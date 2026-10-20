package com.habitica.pomodoro.service

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import com.habitica.pomodoro.data.QishiLibrary
import com.habitica.pomodoro.data.QishiPreset

/**
 * Asset-backed players + 栖时场景多轨流式, with focus, bounded previews and explicit lifecycle cleanup.
 *
 * 栖时场景（ambientSource=="qishi"）：场景选择/延续逻辑全部在 PomodoroViewModel（可离线测试），
 * 这里只负责播放——每轨一个 MediaPlayer，prepareAsync 从公开站点流式，循环播放；
 * 单轨失败只跳过该轨，全部失败经 lastError/onQishiError 上报。
 */
class PomoAudio(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var ambient: MediaPlayer? = null
    private var effect: MediaPlayer? = null
    private var ambientName = "None"
    private var focus: AudioFocusRequest? = null
    private val manager = context.getSystemService(AudioManager::class.java)
    var onEffectFinished: (() -> Unit)? = null
    val effectPlaying: Boolean get() = effect?.isPlaying == true

    // 栖时场景多轨流式（音频不随包，152MB；从公开站点流式播放）
    private class QishiVoice(val player: MediaPlayer, val trackVolume: Int)
    private val qishiVoices = mutableListOf<QishiVoice>()
    private var qishiSceneId: String? = null
    /** 全轨失败/焦点不可用提示（与 Apple AudioManager.lastError 对应） */
    var lastError: String? = null
        private set
    /** 前台服务把播放错误转发到引擎既有 message 通道 */
    var onQishiError: ((String) -> Unit)? = null
    val qishiPlaying: Boolean get() = qishiVoices.isNotEmpty()

    private fun focus(): Boolean {
        if (focus != null) return true
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes()).setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> stopAll()
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        ambient?.pause(); effect?.pause()
                        qishiVoices.forEach { voice -> runCatching { voice.player.pause() } }
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        ambient?.start(); effect?.start()
                        // 还在 prepareAsync 中的轨道 start() 会抛异常；runCatching 跳过，prepared 回调自会启动
                        qishiVoices.forEach { voice -> runCatching { voice.player.start() } }
                    }
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

    /**
     * 栖时场景混音：每轨一个 MediaPlayer，setDataSource(url) + prepareAsync 流式，循环播放；
     * 轨增益 = track.volume/100 × 用户环境音量。同一场景已在播时只调音量（暂停恢复/设置变更延续）。
     * 单轨准备/播放失败只跳过该轨；全部失败上报错误（与 Apple playQishiScene 语义一致）。
     */
    fun playQishiScene(preset: QishiPreset, volume: Double) {
        if (qishiSceneId == preset.id && qishiVoices.isNotEmpty()) { setQishiVolume(volume); return }
        stopQishi()
        // 停掉自定义单轨（若刚从 custom 模式切换过来）；焦点保留，不足时下面重新申请
        ambient?.release(); ambient = null; ambientName = "None"
        if (!focus()) { surfaceQishiError("无法获取音频焦点，栖时场景未播放"); return }
        for (track in preset.tracks) {
            val player = MediaPlayer()
            val queued = runCatching {
                player.setAudioAttributes(attributes())
                player.setDataSource(QishiLibrary.STREAM_BASE + track.file)
                val v = qishiGain(track.volume, volume); player.setVolume(v, v)
                player.setOnPreparedListener { prepared ->
                    runCatching { prepared.isLooping = true; prepared.start() }
                        .onFailure { dropQishiVoice(player, preset.name) }
                }
                player.setOnErrorListener { _, _, _ -> dropQishiVoice(player, preset.name); true }
                player.prepareAsync()
            }.isSuccess
            if (queued) qishiVoices += QishiVoice(player, track.volume) else runCatching { player.release() }
        }
        if (qishiVoices.isEmpty()) {
            surfaceQishiError("栖时场景播放失败：${preset.name}（音频不可用）")
            releaseFocusIfIdle()
            return
        }
        qishiSceneId = preset.id
        lastError = null
    }

    /** 只调音量不重启播放（暂停恢复/环境音量变更） */
    fun setQishiVolume(volume: Double) {
        for (voice in qishiVoices) {
            val v = qishiGain(voice.trackVolume, volume)
            runCatching { voice.player.setVolume(v, v) }
        }
    }

    fun stopQishi() {
        qishiVoices.forEach { voice -> runCatching { voice.player.release() } }
        qishiVoices.clear()
        qishiSceneId = null
        releaseFocusIfIdle()
    }

    /** 单轨失败：跳过该轨继续混音；全部失败才上报"场景播放失败" */
    private fun dropQishiVoice(player: MediaPlayer, sceneName: String) {
        val index = qishiVoices.indexOfFirst { it.player === player }
        runCatching { player.release() }
        if (index < 0) return
        qishiVoices.removeAt(index)
        if (qishiVoices.isEmpty()) {
            qishiSceneId = null
            surfaceQishiError("栖时场景播放失败：$sceneName（音频不可用）")
            releaseFocusIfIdle()
        }
    }

    private fun surfaceQishiError(message: String) {
        lastError = message
        onQishiError?.invoke(message)
    }

    /** 轨增益 = (栖时混音比例/100) × 用户环境音量，夹到 0..1（与 Apple trackGain 一致） */
    private fun qishiGain(trackVolume: Int, userVolume: Double): Float =
        ((trackVolume.coerceIn(0, 100) / 100f) * userVolume.coerceIn(0.0, 1.0).toFloat()).coerceIn(0f, 1f)

    fun stopAmbient() { ambient?.release(); ambient = null; ambientName = "None"; stopQishi() }
    fun stopEffect() { effect?.release(); effect = null; releaseFocusIfIdle(); onEffectFinished?.invoke() }
    private fun releaseFocusIfIdle() {
        if (ambient == null && effect == null && qishiVoices.isEmpty()) { focus?.let(manager::abandonAudioFocusRequest); focus = null }
    }
    fun stopAll() { handler.removeCallbacksAndMessages(null); stopAmbient(); stopEffect() }
    companion object {
        val soundOptions = listOf("None", "Sound1.mp3", "Sound2.mp3", "Sound3.mp3", "Sound4.mp3", "Sound5.mp3", "Sound6.mp3", "Sound7.mp3", "Sound8.mp3", "Sound9.mp3", "clockTicking.mp3")
        val ambientOptions = listOf("None", "Ambient Clock.mp3", "Ambient Rain.mp3", "Ambient Crickets.mp3", "Ambient Birds.mp3")
    }
}
