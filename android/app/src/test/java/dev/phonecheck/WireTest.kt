package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.DataInputStream

class WireTest {
    private val key = ByteArray(32) { it.toByte() }
    @Test fun directionKeyGoldenVector() {
        val material = key + ByteArray(32) { (it + 32).toByte() } + "00000000-0000-0000-0000-000000000001".toByteArray()
        assertEquals("39afc19d399f1c164d12f101a63f3dbe9a6f0c8706bf9fb6e82e492fc8bfcb58",
            Wire.derive(key, "c2s", material).joinToString("") { "%02x".format(it) })
        assertFalse(Wire.derive(key, "c2s", material).contentEquals(Wire.derive(key, "s2c", material)))
    }
    @Test fun cipherGoldenVectorAndReplayRejection() {
        val outgoing = SessionCipher(key)
        val incoming = SessionCipher(key)
        val plain = "Phone Check".toByteArray()
        val first = outgoing.apply(plain, true)
        assertEquals("5ed4dab0d00cc0d56dcbc22465663226decf0eeb3dc7c106df0005", first.joinToString("") { "%02x".format(it) })
        assertArrayEquals(plain, incoming.apply(first, false))
        assertThrows(Exception::class.java) { incoming.apply(first, false) }
        assertArrayEquals(plain, incoming.apply(outgoing.apply(plain, true), false))
        val tampered = first.clone().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertThrows(Exception::class.java) { SessionCipher(key).apply(tampered, false) }
    }
    @Test fun frameRejectsOversizedAndTruncatedPayloads() {
        assertThrows(Exception::class.java) { Wire.read(DataInputStream(ByteArrayInputStream(byteArrayOf(0x7f, -1, -1, -1)))) }
        assertThrows(Exception::class.java) { Wire.read(DataInputStream(ByteArrayInputStream(byteArrayOf(0, 0, 0, 8, 1)))) }
    }
    @Test fun pairingAcceptsOnlyPrivateLiteralAddressesAndStrongKeys() {
        val secret = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(key)
        assertEquals("192.168.1.8", Pairing.parse("pc1|192.168.1.8|47831|$secret").host)
        for (host in listOf("8.8.8.8", "localhost", "127.0.0.1", "192.168.1.999", "172.32.1.1", "example.com")) {
            assertThrows(Exception::class.java) { Pairing.parse("pc1|$host|47831|$secret") }
        }
        assertThrows(Exception::class.java) { Pairing.parse("pc1|10.0.0.1|47831|YQ") }
    }
}
