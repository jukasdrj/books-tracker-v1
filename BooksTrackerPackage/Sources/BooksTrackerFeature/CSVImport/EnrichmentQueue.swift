import Foundation
import SwiftData

@MainActor
public final class EnrichmentQueue {

    // MARK: - Properties

    public static let shared = EnrichmentQueue()

    private var queue: [EnrichmentQueueItem] = []
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
    }

    // MARK: - Initialization

    private init() {
        loadQueue()
    }

    // MARK: - Public Methods

    public func enqueue(workID: PersistentIdentifier, priority: Int = 0) {
        guard !queue.contains(where: { $0.workPersistentID == workID }) else { return }

        let item = EnrichmentQueueItem(workPersistentID: workID, priority: priority)
        queue.append(item)
        sortQueue()
        saveQueue()
    }

    public func enqueueBatch(_ workIDs: [PersistentIdentifier]) {
        for workID in workIDs {
            enqueue(workID: workID)
        }
    }

    public func prioritize(workID: PersistentIdentifier) {
        if let index = queue.firstIndex(where: { $0.workPersistentID == workID }) {
            var item = queue.remove(at: index)
            item.priority = 1000
            queue.insert(item, at: 0)
        } else {
            enqueue(workID: workID, priority: 1000)
        }
        saveQueue()
    }

    public func pop() -> PersistentIdentifier? {
        guard !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        saveQueue()
        return item.workPersistentID
    }

    public func count() -> Int {
        return queue.count
    }

    public func clear() {
        queue.removeAll()
        saveQueue()
    }

    public func validateQueue(in modelContext: ModelContext) {
        let initialCount = queue.count
        queue.removeAll { item in
            modelContext.model(for: item.workPersistentID) as? Work == nil
        }
        if initialCount != queue.count {
            saveQueue()
        }
    }

    // MARK: - Private Methods

    private func sortQueue() {
        queue.sort {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.addedDate < $1.addedDate
        }
    }

    private func saveQueue() {
        if let encoded = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(encoded, forKey: queueStorageKey)
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey),
              let decoded = try? JSONDecoder().decode([EnrichmentQueueItem].self, from: data) else {
            return
        }
        queue = decoded
    }
}

extension ModelContext {
    public func work(for id: PersistentIdentifier) -> Work? {
        return model(for: id) as? Work
    }
}