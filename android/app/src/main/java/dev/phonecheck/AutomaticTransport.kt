package dev.phonecheck

import org.json.JSONObject

/** Main-thread route changes; notification workers only read the selected transport.
 * Probing never interrupts cloud delivery. Every committed route gets a fresh snapshot.
 * No frames or commands are transferred between routes.
 */
internal class AutomaticTransport(
    private val callbacks: TransportCallbacks,
    private val cloudFactory: (TransportCallbacks) -> NotificationTransport,
    private val localFactory: (String, Int, TransportCallbacks) -> NotificationTransport,
    private val mayUseLocal: () -> Boolean,
    private val localMode: (Boolean) -> Unit,
    private val schedule: (Long, () -> Unit) -> (() -> Unit)
) : NotificationTransport {
    @Volatile private var selected: NotificationTransport? = null
    private var cloud: NotificationTransport? = null
    private var local: NotificationTransport? = null
    private var hosts = emptyList<String>()
    private var port = 0
    private var nextHost = 0
    private var retry: (() -> Unit)? = null
    private var running = false
    private var cloudEpoch = 0
    private var localEpoch = 0

    override fun start() { if (!running) { running = true; startCloud() } }
    private fun startCloud() {
        if (!running || cloud != null) return
        localMode(false)
        val epoch = ++cloudEpoch
        val events = TransportCallbacks(
            onConnected = {
                if (running && epoch == cloudEpoch && (local == null || selected !== local)) {
                    selected = cloud; callbacks.onConnected()
                }
            },
            onMessage = { message ->
                if (running && epoch == cloudEpoch) {
                    if (message.optString("type") == "local_endpoint") endpoint(message)
                    else if (selected === cloud) callbacks.onMessage(message)
                }
            },
            onDisconnected = {
                if (running && epoch == cloudEpoch && selected === cloud) {
                    selected = null; callbacks.onDisconnected()
                }
            },
            onPairingRevoked = {
                if (running && epoch == cloudEpoch) { stop(); callbacks.onPairingRevoked() }
            }
        )
        cloud = cloudFactory(events)
        cloud?.start()
    }
    private fun endpoint(message: JSONObject) {
        val addresses = message.optJSONArray("hosts") ?: return
        val offeredPort = message.optInt("port")
        if (addresses.length() !in 1..8 || offeredPort !in 1024..65535) return
        val offeredHosts = (0 until addresses.length()).map { addresses.optString(it) }
        if (!offeredHosts.all(Pairing::isPrivateIPv4)) return
        val changed = hosts != offeredHosts || port != offeredPort
        hosts = offeredHosts.distinct(); port = offeredPort
        if (changed && local != null && selected !== local) {
            localEpoch++; local?.close(); local = null
        }
        if (local == null && (changed || retry == null)) { retry?.invoke(); retry = null; nextHost = 0; probe() }
    }
    private fun probe() {
        if (!running || local != null || hosts.isEmpty() || !mayUseLocal()) return
        if (nextHost >= hosts.size) { later(); return }
        val host = hosts[nextHost++]
        val epoch = ++localEpoch
        val events = TransportCallbacks(
            onConnected = {
                if (running && epoch == localEpoch) {
                    selected = local
                    // Invalidate queued callbacks before stopping the old route.
                    cloudEpoch++; cloud?.close(); cloud = null
                    localMode(true)
                    callbacks.onDisconnected(); callbacks.onConnected()
                }
            },
            onMessage = { if (running && epoch == localEpoch && selected === local) callbacks.onMessage(it) },
            onDisconnected = {
                if (running && epoch == localEpoch) {
                    val wasSelected = local != null && selected === local
                    localEpoch++; local?.close(); local = null
                    if (wasSelected) {
                        selected = null; callbacks.onDisconnected(); startCloud(); later()
                    } else probe()
                }
            }
        )
        local = localFactory(host, port, events)
        local?.start()
    }
    private fun later() {
        retry?.invoke()
        retry = schedule(30_000) { retry = null; nextHost = 0; probe() }
    }
    override fun send(message: JSONObject) { selected?.send(message) }
    override fun sendBatch(messages: List<JSONObject>) { selected?.sendBatch(messages) }
    override fun disconnect() { selected?.disconnect() }
    override fun stop() {
        running = false; cloudEpoch++; localEpoch++
        retry?.invoke(); retry = null; selected = null
        cloud?.close(); cloud = null; local?.close(); local = null
        hosts = emptyList(); nextHost = 0
        localMode(false)
    }
    override fun close() = stop()
}
