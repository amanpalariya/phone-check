package dev.phonecheck

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal object Wire {
    const val MAX_FRAME = 1_048_576
    private val random = SecureRandom()
    fun random() = ByteArray(32).also(random::nextBytes)
    fun b64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
    fun unbase64(value: String): ByteArray = Base64.getDecoder().decode(value)
    fun derive(secret: ByteArray, label: String, material: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return mac.doFinal("phonecheck-v1/$label/".toByteArray() + material)
    }
    fun read(input: DataInputStream): ByteArray {
        val size = input.readInt()
        require(size in 1..MAX_FRAME)
        return ByteArray(size).also(input::readFully)
    }
    fun write(output: DataOutputStream, bytes: ByteArray) {
        require(bytes.size in 1..MAX_FRAME)
        output.writeInt(bytes.size); output.write(bytes); output.flush()
    }
}

internal class SessionCipher(private val key: ByteArray) {
    private var sequence = 0L
    fun apply(bytes: ByteArray, encrypt: Boolean): ByteArray {
        check(sequence >= 0 && sequence < Long.MAX_VALUE)
        val nonce = ByteBuffer.allocate(12).putInt(0).putLong(sequence).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(if (encrypt) Cipher.ENCRYPT_MODE else Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD("phonecheck-v1".toByteArray())
        return cipher.doFinal(bytes).also { sequence++ }
    }
}

internal data class Pairing(val host: String, val port: Int, val secret: ByteArray, val peer: String,
    val ownerUID: String? = null, val pairID: String? = null) {
    val isLocalOnly: Boolean get() = ownerUID == null && pairID == null
    fun json() = JSONObject().put("host", host).put("port", port)
        .put("secret", Wire.b64(secret)).put("peer", peer)
        .put("ownerUID", ownerUID).put("pairID", pairID)
    companion object {
        fun parse(code: String, projectID: String? = null): Pairing {
            val parts = code.trim().split('|')
            if (parts.size == 5 && parts[0] == "pc2") {
                require(parts[1] == projectID)
                require(parts[2].matches(Regex("[A-Za-z0-9_-]{1,128}")))
                require(java.util.UUID.fromString(parts[3]).toString() == parts[3])
                val secret = Base64.getUrlDecoder().decode(parts[4]).also { require(it.size == 32) }
                return Pairing("", 0, secret, java.util.UUID.randomUUID().toString(), parts[2], parts[3])
            }
            require(parts.size == 4 && parts[0] == "pc1")
            // Literal private IPv4 only. Never send pairing material to a public endpoint.
            require(isPrivateIPv4(parts[1]))
            val port = parts[2].toInt().also { require(it in 1024..65535) }
            val secret = Base64.getUrlDecoder().decode(parts[3]).also { require(it.size == 32) }
            return Pairing(parts[1], port, secret, java.util.UUID.randomUUID().toString())
        }
        fun restore(json: JSONObject) = Pairing(json.getString("host"), json.getInt("port"),
            Wire.unbase64(json.getString("secret")), json.getString("peer"),
            json.optString("ownerUID").takeIf { it.isNotEmpty() && it != "null" },
            json.optString("pairID").takeIf { it.isNotEmpty() && it != "null" })
        fun isPrivateIPv4(host: String): Boolean {
            val parts = host.split('.')
            if (parts.size != 4) return false
            val p = parts.map { it.toIntOrNull() ?: return false }
            if (p.any { it !in 0..255 }) return false
            return p[0] == 10 || p[0] == 192 && p[1] == 168 || p[0] == 172 && p[1] in 16..31
        }
    }
}

internal class SecureLink(private val pairing: Pairing) : AutoCloseable {
    private val socket = Socket()
    private lateinit var input: DataInputStream
    private lateinit var output: DataOutputStream
    private lateinit var outgoing: SessionCipher
    private lateinit var incoming: SessionCipher
    fun connect() {
        require(Pairing.isPrivateIPv4(pairing.host))
        socket.connect(InetSocketAddress(InetAddress.getByName(pairing.host), pairing.port), 5000)
        socket.soTimeout = 10000; socket.tcpNoDelay = true
        input = DataInputStream(socket.getInputStream())
        output = DataOutputStream(socket.getOutputStream())
        val hello = JSONObject(String(Wire.read(input), Charsets.UTF_8))
        require(hello.getString("type") == "challenge")
        val server = Wire.unbase64(hello.getString("nonce")).also { require(it.size == 32) }
        val client = Wire.random()
        val material = server + client + pairing.peer.toByteArray()
        val auth = JSONObject().put("type", "authenticate").put("peer", pairing.peer)
            .put("nonce", Wire.b64(client)).put("proof", Wire.b64(Wire.derive(pairing.secret, "client-proof", material)))
        Wire.write(output, auth.toString().toByteArray())
        val ready = JSONObject(String(Wire.read(input), Charsets.UTF_8))
        require(ready.getString("type") == "ready")
        require(MessageDigest.isEqual(Wire.unbase64(ready.getString("proof")),
            Wire.derive(pairing.secret, "server-proof", material)))
        outgoing = SessionCipher(Wire.derive(pairing.secret, "c2s", material))
        incoming = SessionCipher(Wire.derive(pairing.secret, "s2c", material))
        socket.soTimeout = 45000
        val model = android.os.Build.MODEL.trim()
        if (model.isNotEmpty()) {
            send(JSONObject().put("type", "device_info").put("deviceName", model.take(128)))
        }
    }
    @Synchronized fun send(message: JSONObject) {
        Wire.write(output, outgoing.apply(message.toString().toByteArray(Charsets.UTF_8), true))
    }
    fun receive(): JSONObject = JSONObject(String(incoming.apply(Wire.read(input), false), Charsets.UTF_8))
    override fun close() { runCatching { socket.close() } }
}
