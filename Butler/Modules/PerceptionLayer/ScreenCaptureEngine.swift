import Foundation
import ScreenCaptureKit
import Vision
import CoreMedia
import CoreImage

// MARK: - ScreenCaptureEngine

/// Captures the frontmost application window using ScreenCaptureKit, then
/// extracts visible text using the Vision framework's OCR engine.
///
/// This gives BUTLER genuine "eyes" — instead of only knowing the app name,
/// it can read what's actually on screen: the exact error in Xcode, the
/// spreadsheet data in Numbers, the article in Safari.
///
/// Permission required: Screen Recording (System Settings → Privacy & Security
/// → Screen Recording). Degrades gracefully to empty string if denied.
///
/// Not @MainActor — all work is off main actor, returns a Sendable String.
final class ScreenCaptureEngine: Sendable {

    // MARK: - Permission

    var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccessIfNeeded() {
        if !isAuthorized { CGRequestScreenCaptureAccess() }
    }

    // MARK: - Capture

    func captureVisibleText(frontmostPID: pid_t) async -> String {
        guard isAuthorized else { return "" }
        do {
            let content = try await SCShareableContent.current
            if let window = content.windows.first(where: {
                $0.owningApplication?.processID == frontmostPID
                && $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100
            }) {
                return try await ocrWindow(window)
            }
            if let display = content.displays.first {
                return try await ocrDisplay(display)
            }
        } catch {
            print("[ScreenCaptureEngine] \(error.localizedDescription)")
        }
        return ""
    }

    // MARK: - Capture helpers

    private func ocrWindow(_ window: SCWindow) async throws -> String {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width  = max(1, Int(window.frame.width))
        config.height = max(1, Int(window.frame.height))
        config.captureResolution = .nominal
        let buffer = try await SCScreenshotManager.captureSampleBuffer(
            contentFilter: filter, configuration: config)
        return await extractText(from: buffer)
    }

    private func ocrDisplay(_ display: SCDisplay) async throws -> String {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width  = Int(display.frame.width)
        config.height = Int(display.frame.height)
        config.captureResolution = .nominal
        let buffer = try await SCScreenshotManager.captureSampleBuffer(
            contentFilter: filter, configuration: config)
        return await extractText(from: buffer)
    }

    // MARK: - Vision OCR

    private func extractText(from sampleBuffer: CMSampleBuffer) async -> String {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return "" }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return "" }

        // withUnsafeContinuation: VNImageRequestHandler.perform() is synchronous
        // and fires the request completion handler synchronously on the calling
        // thread. Using the checked variant is unnecessary here and risks
        // dispatch_assert_queue failures if the executor context has changed
        // (e.g. after awaiting SCScreenshotManager.captureSampleBuffer).
        return await withUnsafeContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: String(text.prefix(1_500)))
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }
}
