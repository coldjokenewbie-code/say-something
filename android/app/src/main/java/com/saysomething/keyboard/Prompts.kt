package com.saysomething.keyboard

/** Rewrite modes — kept in sync with the web app's MODES. */
data class Mode(val id: String, val label: String, val instruction: String)

object Prompts {
    val MODES: List<Mode> = listOf(
        Mode(
            "polish", "潤飾",
            "把這段口語逐字稿整理成通順自然的文字:去掉贅字、口頭禪、重複和自我修正,補上標點與分段,但保留說話者的原意、語氣和所有重點。",
        ),
        Mode(
            "raw", "原樣",
            "把這段口語逐字稿如實聽寫出來,只補上基本標點與分段,不要改寫、不要刪減內容。",
        ),
        Mode(
            "formal", "正式",
            "把這段口語逐字稿改寫成正式、專業的書面文字。去掉贅字與口語化用詞,結構清晰,保留所有重點。",
        ),
        Mode(
            "message", "訊息",
            "把這段口語逐字稿改寫成適合傳給朋友或同事的簡短通訊軟體訊息:輕鬆自然、口語但通順。",
        ),
        Mode(
            "email", "Email",
            "把這段口語逐字稿改寫成一封電子郵件正文,語氣禮貌專業,必要時分段。",
        ),
        Mode(
            "notes", "筆記",
            "把這段口語逐字稿整理成條列式重點筆記,合併重複內容,保留所有具體資訊。",
        ),
        Mode(
            "translate", "翻譯",
            "先把這段口語逐字稿整理通順,然後翻譯成自然流暢的英文(若原文已是英文則翻成繁體中文)。只輸出翻譯結果。",
        ),
    )

    fun modeById(id: String): Mode = MODES.firstOrNull { it.id == id } ?: MODES[0]

    /** System instruction sent to Gemini together with the recorded audio. */
    fun buildSystem(mode: Mode, outputLang: String): String {
        val lang = if (outputLang == "same") {
            "輸出語言與原文相同(翻譯模式除外);中英夾雜的內容就保留中英夾雜。"
        } else {
            "除非指示要求翻譯,輸出一律使用$outputLang。"
        }
        return listOf(
            "你是語音輸入的後製助手。使用者錄了一段話(內容以中文為主,可能夾雜英文)。",
            "請先聽寫,再依以下要求整理:",
            mode.instruction,
            "聽寫時英文詞要寫成正確的英文(產品名、品牌、技術術語、人名等),中文照寫中文,忠實保留原本的語言,不要把原本是英文的詞翻成中文。",
            lang,
            "只輸出整理後的最終文字,不要任何前言、說明、引號或逐字稿。",
        ).joinToString("\n")
    }
}
