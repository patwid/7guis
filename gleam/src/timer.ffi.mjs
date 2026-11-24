let pending = null

// Calls `cb(timestamp)` on the next animation frame. At most one frame is
// requested at a time: a new request replaces a pending one, so no two tick
// loops can ever run side by side.
export function next_frame(cb) {
  if (pending !== null) cancelAnimationFrame(pending)
  pending = requestAnimationFrame((timestamp) => {
    pending = null
    cb(timestamp)
  })
}

export function now() {
  return performance.now()
}
