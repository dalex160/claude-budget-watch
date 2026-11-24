import Foundation

// Placeholder, replaced in Task 6.
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
print("Budget Guard")
