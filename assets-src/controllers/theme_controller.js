// Light/dark override on top of the CSS `prefers-color-scheme` default.
//
// The stylesheet already renders correctly with no JavaScript at all; this
// controller only writes `data-theme` on <html> and remembers the choice, so
// the page never depends on an inline script to avoid a flash.
class ThemeController extends Stimulus.Controller {
  static targets = ["button"]
  static values = { storageKey: { type: String, default: "flightdeck:theme" } }

  connect() {
    const stored = this.read()
    if (stored) document.documentElement.setAttribute("data-theme", stored)
    this.render()
  }

  toggle() {
    const next = this.current() === "dark" ? "light" : "dark"
    document.documentElement.setAttribute("data-theme", next)
    this.write(next)
    this.render()
  }

  system() {
    document.documentElement.removeAttribute("data-theme")
    this.write(null)
    this.render()
  }

  current() {
    const explicit = document.documentElement.getAttribute("data-theme")
    if (explicit) return explicit
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light"
  }

  // Which icon is visible is decided in CSS by the theme tokens; the only thing
  // that needs saying here is what clicking will do, and it has to stay true
  // after every toggle.
  render() {
    if (!this.hasButtonTarget) return

    const next = this.current() === "dark" ? "light" : "dark"
    const label = `Switch to ${next} theme`

    this.buttonTarget.setAttribute("aria-label", label)
    this.buttonTarget.setAttribute("title", label)
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
      if (value === null) {
        window.localStorage.removeItem(this.storageKeyValue)
      } else {
        window.localStorage.setItem(this.storageKeyValue, value)
      }
    } catch (error) {
      // Private mode / disabled storage: the toggle still works for this page.
    }
  }
}
