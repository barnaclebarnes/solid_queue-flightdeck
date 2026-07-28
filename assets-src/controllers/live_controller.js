// The LIVE indicator: one switch for every polling frame on the page.
//
// The state lives in a `data-fd-live` attribute on <html> rather than in this
// controller, so refresh controllers can read it without knowing about this one
// — and so a frame that arrives later (via a turbo-stream) is paused too.
class LiveController extends Stimulus.Controller {
  static targets = ["label"]
  static values = { interval: { type: Number, default: 5000 }, storageKey: { type: String, default: "flightdeck:live" } }

  connect() {
    this.apply(this.read() !== "off")
  }

  toggle() {
    this.apply(!this.enabled)
  }

  get enabled() {
    return document.documentElement.getAttribute("data-fd-live") !== "off"
  }

  apply(enabled) {
    document.documentElement.setAttribute("data-fd-live", enabled ? "on" : "off")
    this.element.classList.toggle("off", !enabled)
    this.element.setAttribute("aria-pressed", String(enabled))
    this.write(enabled ? "on" : "off")

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = enabled ? `LIVE · ${this.seconds}s` : "PAUSED"
    }

    // Resuming should feel immediate rather than waiting out a whole interval.
    if (enabled) {
      window.dispatchEvent(new CustomEvent("flightdeck:live-resumed"))
    }
  }

  get seconds() {
    return Math.round(this.intervalValue / 1000)
  }

  read() {
    try {
      return window.localStorage.getItem(this.storageKeyValue)
    } catch (error) {
      return null
    }
  }

  write(value) {
    try {
      window.localStorage.setItem(this.storageKeyValue, value)
    } catch (error) {
      // Storage unavailable: the toggle still works for this page.
    }
  }
}
