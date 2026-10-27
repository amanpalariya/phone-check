package dev.phonecheck

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** A bounded, user-started sample satisfies CallStyle's foreground-service requirement. */
class TestbedCallService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val timeout = Runnable { stopSelf() }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = TestNotifications.callNotification(this)
        if (Build.VERSION.SDK_INT >= 34) startForeground(DemoScenario.CALL.number, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        else startForeground(DemoScenario.CALL.number, notification)
        main.removeCallbacks(timeout); main.postDelayed(timeout, 120000)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int) { stopSelf() }
    override fun onTimeout(startId: Int, fgsType: Int) { stopSelf() }
    override fun onDestroy() { main.removeCallbacks(timeout); stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
