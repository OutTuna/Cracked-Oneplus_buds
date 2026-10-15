import AppKit
import SwiftUI
import Combine
import EncoCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = EarbudsModel()
    let preferences = Preferences()
    var updates: UpdateController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let navigation = PanelNavigation()
    private var onboardingWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var closing = false
    private var allowClose = false
    private var closeWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updates = UpdateController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Artwork.icon(preferences.menuIcon)
            button.imagePosition = .imageOnly
            button.toolTip = "Enco Air5 Pro"
            button.target = self
            button.action = #selector(statusPressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Enco Air5 Pro")
        }
        preferences.$menuIcon.sink { [weak self] icon in guard let self else { return }; self.updateStatusBattery(self.model.batteries, connected: self.model.connected, style: icon) }.store(in: &subscriptions)
        model.$batteries.combineLatest(model.$connected).sink { [weak self] batteries, connected in
            self?.updateStatusBattery(batteries, connected: connected)
        }.store(in: &subscriptions)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let controller = NSHostingController(rootView: PanelView(model: model, preferences: preferences,
            updates: updates, navigation: navigation))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 352, height: 520)
        let menu = NSMenu()
        let root = NSMenuItem()
        root.submenu = contextMenu()
        menu.addItem(root)
        NSApp.mainMenu = menu
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showFromNotification), name: NSNotification.Name("io.github.OutTuna.EncoMenu.show"), object: nil)
        updates.start()
        model.start()
        if !preferences.hasChosenFinish { showOnboarding() } else { showPopover() }
    }

    private func updateStatusBattery(_ batteries: [UInt8: BatteryEntry], connected: Bool, style: MenuBarIcon? = nil) {
        guard let button = statusItem.button else { return }
        let level: (UInt8) -> String = { type in
            guard connected, let entry = batteries[type], let percent = entry.percent else { return "—" }
            return "\(percent)%"
        }
        let left = level(1), right = level(2)
        button.attributedTitle = NSAttributedString(string: "")
        button.image = Artwork.statusIcon(style ?? preferences.menuIcon, left: left, right: right)
        button.toolTip = "Enco Air5 Pro · Left \(left) · Right \(right)"
        button.setAccessibilityLabel("Enco Air5 Pro, left battery \(left), right battery \(right)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if preferences.hasChosenFinish { showPopover() } else { showOnboarding() }
        return true
    }

    @objc private func showFromNotification() { showPopover() }

    @objc private func statusPressed(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            beginClose()
            guard let button = statusItem.button else { return }
            contextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else if !preferences.hasChosenFinish { showOnboarding() }
        else if popover.isShown {
            if closing {
                closeWork?.cancel()
                closing = false
                model.panelOpen = true
            } else { beginClose() }
        } else { showPopover() }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Enco", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Enco", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        closeWork?.cancel()
        closing = false
        allowClose = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.title = "Enco Air5 Pro"
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.async { [weak self] in self?.model.panelOpen = true }
        if model.connected { model.refresh() } else if !model.connecting { model.connect() }
    }

    private func beginClose() {
        guard popover.isShown, !closing else { return }
        closing = true
        model.panelOpen = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.allowClose = true
            self.popover.performClose(nil)
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.5), execute: work)
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        if allowClose { return true }
        beginClose()
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelOpen = false
        closing = false
        allowClose = false
    }

    private func window<V: View>(title: String, size: NSSize, rootView: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.setContentSize(size)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = window(title: "Welcome to Enco", size: NSSize(width: 430, height: 460),
                rootView: OnboardingView(preferences: preferences) { [weak self] in
                    guard let self else { return }
                    self.preferences.hasChosenFinish = true
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    self.showPopover()
                })
        }
        present(onboardingWindow)
    }

    @objc func showSettings() {
        navigation.page = .settings
        showPopover()
    }

    @objc func showAbout() {
        navigation.showAbout()
        showPopover()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
