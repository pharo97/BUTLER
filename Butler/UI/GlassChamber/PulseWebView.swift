import SwiftUI
import WebKit

// MARK: - PulseWebView

struct PulseWebView: NSViewRepresentable {

    let state:      String
    let amplitude:  Double
    var birthPhase: String? = nil
    var isSpeaking: Bool    = false

    // MARK: Coordinator

    final class Coordinator {
        weak var webView: WKWebView?
        var lastState:      String  = ""
        var lastAmplitude:  Double  = -1.0
        var lastBirthPhase: String? = "___unset___"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        // WKWebView does not expose drawsBackground in Swift on macOS 14+;
        // use KVC to reach the private _setDrawsBackground: ObjC property so
        // the glass panel shows through.
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "pulse", withExtension: "html") {
            let dir = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: dir)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        if let phase = birthPhase {
            // Birth mode path — only send when phase or isSpeaking changes
            guard phase != coordinator.lastBirthPhase else { return }
            coordinator.lastBirthPhase = phase
            let speakFlag = isSpeaking ? "true" : "false"
            let js = "window.butler?.setBirthMode(\(jsString(phase)), \(speakFlag));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            // Normal path — debounce on state + amplitude
            let ampChanged   = abs(amplitude - coordinator.lastAmplitude) > 0.005
            let stateChanged = state != coordinator.lastState

            guard stateChanged || ampChanged else { return }

            coordinator.lastState     = state
            coordinator.lastAmplitude = amplitude
            coordinator.lastBirthPhase = nil   // reset birth tracking

            let js = "window.butler?.setState(\(jsString(state)), \(amplitude));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: Helpers

    private func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
