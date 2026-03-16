import SwiftUI
import AVFoundation

// MARK: - SettingsView

/// Unified settings sheet covering Voice, Hotkey, AI Provider, Personality, and Memory Palace.
///
/// Opened via the gear icon or right-click -> Settings on the Glass Chamber.
struct SettingsView: View {

    var voiceProfile:           VoiceProfileManager
    var aiLayer:                AIIntegrationLayer
    var hotkeyManager:          HotkeyManager
    var tierManager:            PermissionTierManager
    var audioDeviceManager:     AudioDeviceManager
    var idleProcessor:          IdleBackgroundProcessor

    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyDraft: String = ""

    // Ollama-specific state
    @State private var ollamaInstalledModels: [String] = []
    @State private var ollamaConnected:       Bool?    = nil
    @State private var ollamaChecking:        Bool     = false

    // Memory Palace — confirmation dialog state
    @State private var showForgetConfirmation: Bool = false

    // Voice change sheet state
    @State private var showVoiceSheet:          Bool    = false
    @State private var sheetVoiceIdentifier:    String? = nil

    // MARK: - Personality / name (AppStorage — live across the app)

    @AppStorage("butler.user.name")           private var userName: String = ""
    @AppStorage("butler.ai.customName")        private var aiCustomName: String = "BUTLER"
    @AppStorage("butler.ai.personalityPrompt") private var personalityPrompt: String = ""

    // MARK: - Memory Palace toggles (AppStorage)

