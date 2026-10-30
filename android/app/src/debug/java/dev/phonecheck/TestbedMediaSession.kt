package dev.phonecheck

import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/** A real OS session: controls update playback/metadata without reposting the notification. */
internal object TestbedMediaSession {
    private var session: MediaSession? = null
    private var playing = false
    private var track = 1
    private var position = 1000L
    fun clear() { session?.release(); session = null; playing = false; track = 1; position = 1000 }
    fun token(context: Context): MediaSession.Token {
        session?.let { return it.sessionToken }
        val created = MediaSession(context, "Phone Check media testbed")
        session = created
        created.setCallback(object : MediaSession.Callback() {
            override fun onPlay() { playing = true; received("play") }
            override fun onPause() { playing = false; received("pause") }
            override fun onSkipToNext() { track++; received("next") }
            override fun onSkipToPrevious() { track = maxOf(1, track - 1); received("previous") }
            override fun onSeekTo(pos: Long) { position = pos; received("seek") }
            override fun onCustomAction(action: String, extras: Bundle?) { if (action == "testbed.like") received("like") }
        }, Handler(Looper.getMainLooper()))
        created.isActive = true
        update()
        return created.sessionToken
    }
    private fun received(operation: String) { TestbedState.record(operation); update() }
    private fun update() {
        session?.setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, "Media")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "Sample artist · Track $track")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, 240000).build())
        session?.setPlaybackState(PlaybackState.Builder()
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, position, if (playing) 1f else 0f)
            .setActions(PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_SKIP_TO_NEXT)
            .addCustomAction(PlaybackState.CustomAction.Builder("testbed.like", "Me gusta", android.R.drawable.btn_star_big_off).build()).build())
    }
}
