import Foundation
import AppKit

final class GeminiAnalyzer {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Model Fallback Chain (ordered by speed/cheapness)

    /// Models to try in order. When one is rate-limited, we cascade to the next.
    static let modelChain: [String] = [
        "gemini-3.1-flash-lite-preview",   // fastest, cheapest
        "gemini-2.5-flash-lite",           // very fast, cheap
        "gemini-2.5-flash",                // fast, more capable
        "gemini-3-flash-preview",          // newest flash
        "gemini-2.0-flash",                // older but reliable
        "gemini-2.0-flash-lite",           // older lite variant
    ]

    /// Track rate-limited models with a cooldown period.
    /// Key: model name, Value: timestamp when cooldown expires.
    private static var rateLimitedModels: [String: Date] = [:]
    private static let rateLimitCooldown: TimeInterval = 300 // 5 minutes

    /// Maximum retries for transient errors (500, 503) on a single model.
    private let maxTransientRetries = 2
    private let initialRetryDelay: TimeInterval = 2.0

    // MARK: - Public API

    struct AnalysisResult {
        let name: String
        let modelUsed: String
    }

    /// Analyze a screenshot and return a concise descriptive name, cascading through models on rate limits.
    func analyzeName(for imageURL: URL) async throws -> AnalysisResult {
        // Load and encode the image as base64
        guard let imageData = try? Data(contentsOf: imageURL) else {
            throw GeminiError.couldNotLoadImage
        }

        let base64Image = imageData.base64EncodedString()
        let mimeType = mimeType(for: imageURL.pathExtension)

        // Try each model in the chain
        var lastError: Error = GeminiError.allModelsExhausted

        let availableModels = Self.modelChain.filter { model in
            if let cooldownExpiry = Self.rateLimitedModels[model] {
                if Date() < cooldownExpiry {
                    Logger.log("Gemini: skipping \(model) (rate-limited, cooldown until \(cooldownExpiry))")
                    return false
                } else {
                    // Cooldown expired, allow retry
                    Self.rateLimitedModels.removeValue(forKey: model)
                    Logger.log("Gemini: cooldown expired for \(model), will retry")
                }
            }
            return true
        }

        if availableModels.isEmpty {
            Logger.log("Gemini: ALL models are in cooldown! Clearing oldest and retrying primary...")
            // Clear all cooldowns as a last resort
            Self.rateLimitedModels.removeAll()
        }

        let modelsToTry = availableModels.isEmpty ? Self.modelChain : availableModels

        for model in modelsToTry {
            Logger.log("Gemini: trying model \(model)...")

            do {
                let name = try await callModel(
                    model: model,
                    base64Image: base64Image,
                    mimeType: mimeType
                )
                Logger.log("Gemini: ✅ success with \(model) → \"\(name)\"")
                return AnalysisResult(name: name, modelUsed: model)
            } catch let error as GeminiError {
                switch error {
                case .rateLimited(let model):
                    Logger.log("Gemini: ⚠️ \(model) rate-limited, cascading to next model...")
                    Self.rateLimitedModels[model] = Date().addingTimeInterval(Self.rateLimitCooldown)
                    lastError = error
                    continue // Try next model

                case .transientError:
                    Logger.log("Gemini: ⚠️ transient error on \(model), cascading to next model...")
                    lastError = error
                    continue // Try next model

                default:
                    // Non-recoverable error (bad response, parse failure, etc.)
                    Logger.log("Gemini: ❌ non-recoverable error on \(model): \(error.localizedDescription)")
                    throw error
                }
            } catch {
                Logger.log("Gemini: ❌ unexpected error on \(model): \(error.localizedDescription)")
                lastError = error
                continue // Network errors — try next model
            }
        }

        // All models exhausted
        Logger.log("Gemini: ❌ all models exhausted")
        throw lastError
    }

    // MARK: - Single Model Call (with transient retry)

