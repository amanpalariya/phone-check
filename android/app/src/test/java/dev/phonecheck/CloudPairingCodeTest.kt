package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class CloudPairingCodeTest {
    private val secret = ByteArray(32) { it.toByte() }
    private val encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(secret)
    private val id = "22222222-2222-4222-8222-222222222222"
    private val code = "pc2|test-project|owner|$id|$encoded"
    @Test fun cloudPairingDoesNotUseAnIpAndSurvivesSecureStoreSerialization() {
        val pairing = Pairing.parse(code, "test-project")
        assertEquals("owner", pairing.ownerUID)
        assertEquals(id, pairing.pairID)
        assertEquals("", pairing.host)
        assertArrayEquals(secret, Pairing.restore(pairing.json()).secret)
        assertEquals(pairing.peer, Pairing.restore(pairing.json()).peer)
        assertEquals(id, Pairing.restore(pairing.json()).pairID)
    }
    @Test fun localPairingNeedsNoProjectOrAccountAndSurvivesStorage() {
        val pairing = Pairing.parse("pc1|192.168.1.2|47831|$encoded")
        assertTrue(pairing.isLocalOnly)
        assertNull(pairing.ownerUID); assertNull(pairing.pairID)
        val restored = Pairing.restore(pairing.json())
        assertTrue(restored.isLocalOnly); assertEquals(pairing.host, restored.host)
        assertEquals(pairing.port, restored.port); assertEquals(pairing.peer, restored.peer)
        assertArrayEquals(secret, restored.secret)
        assertFalse(Pairing.parse(code, "test-project").isLocalOnly)
    }
    @Test fun localPairingRefusesPublicHostsAndInvalidPorts() {
        for (endpoint in listOf("8.8.8.8|47831", "localhost|47831", "127.0.0.1|47831", "10.0.0.2|80", "10.0.0.2|65536")) {
            assertThrows(IllegalArgumentException::class.java) { Pairing.parse("pc1|$endpoint|$encoded") }
        }
    }
    @Test fun refusesOtherProjectsAndMalformedSecrets() {
        for (candidate in listOf(code.replace("test-project", "other"), code.replace(encoded, "AA"), code.replace(id, "invalid"))) {
            assertThrows(IllegalArgumentException::class.java) { Pairing.parse(candidate, "test-project") }
        }
    }
    @Test fun everyScanCreatesAFreshDeviceIdentity() {
        assertNotEquals(Pairing.parse(code, "test-project").peer, Pairing.parse(code, "test-project").peer)
    }
}
