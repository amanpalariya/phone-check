package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test

class CloudReconnectTest {
    private class Clock {
        data class Job(val delay: Long, val action: () -> Unit, var cancelled: Boolean = false)
        val jobs = mutableListOf<Job>()
        fun schedule(delay: Long, action: () -> Unit): () -> Unit {
            val job = Job(delay, action); jobs += job
            return { job.cancelled = true }
        }
    }
    @Test fun acceptedOfferPreventsAnOldDisconnectFromReplacingTheNewSession() {
        val clock = Clock(); var requests = 0
        val reconnect = CloudReconnect(clock::schedule) { requests++ }
        reconnect.failed()
        val old = clock.jobs.single()
        reconnect.accepted()
        // A cancelled callback might already have been queued for delivery.
        old.action()
        assertTrue(old.cancelled)
        assertEquals(0, requests)
        reconnect.failed()
        assertEquals(1000L, clock.jobs.last().delay)
        clock.jobs.last().action()
        assertEquals(1, requests)
    }
    @Test fun repeatedFailuresKeepOnlyTheNewestRetryAndBoundTheBackoff() {
        val clock = Clock(); var requests = 0
        val reconnect = CloudReconnect(clock::schedule) { requests++ }
        repeat(8) { reconnect.failed() }
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 15000L, 15000L, 15000L, 15000L), clock.jobs.map { it.delay })
        clock.jobs.forEach { it.action() }
        assertEquals(1, requests)
    }
    @Test fun unansweredOfferRetriesEvenWithoutADatabaseError() {
        val clock = Clock(); var requests = 0
        val reconnect = CloudReconnect(clock::schedule) { requests++ }
        reconnect.awaitingOffer()
        assertEquals(30_000L, clock.jobs.single().delay)
        clock.jobs.single().action()
        assertEquals(1, requests)
    }
    @Test fun acceptedOfferAndStopInvalidateOfferTimeouts() {
        val clock = Clock(); var requests = 0
        val reconnect = CloudReconnect(clock::schedule) { requests++ }
        reconnect.awaitingOffer(); reconnect.accepted()
        clock.jobs.last().action()
        reconnect.awaitingOffer(); reconnect.stop()
        clock.jobs.last().action()
        assertEquals(0, requests)
        assertTrue(clock.jobs.all { it.cancelled })
    }
    @Test fun stoppingTheTransportInvalidatesQueuedRetries() {
        val clock = Clock(); var requests = 0
        val reconnect = CloudReconnect(clock::schedule) { requests++ }
        reconnect.failed(); reconnect.stop()
        clock.jobs.single().action()
        assertEquals(0, requests)
    }
}
