// Auto-dismissing toast. Appended into #fd-toasts by a turbo-stream after every
// action, and removed again on a timer (or immediately when dismissed).
class ToastController extends Stimulus.Controller {
  static values = { timeout: { type: Number, default: 6000 } }

  connect() {
    if (this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.element.remove()
  }
}
