import AppKit

let showPanelNotification = Notification.Name("com.eso.atac.showPanel")
let currentPID = ProcessInfo.processInfo.processIdentifier

// Terminate any legacy bundle-ID process from older alpha builds
for legacyApp in NSRunningApplication.runningApplications(withBundleIdentifier: "com.atac.clipboard")
where legacyApp.processIdentifier != currentPID {
    legacyApp.terminate()
}

// Enforce single instance: if Ataç is already running, ask it to open its popup and exit cleanly
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != currentPID }
    if let existing = others.first {
        DistributedNotificationCenter.default().postNotificationName(
            showPanelNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        existing.activate(options: [])
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
