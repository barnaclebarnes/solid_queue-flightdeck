// Reloads the enclosing <turbo-frame> on an interval.
//
//   <turbo-frame id="tiles" src="..." data-controller="refresh"
//                data-refresh-interval-value="5000"></turbo-frame>
//
// Pauses while the tab is hidden, while the user is typing in the frame, and
// while the topbar LIVE switch is off; jitters each delay by +/-10% so that
// many panels on one page do not stampede the server in lockstep.
class RefreshController extends Stimulus.Controller {
  static values = {
    interval: { type: Number, default: 5000 },
    enabled: { type: Boolean, default: true },
    url: String
  }

  connect() {
    this.onVisibilityChange = this.onVisibilityChange.bind(this)
    this.onLiveResumed = this.onLiveResumed.bind(this)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    window.addEventListener("flightdeck:live-resumed", this.onLiveResumed)
    this.schedule()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    window.removeEventListener("flightdeck:live-resumed", this.onLiveResumed)
    this.cancel()
  }

  enabledValueChanged() {
    if (this.enabledValue) {
      this.schedule()
    } else {
      this.cancel()
    }
  }

  intervalValueChanged() {
    if (this.timer) this.schedule()
  }

  toggle() {
    this.enabledValue = !this.enabledValue
  }

  schedule() {
    this.cancel()
    if (!this.enabledValue) return
    this.timer = setTimeout(() => this.tick(), this.nextDelay())
  }

  cancel() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  tick() {
    if (this.shouldRefresh()) this.refresh()
    this.schedule()
  }

  // The frame is rendered without a src so the first page load is a single
  // request. The first tick gives it the URL the page is already showing —
  // filters, state tab and cursor included — and from then on reload() reuses it.
  refresh() {
    const frame = this.frame()
    if (!frame) return

    if (!frame.src && this.hasUrlValue) {
      frame.setAttribute("src", this.urlValue)
    } else if (typeof frame.reload === "function") {
      frame.reload()
    }
  }

  frame() {
    return this.element.tagName === "TURBO-FRAME"
      ? this.element
      : this.element.querySelector("turbo-frame")
  }

  shouldRefresh() {
    if (document.hidden) return false
    if (!this.enabledValue) return false
    if (!this.live) return false
    return !this.hasFocusedInput()
  }

  // Read from the document rather than held here, so a frame swapped in by a
  // turbo-stream after the switch was flipped is paused too.
  get live() {
    return document.documentElement.getAttribute("data-fd-live") !== "off"
  }

  // Resuming refreshes straight away instead of waiting out an interval.
  onLiveResumed() {
    this.refresh()
    this.schedule()
  }

  hasFocusedInput() {
    const active = document.activeElement
    if (!active) return false
    if (!this.element.contains(active)) return false
    return /^(INPUT|SELECT|TEXTAREA)$/.test(active.tagName) || active.isContentEditable
  }

  onVisibilityChange() {
    if (document.hidden) {
      this.cancel()
    } else {
      this.schedule()
    }
  }

  nextDelay() {
    const base = Math.max(1000, this.intervalValue)
    return Math.round(base * (0.9 + Math.random() * 0.2))
  }
}
