export function every(interval, cb) {
  window.setInterval(() => cb(performance.now()), interval)
}

export function now() {
  return performance.now()
}
