package com.habitica.pomodoro.service

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

/** Asset-backed players, with focus, bounded previews and explicit lifecycle cleanup. */
class PomoAudio(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var ambient: MediaPlayer? = null
    private var effect: MediaPlayer? = null
    private var ambientName = "None"
    private var focus: AudioFocusRequest? = null
    private val manager = context.getSystemService(AudioManager::class.java)
    var onEffectFinished: (() -> Unit)? = null
    val effectPlaying: Boolean get() = effect?.isPlaying == true

    private fun focus(): Boolean {
        if (focus != null) return true
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes()).setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> stopAll()
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        ambient?.pause(); effect?.pause()
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> { ambient?.start(); effect?.start() }
                }
            }.build()
        if (manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { focus = request; return true }
        return false
    }
    private fun attributes() = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private fun player(name: String, volume: Double, loop: Boolean): MediaPlayer? {
        if (name !in soundOptions && name !in ambientOptions || name == "None") return null
        return runCatching {
            if (!focus()) return null
            MediaPlayer().apply {
                setAudioAttributes(attributes())
                context.assets.openFd("audio/$name").use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                val v = volume.coerceIn(0.0, 1.0).toFloat(); setVolume(v, v); isLooping = loop; prepare()
                setOnErrorListener { _, _, _ -> stopAll(); true }
            }
        }.getOrNull()
    }
    fun ambient(name: String, volume: Double) {
        if (name == "None") { stopAmbient(); return }
        if (ambientName == name && ambient?.isPlaying == true) {
            val v = volume.toFloat(); ambient?.setVolume(v, v); return
        }
        stopAmbient()
        ambient = player(name, volume, true); ambientName = name; ambient?.start()
    }
    fun effect(name: String, volume: Double, preview: Boolean = false) {
        handler.removeCallbacksAndMessages(null)
        stopEffect()
        effect = player(name, volume, false)
        effect?.setOnCompletionListener { stopEffect() }
        effect?.start()
        if (preview) handler.postDelayed({ stopAll() }, 8000)
    }
    fun previewAmbient(name: String, volume: Double) {
        stopAll(); ambient(name, volume); handler.postDelayed({ stopAll() }, 8000)
    }
    fun stopAmbient() { ambient?.release(); ambient = null; ambientName = "None"; releaseFocusIfIdle() }
    fun stopEffect() { effect?.release(); effect = null; releaseFocusIfIdle(); onEffectFinished?.invoke() }
    private fun releaseFocusIfIdle() {
        if (ambient == null && effect == null) { focus?.let(manager::abandonAudioFocusRequest); focus = null }
    }
    fun stopAll() { handler.removeCallbacksAndMessages(null); stopAmbient(); stopEffect() }
    companion object {
        val soundOptions = listOf("None", "Sound1.mp3", "Sound2.mp3", "Sound3.mp3", "Sound4.mp3", "Sound5.mp3", "Sound6.mp3", "Sound7.mp3", "Sound8.mp3", "Sound9.mp3", "clockTicking.mp3")
        val ambientOptions = listOf("None", "Ambient Clock.mp3", "Ambient Rain.mp3", "Ambient Crickets.mp3", "Ambient Birds.mp3")
    }
}
