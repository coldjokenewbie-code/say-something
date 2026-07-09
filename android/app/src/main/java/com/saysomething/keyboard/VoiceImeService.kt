package com.saysomething.keyboard

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import java.io.File
import java.util.concurrent.Executors

/**
 * A voice-input keyboard. The user taps the mic, speaks, and the recorded audio
 * is sent to Gemini for transcription + polishing; the result is committed
 * directly into whatever text field is focused — no copy/paste.
 */
class VoiceImeService : InputMethodService() {

    private lateinit var settings: Settings
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private var statusView: TextView? = null
    private var micButton: ImageButton? = null
    private var modeRow: LinearLayout? = null

    private var recorder: MediaRecorder? = null
    private var audioFile: File? = null
    private var recording = false
    private var busy = false

    override fun onCreate() {
        super.onCreate()
        settings = Settings(this)
    }

    override fun onCreateInputView(): View {
        val view = layoutInflater.inflate(R.layout.keyboard_view, null)
        statusView = view.findViewById(R.id.status)
        micButton = view.findViewById(R.id.mic_btn)
        modeRow = view.findViewById(R.id.mode_row)

        micButton?.setOnClickListener { onMicTapped() }

        view.findViewById<Button>(R.id.key_switch).setOnClickListener {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .showInputMethodPicker()
        }
        view.findViewById<Button>(R.id.key_space).setOnClickListener {
            currentInputConnection?.commitText(" ", 1)
        }
        view.findViewById<Button>(R.id.key_backspace).setOnClickListener {
            currentInputConnection?.deleteSurroundingText(1, 0)
        }
        view.findViewById<Button>(R.id.key_enter).setOnClickListener {
            currentInputConnection?.commitText("\n", 1)
        }

        buildModeChips()
        setStatus("按麥克風開始說話")
        return view
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        if (recording) cancelRecording()
    }

    // ---------- mode chips ----------

    private fun buildModeChips() {
        val row = modeRow ?: return
        row.removeAllViews()
        val density = resources.displayMetrics.density
        for (mode in Prompts.MODES) {
            val chip = Button(this)
            chip.text = mode.label
            chip.isAllCaps = false
            chip.textSize = 13f
            chip.setPadding((14 * density).toInt(), 0, (14 * density).toInt(), 0)
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                (40 * density).toInt(),
            )
            lp.setMargins((3 * density).toInt(), 0, (3 * density).toInt(), 0)
            chip.layoutParams = lp
            chip.setOnClickListener {
                settings.modeId = mode.id
                refreshChipStyles()
            }
            chip.tag = mode.id
            row.addView(chip)
        }
        refreshChipStyles()
    }

    private fun refreshChipStyles() {
        val row = modeRow ?: return
        val active = settings.modeId
        for (i in 0 until row.childCount) {
            val chip = row.getChildAt(i) as Button
            if (chip.tag == active) {
                chip.setBackgroundColor(0xFF3A2E1C.toInt())
                chip.setTextColor(0xFFE8A04C.toInt())
            } else {
                chip.setBackgroundColor(0xFF211D19.toInt())
                chip.setTextColor(0xFF9C9489.toInt())
            }
        }
    }

    // ---------- mic / recording ----------

    private fun onMicTapped() {
        if (busy) return
        if (recording) {
            stopAndProcess()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            setStatus("請先開啟麥克風權限(已開啟設定頁)")
            openSettings()
            return
        }
        if (settings.geminiKey.isEmpty()) {
            setStatus("請先在 App 設定 Gemini API key(已開啟設定頁)")
            openSettings()
            return
        }
        startRecording()
    }

    private fun startRecording() {
        val file = File(cacheDir, "say_rec.aac")
        val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioSamplingRate(44100)
            rec.setAudioEncodingBitRate(96000)
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec.start()
        } catch (e: Exception) {
            rec.runCatching { reset() }
            rec.runCatching { release() }
            setStatus("無法啟動錄音:${e.message}")
            return
        }
        recorder = rec
        audioFile = file
        recording = true
        micButton?.setColorFilter(0xFFE25C4A.toInt())
        setStatus("錄音中… 再按一次結束")
    }

    private fun stopAndProcess() {
        val rec = recorder ?: return
        val file = audioFile
        recording = false
        micButton?.clearColorFilter()
        try {
            rec.stop()
        } catch (e: Exception) {
            rec.runCatching { release() }
            recorder = null
            setStatus("錄音太短或失敗,請再試一次")
            return
        }
        rec.release()
        recorder = null

        if (file == null || !file.exists() || file.length() == 0L) {
            setStatus("沒有錄到聲音,請再試一次")
            return
        }

        busy = true
        val mode = Prompts.modeById(settings.modeId)
        setStatus("${mode.label}整理中…")

        val key = settings.geminiKey
        val model = settings.model
        val system = Prompts.buildSystem(mode, settings.outputLang)
        worker.execute {
            try {
                val bytes = file.readBytes()
                val out = Gemini.transcribeAndPolish(key, model, system, bytes, "audio/aac")
                mainHandler.post {
                    busy = false
                    currentInputConnection?.commitText(out, 1)
                    setStatus("完成")
                }
            } catch (e: Exception) {
                mainHandler.post {
                    busy = false
                    setStatus(e.message ?: "發生錯誤")
                }
            }
        }
    }

    private fun cancelRecording() {
        recording = false
        micButton?.clearColorFilter()
        recorder?.runCatching { stop() }
        recorder?.runCatching { release() }
        recorder = null
    }

    private fun openSettings() {
        val intent = Intent(this, SettingsActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun setStatus(text: String) {
        statusView?.text = text
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelRecording()
        worker.shutdownNow()
    }
}
