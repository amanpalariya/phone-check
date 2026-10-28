package dev.phonecheck

import android.os.Handler
import org.json.JSONObject
import java.io.BufferedReader
import java.io.IOException
import java.net.URI
import java.net.URLEncoder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection

/** RTDB's HTTPS + Server-Sent Events API. No Firebase project or SDK is needed to build.
 * Supply refreshed Firebase Auth ID tokens from the provisioned device identity. The token
 * provider runs on an IO worker; never supply an API key, database secret or service account. */
internal class FirebaseRESTMailbox(
    private val main: Handler,
    databaseURL: String,
    pairID: String,
    sessionID: String,
    private val idToken: () -> String
) : FirebaseMailbox {
    private val base: URI
    private val io = ThreadPoolExecutor(3, 3, 0, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(32))
    private val requests = ConcurrentHashMap.newKeySet<HttpsURLConnection>()
    private val closed = AtomicBoolean(false)
    init {
        val database = URI(databaseURL)
        require(validEndpoint(database) && database.rawQuery == null && database.rawFragment == null &&
            (database.path.isNullOrEmpty() || database.path == "/"))
        require(pairID.matches(Regex("[A-Za-z0-9_-]{1,128}")))
        require(java.util.UUID.fromString(sessionID).toString() == sessionID)
        base = database.resolve("/pairs/$pairID/sessions/$sessionID/")
    }
    override fun observe(path: String, changed: (Result<String?>) -> Unit): () -> Unit {
        val cancelled = AtomicBoolean(false)
        val stream = AtomicReference<HttpsURLConnection?>()
        val future = io.submit {
            try {
                val connection = request(path, null)
                stream.set(connection)
                if (cancelled.get() || closed.get()) return@submit
                if (connection.responseCode != 200 || !connection.contentType.orEmpty().startsWith("text/event-stream"))
                    throw IOException()
                connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    var event = ""
                    val data = StringBuilder()
                    while (!cancelled.get() && !closed.get()) {
                        val line = readLine(reader) ?: throw IOException()
                        when {
                            line.isEmpty() -> {
                                when (event) {
                                    "put" -> {
                                        val objectValue = JSONObject(data.toString())
                                        require(objectValue.getString("path") == "/")
                                        val value = objectValue.get("data")
                                        require(value is String || value === JSONObject.NULL)
                                        main.post { if (!cancelled.get() && !closed.get()) changed(Result.success(value as? String)) }
                                    }
                                    "", "keep-alive" -> Unit
                                    else -> throw IOException() // cancel, auth_revoked, unexpected patch
                                }
                                event = ""; data.clear()
                            }
                            line.startsWith("event:") -> event = line.substring(6).trim()
                            line.startsWith("data:") -> {
                                require(data.length + line.length <= Wire.MAX_FRAME * 2 + 1024)
                                data.append(line.substring(5).trim()).append('\n')
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                main.post {
                    if (!cancelled.get() && !closed.get()) changed(Result.failure(IOException("Firebase stream unavailable")))
                }
            } finally {
                stream.getAndSet(null)?.let { requests.remove(it); it.disconnect() }
            }
        }
        return { cancelled.set(true); future.cancel(true); stream.get()?.disconnect() }
    }
    override fun write(path: String, value: String, completion: (Exception?) -> Unit) {
        if (closed.get()) return
        try {
            io.execute {
                var connection: HttpsURLConnection? = null
                val failure = try {
                    require(value.toByteArray().size <= Wire.MAX_FRAME * 2)
                    val body = JSONObject.quote(value).toByteArray(Charsets.UTF_8)
                    connection = request(path, body)
                    if (connection.responseCode != 204) throw IOException()
                    null
                } catch (_: Exception) { IOException("Firebase write unavailable") }
                finally { connection?.let { requests.remove(it); it.disconnect() } }
                main.post { if (!closed.get()) completion(failure) }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            main.post { if (!closed.get()) completion(IOException("Firebase queue full")) }
        }
    }
    private fun request(path: String, body: ByteArray?): HttpsURLConnection {
        require(path in setOf("phoneToMac", "macToPhone", "phoneToMacAck", "macToPhoneAck"))
        val token = idToken().also { require(it.isNotEmpty()) }
        var endpoint = URI(base.toString() + "$path.json?auth=" + URLEncoder.encode(token, "UTF-8") +
            if (body != null) "&print=silent" else "")
        // Firebase streaming may use HTTP 307. Restrict every redirect before sending credentials.
        repeat(6) {
            check(!closed.get() && !Thread.currentThread().isInterrupted)
            require(validEndpoint(endpoint))
            val connection = endpoint.toURL().openConnection() as HttpsURLConnection
            requests.add(connection)
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 10_000; connection.readTimeout = if (body == null) 45_000 else 15_000
                connection.useCaches = false
                connection.requestMethod = if (body == null) "GET" else "PUT"
                connection.setRequestProperty("Accept", if (body == null) "text/event-stream" else "application/json")
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setFixedLengthStreamingMode(body.size)
                    connection.outputStream.use { it.write(body) }
                }
                if (connection.responseCode != 307) return connection
                endpoint = endpoint.resolve(connection.getHeaderField("Location") ?: throw IOException())
            } catch (error: Exception) {
                requests.remove(connection); connection.disconnect(); throw error
            }
            requests.remove(connection); connection.disconnect()
        }
        throw IOException()
    }
    private fun readLine(reader: BufferedReader): String? {
        val value = StringBuilder()
        while (true) {
            val char = reader.read()
            if (char == -1) return if (value.isEmpty()) null else value.toString()
            if (char == '\n'.code) return value.toString().removeSuffix("\r")
            if (value.length >= Wire.MAX_FRAME * 2 + 1024) throw IOException()
            value.append(char.toChar())
        }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        io.shutdownNow(); requests.forEach { it.disconnect() }; requests.clear()
    }
    private fun validEndpoint(url: URI): Boolean = url.scheme == "https" && url.port == -1 && url.userInfo == null &&
        (url.host?.endsWith(".firebaseio.com") == true || url.host?.endsWith(".firebasedatabase.app") == true)
}
