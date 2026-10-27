package dev.phonecheck

import android.os.Handler
import org.json.JSONObject
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal interface NotificationTransport : AutoCloseable {
    fun start(pairing: Pairing)
    fun stop()
    fun send(message: JSONObject)
    fun sendBatch(messages: List<JSONObject>)
    fun disconnect()
}

internal class LanTransport(
    private val main: Handler,
    private val mayConnect: () -> Boolean,
    private val onConnecting: () -> Unit,
    private val onConnected: () -> Unit,
    private val onMessage: (JSONObject) -> Unit,
    private val onDisconnected: () -> Unit
) : NotificationTransport {
    private val writer = ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(256))
    @Volatile private var generation = 0
    @Volatile private var attempt = 0
    @Volatile private var link: SecureLink? = null
    private var worker: Thread? = null

    override fun start(pairing: Pairing) {
        stop()
        val epoch = generation
        worker = Thread({
            var delay = 1000L
            while (epoch == generation && !Thread.currentThread().isInterrupted) {
                val session = ++attempt
                val candidate = SecureLink(pairing)
                fun dispatch(action: () -> Unit) {
                    main.post { if (epoch == generation && attempt == session) action() }
                }
                try {
                    if (!mayConnect()) { dispatch(onDisconnected); break }
                    dispatch(onConnecting)
                    val accepted = synchronized(this@LanTransport) {
                        if (epoch == generation) { link = candidate; true } else false
                    }
                    if (!accepted) break
                    candidate.connect()
                    dispatch(onConnected)
                    delay = 1000L
                    while (epoch == generation) {
                        val message = candidate.receive()
                        dispatch { onMessage(message) }
                    }
                } catch (_: Exception) {
                    dispatch(onDisconnected)
                } finally {
                    candidate.close()
                    synchronized(this@LanTransport) { if (link === candidate) link = null }
                }
                if (epoch != generation) break
                try { Thread.sleep(delay) } catch (_: InterruptedException) { break }
                delay = (delay * 2).coerceAtMost(15000L)
            }
        }, "phone-check-link").also { it.start() }
    }
    override fun send(message: JSONObject) = sendBatch(listOf(message))
    override fun sendBatch(messages: List<JSONObject>) {
        val target = link ?: return
        try {
            writer.execute {
                if (link === target) runCatching {
                    for (message in messages) {
                        if (link !== target) return@execute
                        target.send(message)
                    }
                }.onFailure { target.close() }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) { target.close() }
    }
    override fun disconnect() { link?.close() }
    @Synchronized override fun stop() {
        generation++
        worker?.interrupt(); worker = null
        link?.close(); link = null
        writer.queue.clear()
    }
    override fun close() { stop(); writer.shutdownNow() }
}
