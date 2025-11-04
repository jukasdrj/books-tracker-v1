import Foundation

/// Tracks app launch performance metrics
@MainActor
public final class LaunchMetrics {
    public static let shared = LaunchMetrics()

    private var launchStartTime: CFAbsoluteTime?
    private var milestones: [(String, CFAbsoluteTime)] = []

    private init() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
        print("🚀 Launch tracking started")
    }

    /// Record a milestone during app launch
    public func recordMilestone(_ name: String) {
        let timestamp = CFAbsoluteTimeGetCurrent()
        milestones.append((name, timestamp))

        if let start = launchStartTime {
            let elapsed = (timestamp - start) * 1000 // Convert to ms
            print("⏱️ \(name): +\(Int(elapsed))ms")
        }
    }

    /// Get total launch time
    public func totalLaunchTime() -> Double? {
        guard let start = launchStartTime,
              let lastMilestone = milestones.last else { return nil }
        return (lastMilestone.1 - start) * 1000 // ms
    }

    /// Print full launch report
    public func printReport() {
        guard let start = launchStartTime else { return }
        print("\n📊 Launch Performance Report")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        for (name, timestamp) in milestones {
            let elapsed = (timestamp - start) * 1000
            print("  \(name): +\(Int(elapsed))ms")
        }

        if let total = totalLaunchTime() {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("  Total: \(Int(total))ms")
        }
        print()
    }
}
