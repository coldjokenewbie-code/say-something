package com.saysomething.keyboard

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object Gemini {

    /**
     * Sends recorded audio to the Gemini generateContent endpoint with a system
     * instruction, and returns the polished text. Runs synchronously — call it
     * off the main thread.
     */
    fun transcribeAndPolish(
        apiKey: String,
        model: String,
        system: String,
        audioBytes: ByteArray,
        mime: String,
    ): String {
        val endpoint =
            "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey"

        val parts = JSONArray()
            .put(
                JSONObject().put(
                    "inline_data",
                    JSONObject()
                        .put("mime_type", mime)
                        .put("data", Base64.encodeToString(audioBytes, Base64.NO_WRAP)),
                ),
            )
            .put(JSONObject().put("text", "請處理這段錄音。"))

        val body = JSONObject()
            .put(
                "system_instruction",
                JSONObject().put("parts", JSONArray().put(JSONObject().put("text", system))),
            )
            .put("contents", JSONArray().put(JSONObject().put("parts", parts)))

        val conn = URL(endpoint).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 15000
            conn.readTimeout = 90000
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""

            if (code !in 200..299) {
                throw RuntimeException("Gemini 錯誤 $code:${extractError(text)}")
            }
            return parseText(text)
        } finally {
            conn.disconnect()
        }
    }

    private fun parseText(json: String): String {
        val root = JSONObject(json)
        val candidates = root.optJSONArray("candidates")
        if (candidates == null || candidates.length() == 0) {
            // Could be a safety block — surface promptFeedback if present.
            val feedback = root.optJSONObject("promptFeedback")?.optString("blockReason")
            throw RuntimeException(if (feedback.isNullOrEmpty()) "沒有產生結果" else "內容被擋下($feedback)")
        }
        val partsArr = candidates.getJSONObject(0)
            .optJSONObject("content")
            ?.optJSONArray("parts")
        val sb = StringBuilder()
        if (partsArr != null) {
            for (i in 0 until partsArr.length()) {
                sb.append(partsArr.getJSONObject(i).optString("text", ""))
            }
        }
        val out = sb.toString().trim()
        if (out.isEmpty()) throw RuntimeException("沒有產生文字")
        return out
    }

    private fun extractError(json: String): String =
        try {
            JSONObject(json).optJSONObject("error")?.optString("message") ?: json.take(200)
        } catch (_: Exception) {
            json.take(200)
        }
}
