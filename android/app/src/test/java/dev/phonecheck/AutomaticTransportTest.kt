package dev.phonecheck

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AutomaticTransportTest {
    private class Link(val events: TransportCallbacks) : NotificationTransport {
        val sent = mutableListOf<String>()
        var closed = false
        override fun start() {}
        override fun stop() { closed = true }
        override fun close() = stop()
        override fun disconnect() { events.onDisconnected() }
        override fun send(message: JSONObject) { sent += message.getString("type") }
        override fun sendBatch(messages: List<JSONObject>) { messages.forEach(::send) }
    }
    private class Fixture {
        val clouds = mutableListOf<Link>()
        val locals = mutableListOf<Link>()
        val addresses = mutableListOf<String>()
        val timers = mutableListOf<() -> Unit>()
        var allowed = true
        var offline = false
        var connected = 0
        var disconnected = 0
        var revoked = 0
        val received = mutableListOf<String>()
        val route = AutomaticTransport(
            TransportCallbacks({ connected++ }, { received += it.getString("type") }, { disconnected++ }, { revoked++ }),
            cloudFactory = { Link(it).also(clouds::add) },
            localFactory = { host, _, callbacks -> addresses += host; Link(callbacks).also(locals::add) },
            mayUseLocal = { allowed }, localMode = { offline = it },
            schedule = { _, action -> timers += action; { timers.remove(action); Unit } }
        )
        init { route.start(); clouds.last().events.onConnected() }
        fun endpoint(vararg hosts: String) = clouds.last().events.onMessage(JSONObject()
            .put("type", "local_endpoint").put("hosts", JSONArray(hosts.toList())).put("port", 47831))
        fun send() = route.send(JSONObject().put("type", "upsert"))
        fun tick() { val action = timers.removeAt(0); action() }
    }
    @Test fun probingKeepsCloudUntilAuthenticatedAndThenOnlyUsesLocal() {
        val f = Fixture(); f.endpoint("192.168.1.2"); f.send()
        assertEquals(listOf("upsert"), f.clouds.single().sent)
        assertFalse(f.offline)
        f.locals.single().events.onConnected(); f.send()
        assertTrue(f.clouds.single().closed); assertTrue(f.offline)
        assertEquals(listOf("upsert"), f.locals.single().sent)
        assertEquals(1, f.clouds.single().sent.size)
        assertEquals(2, f.connected); assertEquals(1, f.disconnected)
        assertTrue(f.received.isEmpty())
    }
    @Test fun failureFallsBackWithFreshCloudAndDoesNotReplayQueuedFrames() {
        val f = Fixture(); f.endpoint("10.1.2.3"); val oldCloud = f.clouds.single()
        f.locals.single().events.onConnected(); f.send(); f.locals.single().disconnect()
        assertFalse(f.offline); assertEquals(2, f.clouds.size)
        f.send(); assertTrue(f.clouds.last().sent.isEmpty())
        f.clouds.last().events.onConnected(); f.send()
        assertEquals(listOf("upsert"), f.clouds.last().sent)
        oldCloud.events.onConnected(); oldCloud.events.onMessage(JSONObject().put("type", "command"))
        assertTrue(f.received.isEmpty()); assertEquals(3, f.connected)
    }
    @Test fun triesEveryAddressAndRetriesWithoutDroppingCloud() {
        val f = Fixture(); f.endpoint("10.0.0.1", "192.168.1.3")
        f.locals[0].disconnect(); assertEquals(2, f.locals.size)
        f.locals[1].disconnect(); f.send()
        assertEquals(listOf("10.0.0.1", "192.168.1.3"), f.addresses)
        assertEquals(0, f.disconnected); assertEquals(1, f.timers.size)
        f.tick(); assertEquals("10.0.0.1", f.addresses.last())
    }
    @Test fun deniedPermissionRetainsWorkingCloud() {
        val f = Fixture(); f.allowed = false; f.endpoint("10.0.0.1"); f.send()
        assertTrue(f.locals.isEmpty()); assertFalse(f.offline)
        assertEquals(listOf("upsert"), f.clouds.single().sent)
    }
    @Test fun malformedEndpointsNeverConnect() {
        val f = Fixture()
        f.endpoint("8.8.8.8"); f.endpoint("localhost"); f.endpoint("10.0.0.1", "127.0.0.1")
        f.endpoint(*(1..9).map { "10.0.0.$it" }.toTypedArray())
        assertTrue(f.locals.isEmpty())
    }
    @Test fun stopCancelsRetriesAndIgnoresLateCallbacks() {
        val f = Fixture(); f.endpoint("10.0.0.1"); f.locals.single().disconnect()
        f.route.stop(); assertTrue(f.timers.isEmpty())
        f.locals.single().events.onConnected(); f.clouds.single().events.onConnected(); f.send()
        assertFalse(f.offline); assertEquals(1, f.connected); assertTrue(f.clouds.single().sent.isEmpty())
    }
    @Test fun refreshesAddressesAfterLocalFailure() {
        val f = Fixture(); f.endpoint("10.0.0.1"); f.locals.single().events.onConnected()
        f.locals.single().disconnect(); f.clouds.last().events.onConnected(); f.endpoint("192.168.4.2")
        assertEquals("192.168.4.2", f.addresses.last()); assertTrue(f.timers.isEmpty())
    }
    @Test fun changedAddressCancelsAnOlderProbe() {
        val f = Fixture(); f.endpoint("10.0.0.1"); val old = f.locals.single()
        f.endpoint("192.168.4.2")
        assertTrue(old.closed); assertEquals("192.168.4.2", f.addresses.last())
        old.events.onConnected(); assertFalse(f.offline)
        f.send(); assertEquals(listOf("upsert"), f.clouds.single().sent)
    }
    @Test fun cachedAddressCanRecoverWhileCloudReconnects() {
        val f = Fixture(); f.endpoint("10.0.0.1"); f.locals.single().events.onConnected()
        f.locals.single().disconnect(); f.tick(); f.locals.last().events.onConnected(); f.send()
        assertTrue(f.offline); assertTrue(f.clouds.last().closed)
        assertEquals(listOf("upsert"), f.locals.last().sent)
    }
    @Test fun revocationClosesBothRoutes() {
        val f = Fixture(); f.endpoint("10.0.0.1"); f.clouds.single().events.onPairingRevoked()
        assertTrue(f.clouds.single().closed); assertTrue(f.locals.single().closed)
        assertEquals(1, f.revoked)
    }
}
