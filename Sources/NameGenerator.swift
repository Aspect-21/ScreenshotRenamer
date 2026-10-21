import Foundation

final class NameGenerator {

    /// Generate a clean, descriptive filename from an analysis result.
    func generateName(from analysis: AnalysisResult, originalURL: URL, date: Date) -> String {
        let ext = originalURL.pathExtension.lowercased()
        let datePrefix = Self.formatDate(date)

        // Strategy 1: Use OCR text if available
        if let textName = extractNameFromText(analysis.textLines) {
            let sanitized = sanitize(textName)
            if !sanitized.isEmpty {
                return "\(datePrefix)_\(sanitized).\(ext)"
            }
        }

        // Strategy 2: Use classification labels
        if !analysis.classificationLabels.isEmpty {
            let labelName = analysis.classificationLabels
                .prefix(3)
                .joined(separator: "-")
            let sanitized = sanitize(labelName)
            if !sanitized.isEmpty {
                return "\(datePrefix)_\(sanitized).\(ext)"
            }
        }

        // Fallback: generic name
        return "\(datePrefix)_screenshot.\(ext)"
    }

    // MARK: - Text Extraction

    private func extractNameFromText(_ lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }

        // Filter out very short or very long lines
        let candidates = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.count <= 120
        }

        guard !candidates.isEmpty else { return nil }

        // Heuristic: prefer lines that look like titles
        // - Lines near the top (first 5 lines)
        // - Lines with moderate length (5-60 chars are ideal title length)
        // - Lines that start with a capital letter
        // - Lines without too many special characters

        let topCandidates = Array(candidates.prefix(8))

        // Score each candidate
        let scored = topCandidates.enumerated().map { (index, line) -> (String, Double) in
            var score = 0.0
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Prefer moderate length
            if trimmed.count >= 5 && trimmed.count <= 50 {
                score += 3.0
            } else if trimmed.count >= 3 && trimmed.count <= 80 {
                score += 1.5
            }

            // Prefer lines near the top
            score += max(0, Double(5 - index))

            // Prefer lines starting with uppercase
            if let first = trimmed.first, first.isUppercase {
                score += 2.0
            }

            // Penalize lines with lots of special characters
            let specialRatio = Double(trimmed.filter { !$0.isLetter && !$0.isNumber && $0 != " " }.count) / Double(trimmed.count)
            if specialRatio > 0.3 {
                score -= 3.0
            }

            // Penalize lines that are just numbers or dates
            let digitRatio = Double(trimmed.filter { $0.isNumber }.count) / Double(trimmed.count)
            if digitRatio > 0.6 {
                score -= 2.0
            }

            // Prefer lines with word-like content
            let words = trimmed.split(separator: " ")
            if words.count >= 2 && words.count <= 10 {
                score += 2.0
            }

            return (trimmed, score)
        }

        let best = scored.max(by: { $0.1 < $1.1 })
        return best?.0
    }

    // MARK: - Sanitization

    private func sanitize(_ input: String) -> String {
        var name = input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

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

        // Truncate to 60 characters
        if name.count > 60 {
            name = String(name.prefix(60))
            // Don't end on a hyphen
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return name
    }

    // MARK: - Date Formatting

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
