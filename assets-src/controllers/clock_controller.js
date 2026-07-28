// Ticking clock in the topbar, in the dashboard's display timezone.
//
// The server renders the initial value and the offset, so the clock is correct
// before JavaScript runs and stays in the configured zone rather than the
// viewer's.
class ClockController extends Stimulus.Controller {
  static values = { offset: { type: Number, default: 0 }, label: { type: String, default: "UTC" } }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  tick() {
    const now = new Date(Date.now() + this.offsetValue * 1000)
    const pad = (n) => String(n).padStart(2, "0")
    const time = `${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())}`
    this.element.textContent = `${time} ${this.labelValue}`
  }
}
