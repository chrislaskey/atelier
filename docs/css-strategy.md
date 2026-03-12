# CSS Strategy for Real-Time Preview

## Problem

Atelier lets users type HTML with Tailwind CSS and DaisyUI classes in a textarea and see a live preview. The app's esbuild pipeline only includes CSS classes found in source files at build time. This means arbitrary Tailwind utilities (e.g. `bg-gradient-to-r from-purple-500`) and DaisyUI component classes typed by users won't have corresponding CSS rules, so the preview renders unstyled.

Since Atelier will eventually be embeddable in other applications, the solution should not require modifications to the host app's build pipeline.

## Options Considered

### Option 1: Pre-compiled full CSS files

Load complete, pre-compiled CSS files containing every possible class.

- **DaisyUI**: Available as a [42kB compressed CDN file](https://daisyui.com/docs/cdn/) with all components + a separate `themes.css` for all 34 themes.
- **Tailwind**: No pre-compiled full CSS file exists for v4. The v3 file (~1.2MB) is deprecated. Tailwind v4 is JIT-only.

**Verdict**: Covers DaisyUI classes but *not* arbitrary Tailwind utilities. Incomplete solution.

### Option 2: Tailwind Play CDN in the main page

The [Tailwind v4 Play CDN](https://tailwindcss.com/docs/installation/play-cdn) (`@tailwindcss/browser@4`) is a browser-side JIT compiler. It scans the DOM for class names and generates CSS on the fly. Paired with DaisyUI's CDN CSS, it handles both arbitrary Tailwind utilities and DaisyUI components.

- Officially "development use only" (no SLA, potential performance overhead from DOM scanning)
- Works for staff-facing tools where performance isn't critical
- **Problem**: Loading CDN styles into the main page creates conflicts with the app's own build-pipeline CSS (double-loaded DaisyUI, competing Tailwind rules)

**Verdict**: Solves the class coverage problem but introduces style conflicts.

### Option 3: iframe with Play CDN + DaisyUI CDN (chosen)

Render the preview inside an `<iframe>` whose `srcdoc` loads its own Tailwind Play CDN + DaisyUI CDN. The iframe is an isolated document with its own CSS context.

**Pros:**
- Full coverage of arbitrary Tailwind classes and all DaisyUI components
- Zero style conflicts — iframe CSS is completely isolated from the app
- Embeddable — the iframe approach transfers naturally when Atelier is embedded in other apps
- Theme syncing via `postMessage` keeps preview theme in sync with the app

**Cons:**
- Slightly more implementation complexity (srcdoc construction, postMessage for themes)
- External CDN dependency for the preview (requires internet access)
- "Development use only" caveat for the Tailwind Play CDN (acceptable for staff tooling)

**Verdict**: Best balance of correctness, isolation, and embeddability.

## Implementation

The preview iframe loads:
1. `https://cdn.jsdelivr.net/npm/daisyui@5` — all DaisyUI component styles (42kB compressed)
2. `https://cdn.jsdelivr.net/npm/daisyui@5/themes.css` — all 34 DaisyUI themes
3. `https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4` — Tailwind JIT compiler (runs in browser)

Theme syncing uses `postMessage` from the parent page to the iframe on theme changes.

## References

- [DaisyUI CDN docs](https://daisyui.com/docs/cdn/)
- [Tailwind CSS Play CDN](https://tailwindcss.com/docs/installation/play-cdn)
- [Full compiled Tailwind CSS discussion](https://github.com/tailwindlabs/tailwindcss/discussions/11736)
