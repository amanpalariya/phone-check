package dev.phonecheck

import android.app.Activity
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

/** Play services owns camera access; only the QR payload returns to Phone Check. */
internal fun scanPairingCode(activity: Activity, onComplete: (String?, String?) -> Unit) {
    val options = GmsBarcodeScannerOptions.Builder()
        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
        .enableAutoZoom()
        .build()
    // Activity-scoped Task listeners detach onStop, including when the scanner opens.
    // Ignore a result if its originating screen has since been destroyed.
    runCatching {
        GmsBarcodeScanning.getClient(activity, options).startScan().addOnCompleteListener { task ->
            if (!activity.isDestroyed) {
                when {
                    task.isCanceled -> onComplete(null, null)
                    task.isSuccessful -> onComplete(task.result.rawValue ?: "", null)
                    else -> onComplete(null, "Scanner unavailable. Try again or enter the code.")
                }
            }
        }
    }.onFailure {
        onComplete(null, "Scanner unavailable. Try again or enter the code.")
    }
}
