package dev.phonecheck

import android.os.Handler

/** Transport composition stays separate from notification capture and listener lifecycle. */
internal fun createBridgeTransport(
    pairing: Pairing,
    callbacks: TransportCallbacks,
    main: Handler,
    mayUseLocal: () -> Boolean,
    onConnecting: () -> Unit
): NotificationTransport {
    fun local(host: String, port: Int, events: TransportCallbacks, connecting: () -> Unit) =
        LanTransport(
            pairing.copy(host = host, port = port), main,
            mayConnect = mayUseLocal,
            onConnecting = connecting,
            onConnected = events.onConnected,
            onMessage = events.onMessage,
            onDisconnected = events.onDisconnected
        )

    if (pairing.isLocalOnly) return local(pairing.host, pairing.port, callbacks, onConnecting)

    return AutomaticTransport(
        callbacks,
        cloudFactory = { CloudTransport(pairing, main, it) },
        localFactory = { host, port, events -> local(host, port, events, {}) },
        mayUseLocal = mayUseLocal,
        localMode = { local ->
            if (local) {
                CloudAccount.database.goOffline()
                CloudAccount.database.purgeOutstandingWrites()
            } else {
                CloudAccount.database.goOnline()
            }
        },
        schedule = { delay, action ->
            val task = Runnable { action() }
            main.postDelayed(task, delay)
            val cancel: () -> Unit = { main.removeCallbacks(task) }
            cancel
        }
    )
}
