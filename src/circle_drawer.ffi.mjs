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
