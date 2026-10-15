import AppKit
import SwiftUI
import EncoCore

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ListeningButton: View {
    let mode: ANCMode
    let selected: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var title: String {
        switch mode { case .on: return "ANC"; case .off: return "OFF"; case .transparency: return "TRANSPARENCY" }
    }
    var symbol: String {
        switch mode { case .on: return "waveform.slash"; case .off: return "power"; case .transparency: return "waveform" }
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(height: 21)
                Text(title).font(.system(size: mode == .transparency ? 8.5 : 10, weight: .semibold, design: .rounded)).tracking(0.6)
            }
            .frame(maxWidth: .infinity).frame(height: 70)
            .foregroundStyle(selected ? (scheme == .dark ? Color.black : Color.white) : Color.primary.opacity(disabled ? 0.35 : 0.7))
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(selected ? Color.primary : Color.primary.opacity(hovering && !disabled ? 0.10 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.primary.opacity(selected ? 0 : 0.055), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .accessibilityLabel(mode == .on ? "Noise cancellation" : mode == .off ? "Noise control off" : "Transparency")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BatteryRing: View {
    let title: String
    let entry: BatteryEntry?
    let kind: MenuBarIcon
    var side: Int? = nil
    var percent: Int? { entry?.percent }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.09), lineWidth: 3.8)
                if let percent {
                    Circle().trim(from: 0, to: CGFloat(percent) / 100)
                        .stroke(Color.primary.opacity(percent <= 20 ? 0.45 : 0.85), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(nsImage: Artwork.icon(kind, side: side))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 25, height: 24)
                    .foregroundStyle(Color.primary.opacity(percent == nil ? 0.28 : 0.78))
                if entry?.charging == true {
                    Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                        .padding(3).background(.regularMaterial, in: Circle()).offset(y: -27)
                }
            }
            .frame(width: 55, height: 55)
            Text(percent.map { "\($0)%" } ?? "—").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(percent == nil ? "Battery not reported by the earbuds" : "\(title) battery: \(percent!) percent")
        .accessibilityElement(children: .combine)
    }
}

struct PopoverView: View {
    @ObservedObject var model: EarbudsModel
    @ObservedObject var preferences: Preferences
    var onSettings: () -> Void
    var onAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enco Air5 Pro").font(.system(size: 17, weight: .semibold))
                    Text(preferences.finish.title).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).contentShape(Circle())
                }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            }
            .frame(height: 36)
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.primary.opacity(0.055)).frame(width: 148, height: 12).blur(radius: 10).offset(y: -8)
                EarbudArtworkView(finish: preferences.finish, opened: model.panelOpen)
            }
            .frame(height: 184)
            .accessibilityLabel("OPPO Enco Air5 Pro in \(preferences.finish.title)")
            HStack(spacing: 0) {
                BatteryRing(title: "Left", entry: model.batteries[1], kind: .earbuds, side: 1)
                BatteryRing(title: "Right", entry: model.batteries[2], kind: .earbuds, side: 2)
                BatteryRing(title: "Case", entry: model.batteries[3], kind: .chargingCase)
            }
            .padding(.horizontal, 8)
            .frame(height: 94)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.vertical, 15)
            HStack {
                Text("NOISE CONTROL").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                if model.busy && model.connected { ProgressView().controlSize(.mini).scaleEffect(0.7) }
            }
            .frame(height: 14).padding(.bottom, 9)
            HStack(spacing: 8) {
                ForEach([ANCMode.on, .off, .transparency], id: \.rawValue) { mode in
                    ListeningButton(mode: mode, selected: model.mode == mode, disabled: !model.connected || model.busy) { model.select(mode) }
                }
            }
            .animation(.easeInOut(duration: 0.16), value: model.mode)
            Group {
                if let notice = model.notice {
                    Text(notice).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                } else { Color.clear }
            }
            .frame(height: 34)
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green.opacity(0.8) : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(model.connectionLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if model.connecting { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                else if !model.connected {
                    Button("Connect") { model.connect() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                } else {
                    Button(action: onAbout) { Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("About Enco").accessibilityLabel("About Enco")
                }
            }
            .frame(height: 19)
        }
        .padding(20)
        .frame(width: 352)
        .background(GlassBackground())
    }
}

struct FinishChoices: View {
    @Binding var selection: EarbudFinish

    var body: some View {
        HStack(spacing: 10) {
            ForEach(EarbudFinish.allCases) { finish in
                Button { selection = finish } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Color(nsColor: finish.color)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        Text(finish.title).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        if selection == finish { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.primary) }
                    }
                    .padding(12).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(selection == finish ? 0.065 : 0.025)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(selection == finish ? 0.4 : 0.1), lineWidth: selection == finish ? 1 : 0.5))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == finish ? .isSelected : [])
            }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var preferences: Preferences
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Meet your Enco.").font(.system(size: 27, weight: .semibold)).padding(.top, 30)
            Text("Choose your finish.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 7)
            EarbudArtworkView(finish: preferences.finish, opened: appeared).frame(height: 235)
            FinishChoices(selection: $preferences.finish)
            Button("Continue", action: onContinue).buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction).padding(.top, 24)
        }
        .padding(.horizontal, 28).padding(.bottom, 28).frame(width: 430)
        .background(GlassBackground())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { appeared = true } }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var updates: UpdateController
    var onAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                Text("Earbud finish").font(.system(size: 12, weight: .medium))
                FinishChoices(selection: $preferences.finish)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Menu bar icon").font(.system(size: 12, weight: .medium))
                Picker("Menu bar icon", selection: $preferences.menuIcon) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        Label { Text(icon.title) } icon: { Image(nsImage: Artwork.icon(icon)) }.tag(icon)
                    }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Automatic updates", isOn: $updates.automatic).toggleStyle(.switch).controlSize(.small)
                Text("Keep Enco up to date with signed updates.").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text("Version \(AppInfo.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
                }
            }
            HStack {
                Spacer()
                Button("About Enco", action: onAbout).buttonStyle(.link)
            }
        }
        .padding(28).frame(width: 440).background(GlassBackground())
    }
}

struct AboutView: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var model: EarbudsModel

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
            Text("Enco").font(.system(size: 26, weight: .semibold))
            Text("Version \(AppInfo.version) (\(AppInfo.build))").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.connected {
                Text("Earbuds firmware \(model.firmware)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Link(destination: AppInfo.repository) {
                Label("GitHub Repository", systemImage: "arrow.up.right").font(.system(size: 12))
            }.padding(.top, 3)
            Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck).padding(.top, 7)
            Text(updates.lastCheck == "Not yet checked" ? updates.lastCheck : "Last checked \(updates.lastCheck)")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(30).frame(width: 350).background(GlassBackground())
    }
}

enum AppInfo {
    static let repository = URL(string: "https://github.com/OutTuna/Cracked-Oneplus_buds")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2" }
}
