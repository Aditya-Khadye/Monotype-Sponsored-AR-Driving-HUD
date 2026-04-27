import Foundation

/// Thread-safe ring buffer that holds the last N records on-device.
/// Ensures no data loss during network hiccups — the Mac Mini
/// receiver can request a replay of buffered records on reconnect.
actor RingBuffer<T: Sendable> {

    private var storage: [T?]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    /// Add a record to the buffer (overwrites oldest if full)
    func push(_ item: T) {
        storage[head] = item
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Get all buffered records in chronological order
    func drain() -> [T] {
        guard count > 0 else { return [] }

        var result: [T] = []
        result.reserveCapacity(count)

        let start = (head - count + capacity) % capacity
        for i in 0..<count {
            let idx = (start + i) % capacity
            if let item = storage[idx] {
                result.append(item)
            }
        }
        return result
    }

    /// Number of records currently buffered
    var size: Int { count }

    /// Clear all records
    func clear() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }
}
