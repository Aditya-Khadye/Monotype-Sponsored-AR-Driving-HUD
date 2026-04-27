import Foundation
import Network

/// Streams TelemetryRecords over TCP to the Mac Mini data hub.
/// Sends newline-delimited JSON (NDJSON) for easy parsing.
/// Auto-reconnects on disconnect with exponential backoff.
@MainActor
final class NetworkStreamer: ObservableObject {

    @Published var isConnected = false
    @Published var recordsSent: UInt64 = 0

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "net.streamer", qos: .utility)
    private let encoder = JSONEncoder()

    private var macIP: String = ""
    private var macPort: UInt16 = 5555
    private var shouldReconnect = false
    private var reconnectDelay: TimeInterval = 1.0

    init() {
        encoder.dateEncodingStrategy = .iso8601
    }

    // ── Connect to Mac Mini ──────────────────────────────────

    func connect(ip: String, port: UInt16 = 5555) {
        macIP = ip
        macPort = port
        shouldReconnect = true
        reconnectDelay = 1.0
        establishConnection()
    }

    func disconnect() {
        shouldReconnect = false
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func establishConnection() {
        guard shouldReconnect else { return }

        let host = NWEndpoint.Host(macIP)
        guard let port = NWEndpoint.Port(rawValue: macPort) else { return }

        let conn = NWConnection(host: host, port: port, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.reconnectDelay = 1.0
                    print("[Streamer] Connected to \(self.macIP):\(self.macPort)")

                case .failed(let error):
                    print("[Streamer] Connection failed: \(error)")
                    self.isConnected = false
                    self.scheduleReconnect()

                case .cancelled:
                    self.isConnected = false

                default:
                    break
                }
            }
        }

        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)  // cap at 30s

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                if self.shouldReconnect {
                    print("[Streamer] Reconnecting (delay: \(delay)s)...")
                    self.establishConnection()
                }
            }
        }
    }

    // ── Send a record ────────────────────────────────────────

    func send(_ record: TelemetryRecord) {
        guard isConnected, let conn = connection else { return }

        do {
            var jsonData = try encoder.encode(record)
            jsonData.append(0x0A)  // newline delimiter (NDJSON)

            conn.send(content: jsonData, completion: .contentProcessed { [weak self] error in
                if let error {
                    print("[Streamer] Send error: \(error)")
                } else {
                    Task { @MainActor in
                        self?.recordsSent += 1
                    }
                }
            })
        } catch {
            print("[Streamer] Encode error: \(error)")
        }
    }

    // ── Bulk send (for ring buffer replay) ───────────────────

    func sendBatch(_ records: [TelemetryRecord]) {
        for record in records {
            send(record)
        }
    }
}
