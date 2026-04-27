import Foundation

/// Parses the 96-byte OutGauge UDP packet from BeamNG.drive
/// Layout: little-endian, matches LFS OutGauge spec
///
/// Offset  Type       Field
/// ──────  ─────────  ──────────
/// 0       UInt32     time (ms)
/// 4       char[4]    car
/// 8       UInt16     flags
/// 10      UInt8      gear (0=R, 1=N, 2=1st …)
/// 11      UInt8      plid
/// 12      Float      speed (m/s)
/// 16      Float      rpm
/// 20      Float      turbo (bar)
/// 24      Float      engTemp (°C)
/// 28      Float      fuel (0.0–1.0)
/// 32      Float      oilPressure (bar)
/// 36      Float      oilTemp (°C)
/// 40      Float      throttle (0.0–1.0)
/// 44      Float      brake (0.0–1.0)
/// 48      Float      clutch (0.0–1.0)
/// 52      char[16]   display1
/// 68      char[16]   display2
/// 84      Int32      id
/// 88      Float      dashLightShift
/// 92      Float      dashLightFullBeam

struct OutGaugePacket {
    let time: UInt32
    let car: String
    let flags: UInt16
    let gear: UInt8
    let plid: UInt8
    let speed: Float      // m/s
    let rpm: Float
    let turbo: Float
    let engTemp: Float
    let fuel: Float
    let oilPressure: Float
    let oilTemp: Float
    let throttle: Float
    let brake: Float
    let clutch: Float
    let display1: String
    let display2: String
    let id: Int32
    let dashLightShift: Float
    let dashLightFullBeam: Float

    // ── Computed ──────────────────────────────────────────────
    var speedKMH: Float { speed * 3.6 }
    var speedMPH: Float { speed * 2.23694 }

    var gearLabel: String {
        switch gear {
        case 0:  return "R"
        case 1:  return "N"
        default: return "\(gear - 1)"
        }
    }

    // ── Flag helpers ─────────────────────────────────────────
    var shiftLight: Bool   { flags & (1 << 0) != 0 }
    var fullBeam: Bool     { flags & (1 << 1) != 0 }
    var handbrake: Bool    { flags & (1 << 2) != 0 }
    var tcActive: Bool     { flags & (1 << 4) != 0 }
    var signalLeft: Bool   { flags & (1 << 5) != 0 }
    var signalRight: Bool  { flags & (1 << 6) != 0 }
    var oilWarn: Bool      { flags & (1 << 7) != 0 }
    var batteryWarn: Bool  { flags & (1 << 8) != 0 }
    var absActive: Bool    { flags & (1 << 9) != 0 }
    var useKMH: Bool       { flags & (1 << 15) != 0 }

    // ── Init from raw UDP data ───────────────────────────────
    init?(data: Data) {
        guard data.count >= 96 else { return nil }

        var offset = 0

        func read<T>(_ type: T.Type) -> T {
            let size = MemoryLayout<T>.size
            let value = data.subdata(in: offset..<offset+size)
                .withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            offset += size
            return value
        }

        func readString(_ length: Int) -> String {
            let bytes = data.subdata(in: offset..<offset+length)
            offset += length
            return String(bytes: bytes, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters) ?? ""
        }

        time         = read(UInt32.self)
        car          = readString(4)
        flags        = read(UInt16.self)
        gear         = read(UInt8.self)
        plid         = read(UInt8.self)
        speed        = read(Float.self)
        rpm          = read(Float.self)
        turbo        = read(Float.self)
        engTemp      = read(Float.self)
        fuel         = read(Float.self)
        oilPressure  = read(Float.self)
        oilTemp      = read(Float.self)
        throttle     = read(Float.self)
        brake        = read(Float.self)
        clutch       = read(Float.self)
        display1     = readString(16)
        display2     = readString(16)
        id           = read(Int32.self)
        dashLightShift    = read(Float.self)
        dashLightFullBeam = read(Float.self)
    }
}
