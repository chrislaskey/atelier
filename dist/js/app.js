// Atelier embedded JS
// Phoenix framework JS (phoenix.js, phoenix_html.js, phoenix_live_view.js)
// is prepended at compile time by Atelier.Assets

let socketPath = document.querySelector("html").getAttribute("phx-socket") || "/live"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let liveSocket = new LiveView.LiveSocket(socketPath, Phoenix.Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", _info => {
  // Simple CSS-based loading indicator
  let bar = document.getElementById("atelier-topbar")
  if (!bar) {
    bar = document.createElement("div")
    bar.id = "atelier-topbar"
    bar.style.cssText = "position:fixed;top:0;left:0;height:2px;background:#29d;z-index:9999;transition:width .3s;width:0"
    document.body.appendChild(bar)
  }
  bar.style.width = "80%"
  bar.style.opacity = "1"
})

window.addEventListener("phx:page-loading-stop", _info => {
  let bar = document.getElementById("atelier-topbar")
  if (bar) {
    bar.style.width = "100%"
    setTimeout(() => { bar.style.opacity = "0"; bar.style.width = "0" }, 300)
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation
window.liveSocket = liveSocket
