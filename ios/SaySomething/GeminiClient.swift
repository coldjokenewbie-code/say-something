import Foundation

enum GeminiError: LocalizedError {
    case noApiKey
    case network(String)
    case apiError(Int, String)
    case emptyResult
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "尚未設定 Gemini API key,請到設定頁輸入。"
        case .network(let msg):
            return "網路連線失敗:\(msg)"
        case .apiError(let code, let msg):
            return "Gemini 錯誤 \(code):\(msg)"
        case .emptyResult:
            return "沒有產生文字,請再試一次。"
        case .blocked(let reason):
            return "內容被擋下(\(reason))"
        }
    }
}

/// REST client for the Gemini `generateContent` endpoint — mirrors
/// android/app/src/main/java/com/saysomething/keyboard/Gemini.kt (same
/// v1beta endpoint, same inline_data + system_instruction JSON shape).
enum GeminiClient {
    /// Cloud mode (PRD 階段 7): sends the raw recording, Gemini both
    /// transcribes and polishes it in one call. Kept as-is — this is the
    /// "送音檔,品質最好" path the settings toggle can still pick.
    static func transcribeAndPolish(
        apiKey: String,
        model: String,
        system: String,
        audioData: Data,
        mime: String
    ) async throws -> String {
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": mime,
                                "data": audioData.base64EncodedString(),
                            ]
                        ],
                        ["text": "請處理這段錄音。"],
                    ]
                ]
            ],
        ]
        return try await send(apiKey: apiKey, model: model, body: body)
    }

    /// Local mode (PRD 階段 7): whisper.cpp already turned the recording
    /// into plain text on-device (see WhisperTranscriber); only that text —
    /// never audio — is sent here. Uses the exact same `system` instruction
    /// built by Prompts.buildSystem as the audio path (C7: single prompt
    /// source, same seven-mode semantics), just with a text part instead of
    /// inline_data.
    static func polishText(
        apiKey: String,
        model: String,
        system: String,
        text: String
    ) async throws -> String {
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": text],
                    ]
                ]
            ],
        ]
        return try await send(apiKey: apiKey, model: model, body: body)
    }

    private static func send(apiKey: String, model: String, body: [String: Any]) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noApiKey }

        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        ) else {
            throw GeminiError.network("無效的網址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.network(error.localizedDescription)
        }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard (200...299).contains(statusCode) else {
            throw GeminiError.apiError(statusCode, extractError(from: data))
        }

        return try parseText(from: data)
    }

    private static func parseText(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.emptyResult
        }

        guard let candidates = root["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            if let feedback = root["promptFeedback"] as? [String: Any],
               let blockReason = feedback["blockReason"] as? String, !blockReason.isEmpty {
                throw GeminiError.blocked(blockReason)
            }
            throw GeminiError.emptyResult
        }

        let content = candidates[0]["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyResult }
        return trimmed
    }

    private static func extractError(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.prefix(200))
    }
}
