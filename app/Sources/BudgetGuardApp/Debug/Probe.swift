import AppKit
import BudgetGuardCore

/// `BudgetGuardApp --probe web|claude-code`: prints one line and exits. Never prints identifiers.
@MainActor
enum Probe {
    static func run(_ which: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var line: String?
        let source: UsageSource
        switch which {
        case "web": source = WebSessionSource()
        case "claude-code": source = ClaudeCodeSource()
        default:
            print("usage: --probe web|claude-code")
            exit(2)
        }

        Task { @MainActor in
            do {
                let s = try await source.fetchSnapshot()
                var text = Copy.percentTitle(s.weeklyPercent)
                if let r = s.resetsAt { text += " — " + Copy.resetLine(r, now: Date(), calendar: .current) }
                line = text
            } catch let e as UsageFetchError {
                line = "error: \(e)"
            } catch {
                line = "error: network"
            }
        }

        let deadline = Date().addingTimeInterval(30)
        while line == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        print(line ?? "error: network")
        exit(line?.hasPrefix("error") == true ? 1 : 0)
    }
}
