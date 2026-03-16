import SwiftUI

// MARK: - DebugPanelView

/// Internal debug / admin overlay showing BUTLER's live learning state.
///
/// ## What it shows
///   - Current intervention score breakdown for the active context
///   - Bayesian tolerance (α / β / %) for all 8 ButlerContext cases
///   - Daily rhythm: per-hour engagement bar chart
///   - Rolling intervention count + last-fired timestamp
///   - Quick-action buttons to simulate outcomes (for tuning/testing)
///
/// Access: long-press the status text in GlassChamberView (debug builds only).
struct DebugPanelView: View {

    var learningSystem:     LearningSystem
    var interventionEngine: InterventionEngine
    var activityMonitor:    ActivityMonitor
    var rhythmTracker:      DailyRhythmTracker
    var permissionSecurity: PermissionSecurityManager

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DebugTab = .score

    private let allContexts = ButlerContext.allCases

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            debugHeader
            Divider().opacity(0.25)

            tabBar
            Divider().opacity(0.15)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .score:   scoreTab
                    case .tolerance: toleranceTab
                    case .rhythm:  rhythmTab
                    }
                }
                .padding(18)
            }

            Divider().opacity(0.25)
            debugFooter
        }
        .frame(width: 440, height: 580)
        .background(.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Header

    private var debugHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.40, green: 1.00, blue: 0.55))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEBUG PANEL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Color(red: 0.40, green: 1.00, blue: 0.55))
                    Text("Learning & Intervention State")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Tab bar

    private enum DebugTab: String, CaseIterable {
        case score     = "Score"
        case tolerance = "Tolerance"
        case rhythm    = "Rhythm"
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DebugTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular,
                                      design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(selectedTab == tab
                                         ? Color(red: 0.40, green: 1.00, blue: 0.55)
                                         : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                            ? Color.white.opacity(0.05)
                            : Color.clear
                        )
                }
                .buttonStyle(.plain)

                if tab != DebugTab.allCases.last { Divider().opacity(0.15) }
            }
        }
    }

    // MARK: - Score tab

    private var scoreTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            let ctx   = activityMonitor.context
            let score = interventionEngine.interventionScore(for: ctx)

            // ── Live score bar ─────────────────────────────────────────────
            debugSection("LIVE SCORE") {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text(ctx.displayName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 90, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(scoreColor(score))
                                    .frame(width: geo.size.width * min(1, score))
                                // Threshold line at 0.65
                                Rectangle()
                                    .fill(.white.opacity(0.3))
                                    .frame(width: 1)
                                    .offset(x: geo.size.width * 0.65)
                            }
                        }
                        .frame(height: 10)

                        Text(String(format: "%.3f", score))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(scoreColor(score))
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Spacer().frame(width: 100)
                        Text("threshold: 0.650")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(score >= 0.65 ? "✓ WOULD FIRE" : "✗ below threshold")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(score >= 0.65
                                             ? Color(red: 0.40, green: 1.00, blue: 0.55)
                                             : .secondary)
                    }
                }
            }

            // ── Stats ─────────────────────────────────────────────────────
            debugSection("STATS") {
                HStack(spacing: 0) {
                    statCell(label: "THIS HOUR",
                             value: "\(interventionEngine.interventionsThisHour) / 3")
                    Divider().frame(height: 28).opacity(0.2)
                    statCell(label: "LAST FIRED",
                             value: lastFiredText)
                    Divider().frame(height: 28).opacity(0.2)
                    statCell(label: "SUPPRESSED",
                             value: permissionSecurity.suppressedNow ? "YES" : "NO",
                             valueColor: permissionSecurity.suppressedNow ? .red : .green)
                }
            }

            // ── Quick actions ─────────────────────────────────────────────
            debugSection("SIMULATE OUTCOME") {
                HStack(spacing: 10) {
                    actionButton("Accept", color: Color(red: 0.40, green: 1.00, blue: 0.55)) {
                        interventionEngine.recordAccepted(context: activityMonitor.context)
                    }
                    actionButton("Dismiss", color: Color(red: 1.00, green: 0.40, blue: 0.40)) {
                        interventionEngine.recordDismissed(context: activityMonitor.context)
                    }
                    actionButton("Manual Tap", color: Color(red: 0.75, green: 0.45, blue: 1.00)) {
                        interventionEngine.recordManualTrigger(context: activityMonitor.context)
                    }
                }
            }
        }
    }

    // MARK: - Tolerance tab

    private var toleranceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            debugSection("BAYESIAN TOLERANCE — ALL CONTEXTS") {
                VStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("CONTEXT")
                            .frame(width: 90, alignment: .leading)
                        Text("α")
                            .frame(width: 36, alignment: .trailing)
                        Text("β")
                            .frame(width: 36, alignment: .trailing)
                        Spacer()
                        Text("TOLERANCE")
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                    Divider().opacity(0.15)

                    ForEach(allContexts, id: \.rawValue) { ctx in
                        toleranceRow(ctx)
                    }
                }
            }

            // Reset buttons
            debugSection("RESET") {
                HStack(spacing: 10) {
                    actionButton("Reset Current", color: .orange) {
                        learningSystem.resetContext(activityMonitor.context)
                    }
                    actionButton("Reset All", color: .red) {
                        learningSystem.resetAll()
                    }
                }
            }
        }
    }

    private func toleranceRow(_ ctx: ButlerContext) -> some View {
        let model   = learningSystem.toleranceModel(for: ctx)
        let tol     = model.tolerance
        let isActive = ctx == activityMonitor.context

        return HStack(spacing: 0) {
            // Context name
            Text(ctx.displayName)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular,
                              design: .monospaced))
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: 90, alignment: .leading)

            // α and β
            Text(String(format: "%.1f", model.alpha))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Text(String(format: "%.1f", model.beta))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(toleranceColor(tol))
                        .frame(width: geo.size.width * tol)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 10)

            // Percentage
            Text(String(format: "%.0f%%", tol * 100))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(toleranceColor(tol))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isActive ? Color.white.opacity(0.04) : Color.clear)
    }

    // MARK: - Rhythm tab

    private var rhythmTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            debugSection("HOURLY ENGAGEMENT (0–23h)") {
                VStack(spacing: 6) {
                    // Bar chart — 24 hours
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<24, id: \.self) { hour in
                            let score    = rhythmTracker.engagementScore(hour: hour)
                            let isNow    = hour == Calendar.current.component(.hour, from: Date())
                            let hasData  = rhythmTracker.hourlyEngagement[hour] != nil

                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        isNow
                                        ? Color(red: 0.40, green: 1.00, blue: 0.55)
                                        : (hasData ? toleranceColor(score) : .white.opacity(0.08))
                                    )
                                    .frame(height: max(4, 60 * score))

                                if hour % 6 == 0 {
                                    Text("\(hour)h")
                                        .font(.system(size: 6, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Spacer().frame(height: 8)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 80)

                    HStack {
                        Circle()
                            .fill(Color(red: 0.40, green: 1.00, blue: 0.55))
                            .frame(width: 5, height: 5)
                        Text("current hour")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("multiplier: ×\(String(format: "%.2f", rhythmTracker.rhythmMultiplier))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            debugSection("CURRENT HOUR") {
                HStack(spacing: 0) {
                    statCell(label: "ENGAGEMENT",
                             value: String(format: "%.2f", rhythmTracker.currentEngagementScore))
                    Divider().frame(height: 28).opacity(0.2)
                    statCell(label: "MULTIPLIER",
                             value: "×\(String(format: "%.2f", rhythmTracker.rhythmMultiplier))")
                    Divider().frame(height: 28).opacity(0.2)
                    statCell(label: "DATA POINTS",
                             value: "\(rhythmTracker.hourlyEngagement.count) / 24 hrs")
                }
            }

            debugSection("SIMULATE") {
                HStack(spacing: 10) {
                    actionButton("Record Trigger", color: Color(red: 0.40, green: 1.00, blue: 0.55)) {
                        rhythmTracker.recordManualTrigger()
                    }
                    actionButton("Record Accept", color: .blue) {
                        rhythmTracker.recordAccept()
                    }
                    actionButton("Decay All", color: .orange) {
                        rhythmTracker.decayAll()
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var debugFooter: some View {
        HStack {
            Text("BUTLER DEBUG — internal only, not visible in production")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func debugSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            content()
        }
    }

    private func statCell(label: String, value: String,
                          valueColor: Color = .white.opacity(0.85)) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var lastFiredText: String {
        guard let date = interventionEngine.lastInterventionAt else { return "never" }
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60  { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs/60)m ago" }
        return "\(secs/3600)h ago"
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.65 { return Color(red: 0.40, green: 1.00, blue: 0.55) }
        if score >= 0.40 { return Color(red: 1.00, green: 0.75, blue: 0.20) }
        return .secondary
    }

    private func toleranceColor(_ tol: Double) -> Color {
        if tol >= 0.65 { return Color(red: 0.40, green: 1.00, blue: 0.55) }
        if tol >= 0.40 { return Color(red: 1.00, green: 0.75, blue: 0.20) }
        return Color(red: 1.00, green: 0.40, blue: 0.40)
    }
}
