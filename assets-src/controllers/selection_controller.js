// Row selection for the failed-jobs bulk bar.
//
// The checkboxes are plain form fields inside the bulk form, so selection works
// with JavaScript disabled too — this controller only reveals the bar and keeps
// the count honest.
class SelectionController extends Stimulus.Controller {
  static targets = ["row", "bar", "count", "all"]

  connect() {
    this.refresh()
  }

  refresh() {
    const selected = this.selected()

    if (this.hasBarTarget) this.barTarget.hidden = selected.length === 0
    if (this.hasCountTarget) this.countTarget.textContent = String(selected.length)

    if (this.hasAllTarget) {
      this.allTarget.checked = selected.length > 0 && selected.length === this.rowTargets.length
      this.allTarget.indeterminate = selected.length > 0 && selected.length < this.rowTargets.length
    }
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.rowTargets.forEach((row) => { row.checked = checked })
    this.refresh()
  }

  selectGroup(event) {
    const group = event.params.group
    this.rowTargets.forEach((row) => {
      if (row.dataset.group === group) row.checked = true
    })
    this.refresh()
  }

  selected() {
    return this.rowTargets.filter((row) => row.checked)
  }
}
