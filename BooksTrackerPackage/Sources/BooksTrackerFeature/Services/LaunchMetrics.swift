import Foundation

/// Tracks app launch performance metrics
@MainActor
public final class LaunchMetrics {
    public static let shared = LaunchMetrics()

    private let launchStartTime: CFAbsoluteTime
    private var milestones: [(String, CFAbsoluteTime)] = []

    private init() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        print("🚀 Launch tracking started")
        #endif
    }

    /// Record a milestone during app launch
    public func recordMilestone(_ name: String) {
        let timestamp = CFAbsoluteTimeGetCurrent()
        milestones.append((name, timestamp))
        #if DEBUG
        let elapsed = (timestamp - launchStartTime) * 1000
        #if DEBUG
        print("⏱️ \(name): +\(Int(elapsed))ms")
        #endif
        #endif
    }

    /// Get total launch time
    public func totalLaunchTime() -> Double? {
        guard let lastMilestone = milestones.last else { return nil }
        return (lastMilestone.1 - launchStartTime) * 1000
    }

    /// Print full launch report
    public func printReport() {
        #if DEBUG
        guard !milestones.isEmpty else { return }
        #if DEBUG
        print("\n📊 Launch Performance Report")
        #endif
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        for (name, timestamp) in milestones {
            let elapsed = (timestamp - launchStartTime) * 1000
            #if DEBUG
            print("  \(name): +\(Int(elapsed))ms")
            #endif
        }
        if let total = totalLaunchTime() {
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
            #if DEBUG
            print("  Total: \(Int(total))ms")
            #endif
        }
        #if DEBUG
        print()
        #endif
        #endif
    }
}
