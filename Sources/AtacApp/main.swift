import AppKit

// Prevent duplicate menu bar instances if launched twice
if let bundleID = Bundle.main.bundleIdentifier {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    let currentPID = ProcessInfo.processInfo.processIdentifier
    if running.contains(where: { $0.processIdentifier != currentPID }) {
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
