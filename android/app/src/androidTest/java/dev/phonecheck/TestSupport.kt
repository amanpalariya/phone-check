package dev.phonecheck

import android.app.NotificationManager
import android.content.ComponentName
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileInputStream
import java.net.Socket
import java.util.UUID

internal val instrumentation get() = InstrumentationRegistry.getInstrumentation()
internal val target get() = instrumentation.targetContext
internal fun onMain(action: () -> Unit) = instrumentation.runOnMainSync(action)
internal fun shell(command: String): String {
    return instrumentation.uiAutomation.executeShellCommand(command).use {
        FileInputStream(it.fileDescriptor).bufferedReader().readText()
    }
}
internal fun waitFor(label: String, timeout: Long = 20000, condition: () -> Boolean) {
    val until = SystemClock.elapsedRealtime() + timeout
    while (SystemClock.elapsedRealtime() < until) {
        if (condition()) return
        SystemClock.sleep(100)
    }
    fail("Timed out: $label")
}
internal fun host(action: String = "state", title: String? = null, actionTitle: String? = null, text: String? = null): JSONObject {
    Socket().use { socket ->
        socket.connect(java.net.InetSocketAddress("10.0.2.2", 47832), 3000)
        socket.soTimeout = 3000
        val request = JSONObject().put("action", action).put("id", UUID.randomUUID().toString())
        if (title != null) request.put("title", title)
        if (actionTitle != null) request.put("actionTitle", actionTitle)
        if (text != null) request.put("text", text)
        socket.getOutputStream().write((request.toString() + "\n").toByteArray())
        return JSONObject(socket.getInputStream().bufferedReader().readLine())
    }
}
internal fun titles(): List<String> {
    val array = host().getJSONArray("titles")
    return (0 until array.length()).map { array.getString(it) }
}
internal fun post(id: Int, title: String, ongoing: Boolean = false) {
    shell("am broadcast -f 0x20 -n dev.phonecheck.fixture/.FixtureReceiver -a fixture.POST --ei id $id --es title $title --ez ongoing $ongoing")
}
internal fun clear(id: Int) {
    shell("am broadcast -f 0x20 -n dev.phonecheck.fixture/.FixtureReceiver -a fixture.CLEAR --ei id $id")
}
