import Foundation
import Network

/// Listens on UDP port 4444 for OutGauge packets from BeamNG.drive
/// Publishes parsed packets to SwiftUI views via @Published
@MainActor
final class UDPReceiver: ObservableObject {

    static let shared = UDPReceiver()

    @Published var latest: OutGaugePacket? = nil
    @Published var isListening = false
    @Published var packetsReceived: UInt64 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "outgauge.udp", qos: .userInteractive)

    // ── Start listening ──────────────────────────────────────
    func start(port: UInt16 = 4444) {
        guard listener == nil else { return }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: nwPort) else {
            print("[UDPReceiver] Cannot bind port \(port)")
            return
        }
        listener = l

        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isListening = true
                    print("[UDPReceiver] Listening on UDP :\(port)")
                case .failed(let error):
                    print("[UDPReceiver] Failed: \(error)")
                    self?.isListening = false
                case .cancelled:
                    self?.isListening = false
                default:
                    break
                }
            }
        }

        // Each incoming UDP datagram arrives as a new NWConnection
        l.newConnectionHandler = { [weak self] conn in
            self?.receive(on: conn)
            conn.start(queue: self?.queue ?? .main)
        }

        l.start(queue: queue)
    }

    // ── Stop listening ───────────────────────────────────────
    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        print("[UDPReceiver] Stopped")
    }

    // ── Receive a single datagram ────────────────────────────
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, let pkt = OutGaugePacket(data: data) {
                Task { @MainActor [weak self] in
                    self?.latest = pkt
                    self?.packetsReceived += 1
                }
            }
            if let error {
                print("[UDPReceiver] Receive error: \(error)")
            }
            connection.cancel() // UDP: one datagram per NWConnection
        }
    }
}
