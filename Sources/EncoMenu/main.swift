import AppKit

MainActor.assumeIsolated {
let application = NSApplication.shared
if CommandLine.arguments.count == 3, ["--export-icon", "--export-black-icon"].contains(CommandLine.arguments[1]) {
    do { try Artwork.exportIcon(to: URL(fileURLWithPath: CommandLine.arguments[2]), finish: CommandLine.arguments[1] == "--export-black-icon" ? .matteBlack : .pearlWhite); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
}
if let identifier = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    existing.activate(options: [.activateIgnoringOtherApps])
    DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("io.github.OutTuna.EncoMenu.show"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
let delegate = AppDelegate()
application.delegate = delegate
withExtendedLifetime(delegate) { application.run() }
}
