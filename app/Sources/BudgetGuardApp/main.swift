import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--probe"), i + 1 < args.count {
    MainActor.assumeIsolated { Probe.run(args[i + 1]) }
}
if args.contains("--logout") {
    MainActor.assumeIsolated { LoginTest.logout() }
}
if args.contains("--login-test") {
    let snap = args.firstIndex(of: "--snapshot").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    MainActor.assumeIsolated { LoginTest.run(snapshotPath: snap) }
}

// No debug flag: run the real menu bar app.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
}
