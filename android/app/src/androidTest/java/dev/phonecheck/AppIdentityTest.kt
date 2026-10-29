package dev.phonecheck

import android.app.Notification
import android.graphics.BitmapFactory
import android.os.Process
import android.service.notification.StatusBarNotification
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppIdentityTest {
    @Test fun launcherNotificationSourcesKeepTheirNamesAndIcons() {
        // Shell supplies the independent list, unaffected by Phone Check's visibility.
        // Read no real notifications and leave app data and pairing untouched.
        val components = shell("cmd package query-activities --brief --user current " +
            "-a android.intent.action.MAIN -c android.intent.category.LAUNCHER")
        val packages = components.lineSequence().map { it.trim() }
            .filter { it.matches(Regex("[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+")) }
            .map { it.substringBefore('/') }.distinct().toList()
        assertTrue("Device must have launcher apps", packages.isNotEmpty())
        val capture = NotificationCapture(target)
        val notification = Notification.Builder(target, "identity-check")
            .setSmallIcon(R.drawable.ic_phone).setContentTitle("Identity check").build()
        for ((id, packageName) in packages.withIndex()) {
            if (packageName == target.packageName) continue
            val info = target.packageManager.getApplicationInfo(packageName, 0)
            val expectedLabel = target.packageManager.getApplicationLabel(info).toString().take(256)
            val sbn = StatusBarNotification(packageName, packageName, id, null, info.uid,
                0, 0, notification, Process.myUserHandle(), 0)
            val notice = capture.capture(sbn)!!.json
            assertEquals(expectedLabel, notice.getString("app"))
            val bytes = Base64.decode(notice.getString("appIcon"), Base64.NO_WRAP)
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            assertNotNull("App icon must decode", bitmap)
            assertTrue(bitmap.width in 1..96 && bitmap.height in 1..96)
            bitmap.recycle()
            capture.remove(sbn.key)
        }
    }
}
