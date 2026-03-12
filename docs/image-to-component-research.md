# Image-to-Component: Research & Options

## Context

Atelier lets users create Phoenix components via natural language prompts sent to Claude. We want to extend this so users can also provide **PNG images** (e.g., exported from Figma) and have Claude generate component code from them.

Two ways users get PNG files from design tools:
1. **"Copy as PNG"** into the clipboard
2. **Download a file** to disk

---

## What's Possible

### Claude Vision API

All current Claude models (Haiku 4.5, Sonnet 4.6, Opus 4.6) support vision. The API accepts images as content blocks alongside text in the `messages` array. PNG is a supported format.

**Supported formats:** PNG, JPEG, GIF, WebP

**Size limits:**
- 5 MB per image (API limit)
- 8000x8000 pixels max (for <= 20 images per request)
- 32 MB total request size

**Optimal sizing:** Images larger than 1568px on the long edge get resized internally. Best to pre-resize to ~1568px max dimension to avoid latency penalty with no quality benefit.

**API format** (base64 -- the approach we'd use):
```json
{
  "model": "claude-sonnet-4-6",
  "max_tokens": 4096,
  "system": "...",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/png",
            "data": "<BASE64_STRING>"
          }
        },
        {
          "type": "text",
          "text": "Create a Phoenix functional component that matches this design..."
        }
      ]
    }
  ]
}
```

Key change: `content` becomes an **array of content blocks** instead of a plain string. This is backward-compatible -- the current string format still works for text-only messages.

### Phoenix LiveView File Uploads

LiveView has built-in file upload support via `allow_upload/3`. It handles chunked uploads over the WebSocket, provides progress tracking, drag-and-drop support, and image preview.

Key features:
- **`allow_upload/3`** in mount to configure accepted types, size limits, max entries
- **`<.live_file_input />`** component renders the file input
- **`phx-drop-target`** attribute enables drag-and-drop on any container (no JS needed)
- **`<.live_img_preview />`** component shows a client-side preview before upload completes
- **`consume_uploaded_entries/3`** to read the uploaded file's binary data server-side

Files are streamed to a temp file on disk (not held in memory). Reading and base64-encoding happens only when consumed.

### Browser Clipboard API for Pasted Images

The `paste` event provides clipboard image data as a `File` object via `clipboardData.files`. This data can be programmatically assigned to a `<input type="file">` element, which is how you feed it into LiveView's upload machinery.

All clipboard image sources behave identically to the browser:
- macOS/Windows screenshots
- "Copy as PNG" from Figma, Sketch, Adobe XD
- "Copy Image" from web browser
- All are exposed as `image/png` regardless of internal clipboard format

### Req HTTP Client

Our Req client sends JSON via `Req.post(url, json: params)`. The `json` option serializes the params map to JSON using Jason. Base64-encoded image data is just a string value inside the JSON -- no special handling needed. A 1568x1568 PNG might be ~500KB-2MB as base64, well within Req's default limits and the API's 32MB request limit.

---

## What's NOT Possible / Limitations

| Limitation | Detail |
|---|---|
| **Claude can't generate images** | Vision is input-only. Claude sees the image and produces text (code). It cannot output or edit images. |
| **No pixel-perfect reproduction** | Claude interprets the design intent, but won't match exact spacing, colors, or layout pixel-for-pixel. It's a starting point, not a screenshot-to-code compiler. |
| **No Figma metadata** | A PNG export loses all Figma layer names, component structure, auto-layout settings, design tokens, etc. Claude only sees pixels. |
| **LiveView uploads require a form** | The `<.live_file_input>` must be inside a form with `phx-change` and `phx-submit`. This affects where the upload UI can go. |
| **Clipboard paste requires JS** | LiveView has no built-in paste support. A small JavaScript hook is needed to capture the paste event and inject the file into the LiveView upload input. |
| **Socket assign memory** | Storing base64 image data in socket assigns keeps it in process memory for the session lifetime. Should be consumed and discarded promptly. |

---

## Options

### Option 1: LiveView Upload + Clipboard Paste Hook

Use LiveView's built-in `allow_upload` for file selection and drag-and-drop, plus a small JS hook for clipboard paste. Both feed into the same upload pipeline.

**Elixir side:**
```elixir
# In mount:
socket = allow_upload(socket, :design_image,
  accept: ~w(.png .jpg .jpeg .webp),
  max_entries: 1,
  max_file_size: 5_000_000
)

# In the prompt submission handler:
image_data = case uploaded_entries(socket, :design_image) do
  {[_|_], []} ->
    consume_uploaded_entries(socket, :design_image, fn %{path: path}, entry ->
      binary = File.read!(path)
      {:ok, %{base64: Base.encode64(binary), media_type: entry.client_type}}
    end)
    |> List.first()
  _ -> nil
end

# Build content blocks:
content = case image_data do
  nil ->
    prompt_text  # plain string, same as today
  %{base64: b64, media_type: mt} ->
    [
      %{type: "image", source: %{type: "base64", media_type: mt, data: b64}},
      %{type: "text", text: prompt_text}
    ]
end
```

**JavaScript hook (~15 lines):**
```javascript
Hooks.PasteUpload = {
  mounted() {
    this.handlePaste = (e) => {
      const files = e.clipboardData?.files;
      if (!files?.length) return;
      const input = this.el.querySelector("input[type=file]");
      if (!input) return;
      const dt = new DataTransfer();
      for (const f of files) if (f.type.startsWith("image/")) dt.items.add(f);
      if (dt.files.length) {
        input.files = dt.files;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
    };
    window.addEventListener("paste", this.handlePaste);
  },
  destroyed() { window.removeEventListener("paste", this.handlePaste); }
};
```

**Pros:**
- Uses LiveView's battle-tested upload infrastructure (chunked transfer, validation, progress, preview)
- Drag-and-drop support comes free with `phx-drop-target`
- `<.live_img_preview>` gives instant thumbnail before upload completes
- File stays on disk until consumed -- low memory footprint
- Clipboard paste and file picker share the same server-side code path
- Handles large files gracefully (chunked upload, configurable size limits)

**Cons:**
- Requires adding `<.live_file_input>` to the template (needs UI design thought)
- Upload form lifecycle adds some complexity (validate event, cancel handling)
- The JS paste hook, while small, is a piece of custom JS to maintain

### Option 2: Client-side Base64 via pushEvent

Skip LiveView uploads entirely. Use JavaScript to read the file (from file input or clipboard), convert to base64 client-side, and send via `pushEvent`.

**JavaScript:**
```javascript
// On paste or file input change:
const reader = new FileReader();
reader.onload = () => {
  this.pushEvent("image_attached", {
    data: reader.result.split(",")[1],  // strip data: prefix
    media_type: file.type,
    name: file.name
  });
};
reader.readAsDataURL(file);
```

**Elixir side:**
```elixir
def handle_event("image_attached", %{"data" => b64, "media_type" => mt}, socket) do
  {:noreply, assign(socket, :attached_image, %{base64: b64, media_type: mt})}
end
```

**Pros:**
- No LiveView upload infrastructure needed -- simpler setup
- Works with a plain `<input type="file">` or clipboard, no `<.live_file_input>` required
- Fewer moving parts on the Elixir side

**Cons:**
- Base64 string sent as a single WebSocket message (no chunking) -- can hit WebSocket frame limits for large images
- Phoenix default WebSocket max frame is ~10MB, but a 5MB PNG becomes ~6.7MB as base64 -- getting close
- The full base64 string lives in socket assigns (process memory) until used
- No built-in progress bar, no `<.live_img_preview>`, no drag-and-drop
- No built-in file validation (type, size) -- must implement manually in JS
- Large payloads can briefly block the LiveView process

### Option 3: Hybrid -- Client-side Resize + LiveView Upload

Same as Option 1, but add client-side image resizing before upload. Since Claude internally downsizes anything beyond 1568px, we can do it upfront to reduce transfer size.

**Additional JS (using canvas):**
```javascript
function resizeIfNeeded(file, maxDim = 1568) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      if (img.width <= maxDim && img.height <= maxDim) {
        resolve(file); // already small enough
        return;
      }
      const scale = maxDim / Math.max(img.width, img.height);
      const canvas = document.createElement("canvas");
      canvas.width = img.width * scale;
      canvas.height = img.height * scale;
      canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
      canvas.toBlob(resolve, file.type);
    };
    img.src = URL.createObjectURL(file);
  });
}
```

**Pros:**
- Everything from Option 1, plus smaller payloads and faster uploads
- Matches what Claude will do internally anyway -- no quality loss
- A 4000x3000 Figma export (~3MB) becomes ~800x600 (~200KB)

**Cons:**
- More JS to maintain
- Canvas resizing can briefly block the main thread for very large images
- Loses original resolution if the user later wants the full-size image for another purpose

---

## Recommendation

**Option 1 (LiveView Upload + Paste Hook)** is the best starting point. It's the most "Phoenix-native" approach, handles edge cases well (large files, validation, progress), and the clipboard paste hook is minimal. Client-side resizing (Option 3) is a nice optimization to add later if upload speed becomes an issue, but isn't necessary to ship v1.

Option 2 (pushEvent) is tempting for its simplicity but the WebSocket frame size concern and lack of built-in upload features make it the weaker choice.

---

## Implementation Scope

Changes needed for Option 1:

| Area | Change |
|---|---|
| **`mount/3`** in `index.ex` | Add `allow_upload(:design_image, ...)` |
| **`apply_prompt/4`** in `index.ex` | Accept optional image data, build content block array |
| **`client.ex`** | No changes needed -- `json: params` handles the new structure |
| **Template** (`index.html.heex`) | Add `<.live_file_input>`, paste zone UI, optional image preview |
| **JS** (`app.js` or colocated hook) | Add `PasteUpload` hook (~15 lines) |
| **Schema** (`schema.ex`) | No changes needed -- image data is transient, not a form field |

The `create_message/1` client function needs **zero changes** -- it already passes the params map as JSON. The only difference is the shape of the `content` value inside `messages`.

---

## Open Questions

1. **UI placement:** Where should the image upload/paste zone go relative to the prompt textarea? Options:
   - Above the textarea (image is primary input)
   - Below the textarea (supplementary to the text prompt)
   - Inline drop zone overlaid on the textarea itself
   - A separate tab or toggle ("Text prompt" vs "Image prompt")

2. **Image + text or image-only?** Should users be able to send just an image (no text prompt), or should a text prompt always be required? Claude works well with image-only but a guiding prompt ("make this a card component with DaisyUI") would likely produce better results.

3. **Image persistence:** Should the attached image survive a generation cycle? Currently the prompt text persists after generation. If a user wants to iterate ("now make the buttons rounded"), should the original image still be attached, or should they re-paste it?

4. **Multiple images?** The API supports up to 100 images per request. Is there a use case for multiple images (e.g., mobile + desktop versions of a design, or a component in different states)?

5. **Image preview in history?** The app stores generation history in localStorage. Should the image be stored with the history snapshot? Base64 images could be large for localStorage (typical limit is 5-10MB total per origin).

6. **Should we resize client-side?** Start without it for simplicity, but worth revisiting if users commonly paste large Figma exports that make the upload feel slow.

7. **Non-prompt use cases:** Should images also work with the other generation modes? For example, pasting a design image into the HTML tab to generate HTML directly, rather than going through the prompt flow?

8. **Anthropic API version header:** The current header is `"anthropic-version": "2023-06-01"`. Vision has been supported since this version (it launched with Claude 3 in early 2024 on this API version), so no header change is needed. But worth verifying in a quick test.
