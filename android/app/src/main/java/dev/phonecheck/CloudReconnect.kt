package dev.phonecheck

/** A successful session invalidates every retry from the previous connection attempt. */
internal class CloudReconnect(
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val retry: () -> Unit
) {
    private var generation = 0L
    private var nextDelay = 1000L
    private var cancel: (() -> Unit)? = null

    fun failed() {
        cancel?.invoke()
        val attempt = ++generation
        val delay = nextDelay
        nextDelay = (nextDelay * 2).coerceAtMost(15_000)
        cancel = schedule(delay) {
            if (attempt == generation) { cancel = null; generation++; retry() }
        }
    }
    fun accepted() {
        stop()
        nextDelay = 1000
    }
    fun stop() {
        generation++
        cancel?.invoke(); cancel = null
    }
}
