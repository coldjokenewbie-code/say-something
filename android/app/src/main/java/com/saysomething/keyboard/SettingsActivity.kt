package com.saysomething.keyboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import android.view.inputmethod.InputMethodManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class SettingsActivity : AppCompatActivity() {

    private lateinit var settings: Settings
    private lateinit var keyInput: EditText
    private lateinit var modelSpinner: Spinner
    private lateinit var langSpinner: Spinner

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        settings = Settings(this)

        keyInput = findViewById(R.id.key_input)
        modelSpinner = findViewById(R.id.model_spinner)
        langSpinner = findViewById(R.id.lang_spinner)

        keyInput.setText(settings.geminiKey)

        modelSpinner.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_dropdown_item, Settings.MODELS,
        )
        modelSpinner.setSelection(Settings.MODELS.indexOf(settings.model).coerceAtLeast(0))

        val langLabels = Settings.LANGS.map { it.second }
        langSpinner.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_dropdown_item, langLabels,
        )
        langSpinner.setSelection(
            Settings.LANGS.indexOfFirst { it.first == settings.outputLang }.coerceAtLeast(0),
        )

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            settings.geminiKey = keyInput.text.toString().trim()
            settings.model = Settings.MODELS[modelSpinner.selectedItemPosition]
            settings.outputLang = Settings.LANGS[langSpinner.selectedItemPosition].first
            Toast.makeText(this, "已儲存", Toast.LENGTH_SHORT).show()
        }

        findViewById<Button>(R.id.btn_permission).setOnClickListener {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED
            ) {
                Toast.makeText(this, "麥克風權限已開啟", Toast.LENGTH_SHORT).show()
            } else {
                ActivityCompat.requestPermissions(
                    this, arrayOf(Manifest.permission.RECORD_AUDIO), 1,
                )
            }
        }

        findViewById<Button>(R.id.btn_enable).setOnClickListener {
            startActivity(Intent(AndroidSettings.ACTION_INPUT_METHOD_SETTINGS))
        }

        findViewById<Button>(R.id.btn_pick).setOnClickListener {
            (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
        }
    }
}
