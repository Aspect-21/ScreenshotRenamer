import Foundation
import Vision
import AppKit

struct AnalysisResult {
    let textLines: [String]
    let classificationLabels: [String]
}

final class ImageAnalyzer {

    func analyze(imageAt url: URL) async throws -> AnalysisResult {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AnalyzerError.couldNotLoadImage
        }

        async let textResult = recognizeText(in: cgImage)
        async let classResult = classifyImage(in: cgImage)

        let texts = try await textResult
        let labels = try await classResult

        return AnalysisResult(textLines: texts, classificationLabels: labels)
    }

    // MARK: - OCR

    private func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Sort by position (top to bottom, then left to right)
                let sorted = observations.sorted { a, b in
                    if abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.02 {
                        return a.boundingBox.origin.y > b.boundingBox.origin.y // top first (Vision coords are bottom-up)
                    }
                    return a.boundingBox.origin.x < b.boundingBox.origin.x
                }

                let lines = sorted.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Classification

    private func classifyImage(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Get top labels with >10% confidence
                let labels = observations
                    .filter { $0.confidence > 0.1 }
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(5)
                    .map { $0.identifier }

                continuation.resume(returning: Array(labels))
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum AnalyzerError: LocalizedError {
    case couldNotLoadImage

    var errorDescription: String? {
        switch self {
        case .couldNotLoadImage:
            return "Could not load the image file"
        }
    }
}
