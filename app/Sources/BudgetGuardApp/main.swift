import Foundation

// Placeholder, replaced in Task 6.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--probe"), i + 1 < args.count {
    MainActor.assumeIsolated { Probe.run(args[i + 1]) }
}
print("Budget Guard")
