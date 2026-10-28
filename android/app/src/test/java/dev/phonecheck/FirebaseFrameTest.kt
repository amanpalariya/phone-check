package dev.phonecheck

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class FirebaseFrameTest {
    private val id = "00000000-0000-0000-0000-000000000001"
    private val secret = ByteArray(32) { it.toByte() }
    private fun session(sessionID: String = id) = FirebaseSession(sessionID, secret, 1_000_000, 100_000)
    @Test fun orderedEncryptedDeliveryDuplicatesAndCommands() {
        val phone = FirebaseFrameCodec(session(), true)
        val mac = FirebaseFrameCodec(session(), false)
        val first = phone.encode(JSONObject().put("type", "snapshot_begin"), 1, 100_000)
        assertEquals("snapshot_begin", mac.decode(first, 100_000)!!.getString("type"))
        assertNull(mac.decode(first, 100_000))
        val next = phone.encode(JSONObject().put("type", "upsert").put("phoneInUse", true), 2, 100_000)
        assertTrue(mac.decode(next, 100_000)!!.getBoolean("phoneInUse"))
        val command = mac.encode(JSONObject().put("type", "dismiss"), 1, 100_000)
        assertEquals("dismiss", phone.decode(command, 100_000)!!.getString("type"))
        assertFalse(first.contains("snapshot_begin"))
    }
    @Test fun rejectsSkippedExpiredTamperedAndWrongSessionPackets() {
        val packet = FirebaseFrameCodec(session(), true).encode(JSONObject().put("type", "action"), 1, 100_000)
        val skipped = JSONObject(packet).put("sequence", 2).toString()
        assertThrows(Exception::class.java) { FirebaseFrameCodec(session(), false).decode(skipped, 100_000) }
        assertThrows(Exception::class.java) { FirebaseFrameCodec(session(), false).decode(packet, 130_000) }
        val tampered = JSONObject(packet)
        val bytes = Wire.unbase64(tampered.getString("payload"))
        bytes[0] = (bytes[0].toInt() xor 1).toByte()
        tampered.put("payload", Wire.b64(bytes))
        assertThrows(Exception::class.java) { FirebaseFrameCodec(session(), false).decode(tampered.toString(), 100_000) }
        val other = session("00000000-0000-0000-0000-000000000002")
        assertThrows(Exception::class.java) { FirebaseFrameCodec(other, false).decode(packet, 100_000) }
    }
    @Test fun decodesSwiftEncryptedFrame() {
        val packet = JSONObject().put("sequence", 1).put("payload", "IANdfRKCz0knN7dsmuZAitTlw7mwUAJ5djkEWzhWBzf0wiylsdsloXutAfQl5kmu9TJXhLIeJ3wduJSkfnS4iTT4VmRYo370vU6qWTekgHwTrfse4ZHXHUrIq7zpqQUsU0wZJi1NLhreRrnXPeH5xM4UNZBZbxsbZJSlDg2J3UhENMPbO+EVQUM+i3jVqCHHnSok/KVZZjWD8RhhPUzm5g==")
        val message = FirebaseFrameCodec(session(), false).decode(packet.toString(), 100_000)!!
        assertEquals("upsert", message.getString("type"))
        assertTrue(message.getBoolean("phoneInUse"))
        assertEquals(100_000, message.getLong("sentAt"))
    }
    @Test fun shortLivedSessionAndCrossPlatformKeyVector() {
        assertThrows(Exception::class.java) { FirebaseSession(id, secret, 1_000_001, 100_000) }
        assertThrows(Exception::class.java) { FirebaseSession(id, secret, 100_000, 100_000) }
        assertThrows(Exception::class.java) { FirebaseSession(id, byteArrayOf(1), 200_000, 100_000) }
        assertEquals("de8f5b6b7d7fbcf1c1a5c40286b5fd8b03ac56d1ce415789f495e4f7ea0863e3", Wire.derive(secret, "firebase-phoneToMac", id.toByteArray()).joinToString("") { "%02x".format(it) })
    }
}
