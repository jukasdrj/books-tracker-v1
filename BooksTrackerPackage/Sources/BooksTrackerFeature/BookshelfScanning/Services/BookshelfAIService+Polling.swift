import Foundation
import UIKit

/// Extension for HTTP polling fallback
extension BookshelfAIService {

    /// Process bookshelf image using HTTP polling (fallback when WebSocket fails)
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - jobId: Pre-generated job identifier
    ///   - provider: AI provider (Gemini or Cloudflare)
    ///   - progressHandler: Closure for progress updates (called every 2s)
    /// - Returns: Tuple of detected books and suggestions
    /// - Throws: BookshelfAIError for failures
    internal func processViaPolling(
        image: UIImage,
        jobId: String,
        provider: AIProvider,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {
        print("📊 Using HTTP polling fallback for job \(jobId)")

        // STEP 1: Compress image
        let config = provider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let compressedData = processedImage.jpegData(compressionQuality: 0.8) else {
            throw .imageCompressionFailed
        }

        // STEP 2: Upload image
        let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"
        let uploadURL = URL(string: "\(baseURL)/bookshelf-scan/upload")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(provider.rawValue, forHTTPHeaderField: "X-Provider")
        uploadRequest.setValue(jobId, forHTTPHeaderField: "X-Job-ID")
        uploadRequest.httpBody = compressedData

        do {
            let (_, response) = try await URLSession.shared.data(for: uploadRequest)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw BookshelfAIError.serverError(500, "Upload failed")
            }
            print("✅ Image uploaded with jobId: \(jobId) (polling mode)")
        } catch let bookshelfError as BookshelfAIError {
            throw bookshelfError
        } catch {
            throw .networkError(error)
        }

        // STEP 3: Poll for status every 2 seconds
        let maxPolls = 40  // 40 polls * 2s = 80s timeout
        var pollCount = 0

        while pollCount < maxPolls {
            pollCount += 1

            do {
                let status = try await pollJobStatus(jobId: jobId)

                // Calculate progress from stage
                let (progress, statusMessage) = mapStageToProgress(stage: status.stage, elapsed: status.elapsedTime)

                await MainActor.run {
                    progressHandler(progress, statusMessage)
                }

                print("📊 Poll #\(pollCount): \(Int(progress * 100))% - \(statusMessage)")

                // Check if complete
                if let result = status.result {
                    print("✅ Polling complete after \(pollCount) polls")

                    let detectedBooks = result.books.compactMap { aiBook in
                        self.convertToDetectedBook(aiBook)
                    }
                    let suggestions = SuggestionGenerator.generateSuggestions(from: result)

                    return (detectedBooks, suggestions)
                }

                // Check if errored
                if let error = status.error {
                    throw BookshelfAIError.serverError(500, "Job failed: \(error)")
                }

                // Wait 2 seconds before next poll
                try await Task.sleep(for: .seconds(2))

            } catch let bookshelfError as BookshelfAIError {
                throw bookshelfError
            } catch {
                throw .networkError(error)
            }
        }

        // Timeout after maxPolls
        throw BookshelfAIError.serverError(408, "Polling timeout after \(pollCount) polls")
    }

    /// Map stage string to progress percentage and display message
    private func mapStageToProgress(stage: String, elapsed: Int) -> (Double, String) {
        switch stage.lowercased() {
        case "uploading":
            return (0.1, "Uploading image...")
        case "analyzing":
            return (0.3, "Analyzing image quality...")
        case "processing":
            return (0.5, "Processing with AI...")
        case "extracting":
            return (0.7, "Extracting book details...")
        case "complete", "completed":
            return (1.0, "Complete!")
        default:
            // Estimate based on elapsed time (typical: 25-40s)
            let estimatedProgress = min(0.9, Double(elapsed) / 40.0)
            return (estimatedProgress, "Processing... (\(elapsed)s)")
        }
    }
}

