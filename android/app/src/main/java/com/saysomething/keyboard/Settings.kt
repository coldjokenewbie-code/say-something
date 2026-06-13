package com.saysomething.keyboard

import android.content.Context

/** Thin wrapper over SharedPreferences, shared by the IME service and the
 *  settings screen. */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("say_something", Context.MODE_PRIVATE)

    var geminiKey: String
        get() = prefs.getString("gemini_key", "") ?: ""
        set(v) = prefs.edit().putString("gemini_key", v).apply()

    var model: String
        get() = prefs.getString("model", "gemini-2.5-flash") ?: "gemini-2.5-flash"
        set(v) = prefs.edit().putString("model", v).apply()

    var outputLang: String
        get() = prefs.getString("output_lang", "same") ?: "same"
        set(v) = prefs.edit().putString("output_lang", v).apply()

    var modeId: String
        get() = prefs.getString("mode", "polish") ?: "polish"
        set(v) = prefs.edit().putString("mode", v).apply()

    companion object {
        val MODELS = listOf("gemini-2.5-flash", "gemini-2.5-pro")
        // Pairs of (stored value, display label)
        val LANGS = listOf(
            "same" to "跟隨原文(中英夾雜保留)",
            "繁體中文" to "繁體中文",
            "English" to "English",
            "日本語" to "日本語",
        )
    }
}