    private func callModel(model: String, base64Image: String, mimeType: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = """
        Look at this screenshot and generate a short, descriptive filename for it (without file extension).
        
        Rules:
        - Maximum 6 words, prefer 3-4 words
        - Use lowercase words separated by hyphens
        - Describe WHAT the screenshot shows (e.g. "slack-conversation-about-deployment", "vscode-python-syntax-error", "twitter-feed-dark-mode", "chrome-google-search-results", "settings-wifi-connected")
        - Focus on the most important/distinctive content visible
        - If there's text visible, incorporate the key topic
        - Do NOT include dates, "screenshot", or file extensions
        - Respond with ONLY the filename, nothing else
        """

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 256
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Retry loop for transient errors only
        for attempt in 0...maxTransientRetries {
            if attempt > 0 {
                let delay = initialRetryDelay * pow(2.0, Double(attempt - 1))
                Logger.log("Gemini: transient retry \(attempt)/\(maxTransientRetries) on \(model) after \(delay)s...")
                try await Task.sleep(for: .seconds(delay))
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }

            // Rate limited — don't retry, cascade to next model
            if httpResponse.statusCode == 429 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Rate limited"
                Logger.log("Gemini: \(model) returned 429: \(errorBody.prefix(200))")
                throw GeminiError.rateLimited(model: model)
            }

            // Transient server errors — retry same model
            if httpResponse.statusCode >= 500 && httpResponse.statusCode < 600 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Server error"
                Logger.log("Gemini: \(model) returned \(httpResponse.statusCode): \(errorBody.prefix(200))")
                if attempt < maxTransientRetries {
                    continue // retry
                }
                throw GeminiError.transientError(statusCode: httpResponse.statusCode, model: model)
            }

            // Other non-200 errors — don't retry
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.log("Gemini: \(model) API error (\(httpResponse.statusCode)): \(errorBody.prefix(300))")
                throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            // Log raw response for debugging
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            Logger.log("Gemini: \(model) raw response (status 200): \(rawBody.prefix(500))")

            // Parse the response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                Logger.log("Gemini: \(model) could not parse response structure")
                throw GeminiError.invalidResponse
            }

            // Gemini thinking models may return a "thought" part + a text part.
            // We want the last part that has a "text" key and is NOT a thought.
            let textPart = parts.last(where: { part in
                part["text"] != nil && part["thought"] == nil && part["thoughtSignature"] == nil
            }) ?? parts.last(where: { $0["text"] != nil })

            guard let text = textPart?["text"] as? String, !text.isEmpty else {
                Logger.log("Gemini: \(model) no text found in parts: \(parts)")
                throw GeminiError.invalidResponse
            }

            let name = sanitize(text.trimmingCharacters(in: .whitespacesAndNewlines))
            return name
        }

        throw GeminiError.transientError(statusCode: 500, model: model)
    }

    // MARK: - Helpers

    private func sanitize(_ input: String) -> String {
        var name = input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove any quotes or backticks the model might add
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "`", with: "")

        // Replace spaces and underscores with hyphens
        name = name.replacingOccurrences(of: " ", with: "-")
        name = name.replacingOccurrences(of: "_", with: "-")

        // Remove all non-alphanumeric characters except hyphens
        name = String(name.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
        })

        // Collapse multiple hyphens
        while name.contains("--") {
            name = name.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing hyphens
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate
        if name.count > 80 {
            name = String(name.prefix(80))
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return name.isEmpty ? "screenshot" : name
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        default: return "image/png"
        }
    }
}

enum GeminiError: LocalizedError {
    case couldNotLoadImage
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case rateLimited(model: String)
    case transientError(statusCode: Int, model: String)
    case allModelsExhausted

    var errorDescription: String? {
        switch self {
        case .couldNotLoadImage:
            return "Could not load the image file"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let code, let msg):
            return "Gemini API error (\(code)): \(msg)"
        case .rateLimited(let model):
            return "Rate limited on \(model)"
        case .transientError(let code, let model):
            return "Server error (\(code)) on \(model)"
        case .allModelsExhausted:
            return "All Gemini models are rate-limited or unavailable"
        }
    }
}
