package dev.phonecheck

import android.app.Notification
import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Base64
import java.io.ByteArrayOutputStream

/** Reads only OS-provided bitmaps or granted local content URIs, with bounded previews. */
internal class NotificationImages(private val context: Context) {
    private val icons = mutableMapOf<String, String>()
    fun clear() = icons.clear()
    fun removeIcon(packageName: String) { icons.remove(packageName) }
    fun appIcon(packageName: String): String? {
        icons[packageName]?.let { return it }
        val icon = runCatching {
            val drawable = context.packageManager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, 48, 48); drawable.draw(Canvas(bitmap))
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream); bitmap.recycle()
            if (stream.size() > 12288) null else Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        }.getOrNull()
        // A temporary lookup failure must not suppress the icon until disconnect.
        if (icon != null) icons[packageName] = icon
        return icon
    }
    @Suppress("DEPRECATION")
    fun picture(notification: Notification): String? = runCatching {
        val extras = notification.extras
        val bitmap = if (Build.VERSION.SDK_INT >= 33) extras.getParcelable(Notification.EXTRA_PICTURE, Bitmap::class.java)
            else extras.getParcelable<Bitmap>(Notification.EXTRA_PICTURE)
        if (bitmap != null) return encode(bitmap)
        val icon = if (Build.VERSION.SDK_INT >= 33) extras.getParcelable(Notification.EXTRA_PICTURE_ICON, Icon::class.java)
            else if (Build.VERSION.SDK_INT >= 31) extras.getParcelable<Icon>(Notification.EXTRA_PICTURE_ICON) else null
        icon ?: return null
        val source = when (icon.type) {
            Icon.TYPE_URI, Icon.TYPE_URI_ADAPTIVE_BITMAP -> readLocalImage(icon.uri) // Modern Android moves picture bitmaps to granted URIs.
            else -> (icon.loadDrawable(context) as? BitmapDrawable)?.bitmap
        } ?: return null
        val result = encode(source)
        if (icon.type == Icon.TYPE_URI || icon.type == Icon.TYPE_URI_ADAPTIVE_BITMAP) source.recycle()
        result
    }.getOrNull()
    private fun readLocalImage(uri: android.net.Uri): Bitmap? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT && uri.scheme != ContentResolver.SCHEME_ANDROID_RESOURCE) return null
        val data = context.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() + count > 2 * 1024 * 1024) return null
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth !in 1..16384 || bounds.outHeight !in 1..16384) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 960) sample *= 2
        return BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }
    fun actionArtwork(notification: Notification): String? = runCatching {
        val icon = notification.getLargeIcon() ?: return null
        val localUri = icon.type == Icon.TYPE_URI || icon.type == Icon.TYPE_URI_ADAPTIVE_BITMAP
        val bitmap = (if (localUri) readLocalImage(icon.uri) else (icon.loadDrawable(context) as? BitmapDrawable)?.bitmap) ?: return null
        val result = encode(bitmap)
        if (localUri) bitmap.recycle()
        result
    }.getOrNull()
    fun artwork(bitmap: Bitmap?): String? = bitmap?.let { runCatching { encode(it) }.getOrNull() }
    fun actionIcon(icon: Icon?): String? = runCatching {
        icon ?: return null
        if (icon.type == Icon.TYPE_URI || icon.type == Icon.TYPE_URI_ADAPTIVE_BITMAP) return null
        val drawable = icon.loadDrawable(context) ?: return null
        val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, 48, 48); drawable.draw(Canvas(bitmap))
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream); bitmap.recycle()
        if (stream.size() > 12288) null else Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }.getOrNull()
    private fun encode(source: Bitmap): String? {
        if (source.width.toLong() * source.height > 32_000_000) return null
        val software = if (source.config == Bitmap.Config.HARDWARE) source.copy(Bitmap.Config.ARGB_8888, false) else source
        software ?: return null
        val scale = minOf(1.0, 480.0 / maxOf(software.width, software.height))
        val preview = Bitmap.createScaledBitmap(software, (software.width * scale).toInt().coerceAtLeast(1),
            (software.height * scale).toInt().coerceAtLeast(1), true)
        val stream = ByteArrayOutputStream()
        preview.compress(Bitmap.CompressFormat.JPEG, 55, stream)
        if (stream.size() > 32768) { stream.reset(); preview.compress(Bitmap.CompressFormat.JPEG, 20, stream) }
        if (preview !== software) preview.recycle()
        if (software !== source) software.recycle()
        return if (stream.size() > 32768) null else Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
