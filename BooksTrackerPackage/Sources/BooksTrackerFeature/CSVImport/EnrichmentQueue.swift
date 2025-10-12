import Foundation
import SwiftData

// MARK: - Enrichment Queue
/// Priority queue for managing background enrichment of imported books
/// Supports FIFO ordering with ability to prioritize specific items (e.g., user scrolled to book)
/// MainActor-isolated for SwiftData compatibility
@MainActor
public final class EnrichmentQueue {
    public static let shared = EnrichmentQueue()

    // MARK: - Properties

    private var queue: [EnrichmentQueueItem] = []
    private var processing: Bool = false
    private var currentTask: Task<Void, Never>?

    // Persistence
    private let queueStorageKey = "EnrichmentQueueStorage"

    // MARK: - Queue Item

    public struct EnrichmentQueueItem: Codable, Sendable, Identifiable {
        public let id: UUID
        public let workPersistentID: PersistentIdentifier
        public var priority: Int
        public let addedDate: Date

        public init(workPersistentID: PersistentIdentifier, priority: Int = 0) {
            self.id = UUID()
            self.workPersistentID = workPersistentID
            self.priority = priority
            self.addedDate = Date()
        }

        // Make the priority mutable for updates
        public mutating func setPriority(_ newPriority: Int) {
            priority = newPriority
        }
    }

    // MARK: - Initialization

    private init() {
        loadQueue()
    }

    // MARK: - Public Methods

    /// Add a work to the enrichment queue
    public func enqueue(workID: PersistentIdentifier, priority: Int = 0) {
        // Check if already in queue
        guard !queue.contains(where: { $0.workPersistentID == workID }) else {
            return
        }

        let item = EnrichmentQueueItem(workPersistentID: workID, priority: priority)
        queue.append(item)

        // Sort by priority (higher priority first), then by date (FIFO)
        queue.sort {
            if $0.priority == $1.priority {
                return $0.addedDate < $1.addedDate
            }
            return $0.priority > $1.priority
        }

        saveQueue()
    }

    /// Add multiple works to the queue
    public func enqueueBatch(_ workIDs: [PersistentIdentifier]) {
        for workID in workIDs {
            enqueue(workID: workID)
        }
    }

    /// Move a specific work to the front of the queue (e.g., user viewed it)
    public func prioritize(workID: PersistentIdentifier) {
        guard let index = queue.firstIndex(where: { $0.workPersistentID == workID }) else {
            // Not in queue - add it with high priority
            enqueue(workID: workID, priority: 1000)
            return
        }

        // Update priority and re-sort
        let item = queue[index]
        queue.remove(at: index)

        var mutableItem = item
        mutableItem.priority = 1000 // High priority
        queue.insert(mutableItem, at: 0) // Move to front

        saveQueue()
    }

    /// Remove a work from the queue
    public func dequeue(workID: PersistentIdentifier) {
        queue.removeAll { $0.workPersistentID == workID }
        saveQueue()
    }

    /// Get the next work to enrich (highest priority / oldest)
    public func next() -> PersistentIdentifier? {
        return queue.first?.workPersistentID
    }

    /// Remove and return the next work to enrich
    public func pop() -> PersistentIdentifier? {
        guard !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        saveQueue()
        return item.workPersistentID
    }

    /// Get current queue size
    public func count() -> Int {
        return queue.count
    }

    /// Clear all items from the queue
    public func clear() {
        queue.removeAll()
        saveQueue()
        print("🧹 EnrichmentQueue cleared")
    }

    /// Validate queue on startup - remove invalid persistent IDs
    public func validateQueue(in modelContext: ModelContext) {
        let initialCount = queue.count

        queue.removeAll { item in
            // Try to fetch the work - if it fails, remove from queue
            if modelContext.model(for: item.workPersistentID) as? Work == nil {
                print("🧹 Removing invalid work ID from queue")
                return true  // Remove this item
            }
            return false  // Keep this item
        }

        let removedCount = initialCount - queue.count
        if removedCount > 0 {
            print("🧹 Queue cleanup: Removed \(removedCount) invalid items (was \(initialCount), now \(queue.count))")
            saveQueue()  // Persist cleanup
        }
    }

    /// Check if queue is empty
    public func isEmpty() -> Bool {
        return queue.isEmpty
    }

    /// Get all pending work IDs (for debugging/monitoring)
    public func getAllPending() -> [PersistentIdentifier] {
        return queue.map { $0.workPersistentID }
    }

    // MARK: - Background Processing

    /// Start background enrichment process
    /// - Parameters:
    ///   - modelContext: SwiftData model context for database operations
    ///   - progressHandler: Callback with (processed, total, currentTitle)
    public func startProcessing(
        in modelContext: ModelContext,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) {
        // Don't start if already processing
        guard !processing else { return }

        processing = true
        let totalCount = queue.count

        // Notify ContentView that enrichment started
        NotificationCenter.default.post(
            name: NSNotification.Name("EnrichmentStarted"),
            object: nil,
            userInfo: ["totalBooks": totalCount]
        )

        currentTask = Task {
            var processedCount = 0

            while !queue.isEmpty {
                // Check for cancellation
                guard !Task.isCancelled else {
                    processing = false
                    return
                }

                // Get next work to enrich
                guard let workID = pop() else { break }

                // Fetch work from context - handle deleted works gracefully
                guard let work = modelContext.model(for: workID) as? Work else {
                    // Work was deleted - remove from persisted queue
                    print("⚠️ Skipping deleted work (cleaning up queue)")
                    saveQueue()  // Persist cleanup immediately
                    continue
                }

                // Enrich the work
                let result = await EnrichmentService.shared.enrichWork(work, in: modelContext)

                processedCount += 1

                // Report progress with current book title
                progressHandler(processedCount, totalCount, work.title)

                // Notify ContentView of progress update
                NotificationCenter.default.post(
                    name: NSNotification.Name("EnrichmentProgress"),
                    object: nil,
                    userInfo: [
                        "completed": processedCount,
                        "total": totalCount,
                        "currentTitle": work.title
                    ]
                )

                // Log result
                switch result {
                case .success:
                    print("✅ Enriched: \(work.title)")
                case .failure(let error):
                    print("⚠️ Failed to enrich \(work.title): \(error)")
                }

                // Yield to avoid blocking
                await Task.yield()
            }

            processing = false

            // Notify ContentView that enrichment completed
            NotificationCenter.default.post(
                name: NSNotification.Name("EnrichmentCompleted"),
                object: nil
            )
        }
    }

    /// Stop background processing
    public func stopProcessing() {
        currentTask?.cancel()
        currentTask = nil
        processing = false
    }

    /// Check if currently processing
    public func isProcessing() -> Bool {
        return processing
    }

    // MARK: - Persistence

    private func saveQueue() {
        // Encode queue to UserDefaults
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(queue) {
            UserDefaults.standard.set(encoded, forKey: queueStorageKey)
        }
    }

    private func loadQueue() {
        // Decode queue from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey) else {
            return
        }

        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([EnrichmentQueueItem].self, from: data) {
            queue = decoded
        }
    }
}

// MARK: - Convenience Extension for ModelContext

extension ModelContext {
    /// Get a work by its persistent identifier
    public func work(for id: PersistentIdentifier) -> Work? {
        return model(for: id) as? Work
    }
}
