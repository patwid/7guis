export function init_dialog() {
  Object.defineProperty(HTMLDialogElement.prototype, "modalopen", {
    get() {
      return this.open
    },

    set(value) {
      if (value) {
        requestAnimationFrame(() => this.showModal())
      } else {
        this.close()
      }
    }
  })
}

export function update_radius(id, value) {
  requestAnimationFrame(() =>
    document.getElementById(id).setAttribute("r", value.toString()))
}