    @AppStorage("butler.memory.enabled")          private var memoryEnabled: Bool = false
    @AppStorage("butler.memory.includeInPrompts") private var memoryInPrompts: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .opacity(0.3)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    tiersSection
                    audioDevicesSection
                    voiceSection
                    rateSection
                    hotkeySection
                    apiSection
                    personalitySection
                    memorySection
                }
                .padding(24)
            }

            Divider()
                .opacity(0.3)

            // Footer
            footer
        }
        // Increased height to accommodate two new sections
        .frame(width: 400, height: 820)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("BUTLER")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(3)
                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Permission Tiers section

    private var tiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PERMISSIONS")

            VStack(spacing: 8) {
                tierCard(
                    number: "0",
                    name: "Passive",
                    description: "Activity monitoring — knows which app is active and broadly what you're doing. No screen reading, no interruptions.",
                    symbol: "eye.slash",
                    isAlwaysOn: true,
                    isLocked: false,
                    isEnabled: .constant(true)
                )
                tierCard(
                    number: "1",
                    name: "App Awareness",
                    description: "Screen context + clipboard reading. Butler can see what you're working on and react when you copy something.",
                    symbol: "doc.text.magnifyingglass",
                    isAlwaysOn: false,
                    isLocked: false,
                    isEnabled: Binding(
                        get: { tierManager.tier1Enabled },
                        set: { tierManager.tier1Enabled = $0 }
                    )
                )
                tierCard(
                    number: "2",
                    name: "Interventions",
                    description: "Proactive voice suggestions without you pressing the mic. Butler speaks up when it thinks it can help.",
                    symbol: "waveform.badge.plus",
                    isAlwaysOn: false,
                    isLocked: false,
                    isEnabled: Binding(
                        get: { tierManager.tier2Enabled },
                        set: { tierManager.tier2Enabled = $0 }
                    )
                )
                tierCard(
                    number: "3",
                    name: "Automation",
                    description: "File operations, AppleScript, Shortcuts integration. Butler can take actions on your behalf.",
                    symbol: "gearshape.2",
                    isAlwaysOn: false,
                    isLocked: true,
                    isEnabled: Binding(
                        get: { tierManager.tier3Enabled },
                        set: { tierManager.tier3Enabled = $0 }
                    )
                )
                tier4Card
            }
        }
    }

    // MARK: - Tier 4 — Librarian card

    private var tier4Card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (mirrors tierCard layout)
            HStack(alignment: .top, spacing: 12) {
                // Tier badge
                ZStack {
                    Circle()
                        .fill(tierManager.tier4Enabled
                              ? Color.accentColor.opacity(0.18)
                              : Color.white.opacity(0.05))
                    Text("4")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(tierManager.tier4Enabled ? Color.accentColor : .secondary)
                }
                .frame(width: 26, height: 26)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 10))
                            .foregroundStyle(tierManager.tier4Enabled ? Color.accentColor : .secondary)
                        Text("Librarian")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tierManager.tier4Enabled ? .primary : .secondary)
                        Text("HIGH PRIVACY")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.12)))
                    }
                    Text("Background scanning during idle: infers your work patterns from file names and types only. Zero file content is read. Local only.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { tierManager.tier4Enabled },
                    set: { tierManager.tier4Enabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            // Sub-permissions (only visible when Tier 4 is on)
            if tierManager.tier4Enabled {
                VStack(alignment: .leading, spacing: 2) {
                    Divider().opacity(0.3).padding(.vertical, 8)

                    subPermissionRow(
                        symbol: "arrow.down.to.line",
                        label:  "Downloads folder",
                        detail: "File names + types only",
                        isOn: Binding(
                            get: { tierManager.tier4Downloads },
                            set: { tierManager.tier4Downloads = $0 }
                        )
                    )
                    subPermissionRow(
                        symbol: "rectangle.and.text.magnifyingglass",
                        label:  "Desktop",
                        detail: "Project file detection",
                        isOn: Binding(
                            get: { tierManager.tier4Desktop },
                            set: { tierManager.tier4Desktop = $0 }
                        )
                    )
                    subPermissionRow(
                        symbol: "doc.on.clipboard",
                        label:  "Clipboard patterns",
                        detail: "Code vs text detection (not stored)",
                        isOn: Binding(
                            get: { tierManager.tier4Clipboard },
                            set: { tierManager.tier4Clipboard = $0 }
                        )
                    )

                    // Live status from idleProcessor
                    if idleProcessor.isRunning {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text(idleProcessor.statusLine)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let last = idleProcessor.lastScanAt {
                                Text("· last scan \(last.formatted(.relative(presentation: .named)))")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.leading, 38)  // align with text, past badge
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tierManager.tier4Enabled
                      ? Color.accentColor.opacity(0.05)
                      : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            tierManager.tier4Enabled
                            ? Color.accentColor.opacity(0.18)
                            : Color.white.opacity(0.07),
                            lineWidth: 0.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: tierManager.tier4Enabled)
    }

    private func subPermissionRow(
        symbol: String,
        label:  String,
        detail: String,
        isOn:   Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func tierCard(
        number: String,
        name: String,
        description: String,
        symbol: String,
        isAlwaysOn: Bool,
        isLocked: Bool,
        isEnabled: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Tier badge
            ZStack {
                Circle()
                    .fill(isEnabled.wrappedValue || isAlwaysOn
                          ? Color.accentColor.opacity(0.18)
                          : Color.white.opacity(0.05))
                Text(number)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isEnabled.wrappedValue || isAlwaysOn
                                     ? Color.accentColor
                                     : .secondary)
            }
            .frame(width: 26, height: 26)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(isEnabled.wrappedValue || isAlwaysOn
                                         ? Color.accentColor : .secondary)
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEnabled.wrappedValue || isAlwaysOn ? .primary : .secondary)
                    if isAlwaysOn {
                        Text("ALWAYS ON")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.green.opacity(0.12)))
                    }
                    if isLocked {
                        Text("COMING SOON")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.12)))
                    }
                }
                Text(description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Toggle
            if !isAlwaysOn {
                Toggle("", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isLocked)
                    .labelsHidden()
                    .opacity(isLocked ? 0.35 : 1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isEnabled.wrappedValue || isAlwaysOn
                      ? Color.accentColor.opacity(0.05)
                      : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isEnabled.wrappedValue || isAlwaysOn
                            ? Color.accentColor.opacity(0.18)
                            : Color.white.opacity(0.07),
                            lineWidth: 0.5
                        )
                )
        )
    }

    // MARK: - Audio devices section

    private var audioDevicesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("AUDIO DEVICES")
                Spacer()
                Button { audioDeviceManager.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
            }

            // Microphone input
            VStack(alignment: .leading, spacing: 6) {
                Text("Microphone")
                    .font(.system(size: 10, weight: .medium))

                if audioDeviceManager.inputDevices.isEmpty {
                    Text("No input devices found.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(audioDeviceManager.inputDevices) { device in
                            deviceRow(
                                device,
                                isSelected: device.uid == audioDeviceManager.selectedInputUID
                            ) {
                                audioDeviceManager.selectInput(device)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
                }
            }

            // Speaker output
            VStack(alignment: .leading, spacing: 6) {
                Text("Speaker Output")
                    .font(.system(size: 10, weight: .medium))

                if audioDeviceManager.outputDevices.isEmpty {
                    Text("No output devices found.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(audioDeviceManager.outputDevices) { device in
                            deviceRow(
                                device,
                                isSelected: device.uid == audioDeviceManager.selectedOutputUID
                            ) {
                                audioDeviceManager.selectOutput(device)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
                }

                Text("BUTLER routes speech to this device. Select a different output to override the system default.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func deviceRow(
        _ device:   AudioDeviceManager.AudioDevice,
        isSelected: Bool,
        disabled:   Bool = false,
        onTap:      @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(device.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(disabled ? .secondary : .primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { onTap() } }
    }

    // MARK: - Voice section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("VOICE")

            if voiceProfile.voices.isEmpty {
                Text("No English voices found. Download voices in System Settings -> Accessibility -> Spoken Content -> System Voice.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(voiceProfile.voicesByGender, id: \.gender) { group in
                        // Gender header
                        Text(group.gender.rawValue.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .tracking(1.5)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        // Voice rows
                        ForEach(group.voices) { option in
                            voiceRow(option)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.5))
                )
            }
        }
    }

    private func voiceRow(_ option: VoiceOption) -> some View {
        let isSelected = option.identifier == voiceProfile.selectedVoiceIdentifier

        return HStack(spacing: 10) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            // Name + region
            VStack(alignment: .leading, spacing: 1) {
                Text(option.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                if !option.regionLabel.isEmpty {
                    Text(option.regionLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Quality badge
            Text(option.qualityLabel)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(qualityColor(option.quality))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(qualityColor(option.quality).opacity(0.12))
                )

            // Preview button
            Button {
                voiceProfile.previewVoice(option)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            voiceProfile.stopPreview()
            voiceProfile.selectedVoiceIdentifier = option.identifier
        }
    }

    private func qualityColor(_ q: AVSpeechSynthesisVoiceQuality) -> Color {
        switch q {
        case .premium:  return Color(red: 0.35, green: 1.00, blue: 0.72)  // aqua
        case .enhanced: return Color(red: 0.75, green: 0.45, blue: 1.00)  // purple
        default:        return .secondary
        }
    }

    // MARK: - Voice change sheet (opened from Personality section)

    /// Friendly display name for the currently selected voice.
    private var currentVoiceDisplayName: String {
        // Prefer the name stored at the canonical key (set by VoiceSelectionView)
        if let name = UserDefaults.standard.string(forKey: "butler.tts.voiceName"), !name.isEmpty {
            return name
        }
        // Fall back to VoiceProfileManager's selected voice
        if let v = voiceProfile.voices.first(where: {
            $0.identifier == voiceProfile.selectedVoiceIdentifier
        }) {
            return v.name
        }
        return "System Default"
    }

    /// A sheet containing `VoiceSelectionView` for mid-session voice changes.
    ///
    /// On commit the canonical UserDefaults key and `VoiceProfileManager` are both updated
    /// so future TTS picks up the choice immediately (no restart required).
    private var voiceChangeSheet: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                Text("CHANGE VOICE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { showVoiceSheet = false }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            // Reuse VoiceSelectionView — it already handles preview + commit
            VoiceSelectionView(
                selectedVoiceIdentifier: $sheetVoiceIdentifier,
                onVoiceSelected: {
                    // Sync the committed identifier back to VoiceProfileManager
                    if let id = sheetVoiceIdentifier {
                        voiceProfile.selectedVoiceIdentifier = id
                    }
                    showVoiceSheet = false
                }
            )
            .padding(20)

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            sheetVoiceIdentifier = voiceProfile.selectedVoiceIdentifier
        }
    }

    // MARK: - Speaking rate

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SPEAKING RATE")

            HStack(spacing: 12) {
                Image(systemName: "tortoise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(voiceProfile.speakingRate) },
                        set: { voiceProfile.speakingRate = Float($0) }
                    ),
                    in: 0.3 ... 0.7
                )

                Image(systemName: "hare")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Drag to adjust how fast BUTLER speaks. This will evolve automatically as BUTLER learns your preference.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Hotkey section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("GLOBAL HOTKEY")

            HStack(spacing: 12) {
                // Key badge
                HStack(spacing: 4) {
                    keyBadge("⌥")
                    Text("+")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    keyBadge("Space")
                }

                Spacer()

                // Status
                if hotkeyManager.isMonitoring {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                } else if hotkeyManager.needsInputMonitoringPermission {
                    Button("Enable in System Settings") {
                        hotkeyManager.requestPermission()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Label("Not active", systemImage: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if hotkeyManager.needsInputMonitoringPermission {
                Text("Grant Input Monitoring in System Settings -> Privacy & Security -> Input Monitoring, then re-launch BUTLER.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func keyBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
            )
    }

    // MARK: - API Provider section

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("AI PROVIDER")

            // Provider picker — uses short names so three segments fit at 400pt
            Picker("Provider", selection: Binding(
                get: { aiLayer.selectedProvider },
                set: { aiLayer.selectedProvider = $0; apiKeyDraft = "" }
            )) {
                ForEach(AIProviderType.allCases, id: \.self) { provider in
                    Text(provider.shortName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            // Branch: Ollama (local) vs cloud providers
            if aiLayer.selectedProvider == .ollama {
                ollamaSection
            } else {
                cloudKeySection
            }
        }
        .animation(.easeInOut(duration: 0.15), value: aiLayer.selectedProvider)
        // Refresh Ollama status whenever the provider tab changes
        .task(id: aiLayer.selectedProvider) {
            if aiLayer.selectedProvider == .ollama {
                await checkOllama()
            }
        }
    }

    // MARK: - Ollama section (no key required)

    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Connection status row
            HStack(spacing: 8) {
                // Status dot
                Group {
                    if ollamaChecking {
                        ProgressView()
                            .controlSize(.mini)
                    } else if ollamaConnected == true {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    } else if ollamaConnected == false {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }

                Text(ollamaStatusLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(ollamaConnected == true ? .primary : .secondary)

                Spacer()

                Button {
                    Task { await checkOllama() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Re-check Ollama connection")
            }

            // Model picker — populated from /api/tags when connected
            let models = ollamaInstalledModels.isEmpty
                ? OllamaProvider().availableModels
                : ollamaInstalledModels

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.system(size: 10, weight: .medium))

                Picker("Model", selection: Binding(
                    get: { aiLayer.selectedModel },
                    set: { aiLayer.selectedModel = $0 }
                )) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)

                if !ollamaInstalledModels.isEmpty {
                    Text("Showing models installed on your machine.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Showing popular models — connect to Ollama to see installed models.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Help text
            if ollamaConnected == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ollama not detected. Start it with:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("brew install ollama && ollama serve")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                    Text("Then pull a model: ollama pull llama3.2")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Runs entirely on-device — no API key, no internet, no cost.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var ollamaStatusLabel: String {
        if ollamaChecking     { return "Checking..." }
        if ollamaConnected == true  { return "Ollama running · localhost:11434" }
        if ollamaConnected == false { return "Ollama not found · not running?" }
        return "Unknown"
    }

    @MainActor
    private func checkOllama() async {
        ollamaChecking = true
        let models = await OllamaProvider.fetchInstalledModels()
        ollamaInstalledModels = models
        ollamaConnected       = !models.isEmpty
        ollamaChecking        = false

        // If we got models back and the current model isn't in the list, reset to first
        if !models.isEmpty && !models.contains(aiLayer.selectedModel) {
            aiLayer.selectedModel = models[0]
        }
    }

    // MARK: - Cloud provider section (key required)

    private var cloudKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // API key input
            HStack(spacing: 8) {
                SecureField(
                    aiLayer.selectedProvider.provider.apiKeyPlaceholder,
                    text: $apiKeyDraft
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

                Button("Save") {
                    aiLayer.saveApiKey(apiKeyDraft)
                    apiKeyDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKeyDraft.count < 20)
            }

            HStack {
                // Status indicator
                if aiLayer.apiKey.isEmpty {
                    Label("No key saved", systemImage: "exclamationmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else {
                    Label("Key saved in Keychain", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }

                Spacer()

                Link("Get a key ->", destination: aiLayer.selectedProvider.provider.apiKeyURL)
                    .font(.system(size: 9))

                if !aiLayer.apiKey.isEmpty {
                    Button("Clear") { aiLayer.clearApiKey() }
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.8))
                        .buttonStyle(.plain)
                }
            }

            Text("Keys are stored encrypted in the macOS Keychain. Nothing leaves your machine except API requests.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Personality section (Feature 1)

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("AI PERSONALITY")

            // ── Voice picker ─────────────────────────────────────────────────────
            // Shows the currently selected voice name with a button to open a sheet
            // containing VoiceSelectionView.  Changes here write to both the
            // canonical key (butler.tts.voiceIdentifier) and VoiceProfileManager's
            // key (butler.selectedVoiceIdentifier.v1) so every TTS path stays in sync.
            settingsRow(label: "Voice") {
                HStack(spacing: 8) {
                    // Current voice name
                    Text(currentVoiceDisplayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    // Change button → opens voice sheet
                    Button {
                        sheetVoiceIdentifier = voiceProfile.selectedVoiceIdentifier
                        showVoiceSheet = true
                    } label: {
                        Text("Change")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 200)
            }
            Text("The voice BUTLER uses when speaking to you.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            // Voice change sheet
            .sheet(isPresented: $showVoiceSheet) {
                voiceChangeSheet
            }

            // Your name field — used in Memory Palace file naming
            settingsRow(label: "Your Name") {
                TextField("Ahmed", text: $userName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .frame(maxWidth: 160)
            }
            Text("Used to name your Memory Palace files.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            // AI name field — displayed in Glass Chamber wordmark
            settingsRow(label: "AI Name") {
                TextField("Butler", text: $aiCustomName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .frame(maxWidth: 160)
                    // Enforce 24-char max
                    .onChange(of: aiCustomName) { _, new in
                        if new.count > 24 {
                            aiCustomName = String(new.prefix(24))
                        }
                    }
            }
            Text("Shown in the Glass Chamber and injected into every prompt.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            // Personality prompt — multi-line TextEditor
            VStack(alignment: .leading, spacing: 6) {
                Text("Personality")
                    .font(.system(size: 10, weight: .medium))

                ZStack(alignment: .topLeading) {
                    // Placeholder text when empty
                    if personalityPrompt.isEmpty {
                        Text("e.g. You are concise, dry-witted, and speak like a trusted advisor. You prefer brevity and use British English.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $personalityPrompt)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 80)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
            }

            Text("This is injected at the top of every system prompt as a PERSONALITY DIRECTIVE.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Memory Palace section (Feature 2)

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("MEMORY PALACE")

            // Toggles
            VStack(spacing: 1) {
                toggleRow(
                    label: "Write learning facts to memory files",
                    detail: "Butler logs interventions and context patterns locally.",
                    isOn: $memoryEnabled
                )

                Divider().opacity(0.3).padding(.horizontal, 12)

                toggleRow(
                    label: "Include memory in conversation context",
                    detail: "Recent facts are injected into every system prompt.",
                    isOn: $memoryInPrompts
                )
                .disabled(!memoryEnabled)
                .opacity(memoryEnabled ? 1 : 0.40)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            // Memory file list
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory files (local only):")
                    .font(.system(size: 10, weight: .medium))

                VStack(spacing: 0) {
                    ForEach(MemoryCategory.allCases, id: \.rawValue) { category in
                        memoryFileRow(category: category)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            }

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    MemoryWriter.shared.revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    showForgetConfirmation = true
                } label: {
                    Label("Forget Everything", systemImage: "trash")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .confirmationDialog(
                    "Forget Everything?",
                    isPresented: $showForgetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete All Memory Files", role: .destructive) {
                        MemoryWriter.shared.wipeAll()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This permanently deletes all Memory Palace files. Butler will start learning about you from scratch.")
                }
            }

            // Privacy note
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("Local plain text files only — no cloud sync, no external transmission.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A single memory file row with an "Open" button.
    private func memoryFileRow(category: MemoryCategory) -> some View {
        let writer   = MemoryWriter.shared
        let fileName = writer.filePath(for: category).lastPathComponent
        let exists   = FileManager.default.fileExists(atPath: writer.filePath(for: category).path)

        return HStack(spacing: 10) {
            Image(systemName: category.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(exists ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(exists ? .primary : .secondary)
                Text(category.displayName)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                writer.openFile(for: category)
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 9))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// A toggle row with a label and detail string, styled to match the tier cards.
    private func toggleRow(
        label:  String,
        detail: String,
        isOn:   Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// A horizontal key-value settings row.
    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("BUTLER evolves with you — voice, pace, and personality adapt over time.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Helper

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .tracking(1.5)
    }
}
