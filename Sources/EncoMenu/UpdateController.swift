import AppKit
import Combine
import Sparkle

@MainActor final class UpdateController: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var automatic: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automatic
            controller.updater.automaticallyDownloadsUpdates = automatic
        }
    }
    @Published var canCheck = true
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automatic = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func start() { controller.startUpdater() }
    func check() { NSApp.activate(ignoringOtherApps: true); controller.checkForUpdates(nil) }
    var lastCheck: String {
        guard let date = controller.updater.lastUpdateCheckDate else { return "Not yet checked" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
