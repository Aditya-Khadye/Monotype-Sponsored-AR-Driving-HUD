import Foundation

struct OutGaugePacket: Equatable {

    let time: UInt32
    let car: String
    let flags: UInt16
    let gear: UInt8
    let plid: UInt8
    let speed: Float
    let rpm: Float
    let turbo: Float
    let engTemp: Float
    let fuel: Float
    let oilPressure: Float
    let oilTemp: Float
    let throttle: Float
    let brake: Float
    let clutch: Float

    var speedKMH: Float { speed * 3.6 }
    var speedMPH: Float { speed * 2.23694 }

    var gearLabel: String {
        switch gear {
        case 0:  return "R"
        case 1:  return "N"
        default: return "\(gear - 1)"
        }
    }

    var absActive: Bool   { flags & (1 << 9) != 0 }
    var tcActive: Bool    { flags & (1 << 4) != 0 }
    var handbrake: Bool   { flags & (1 << 2) != 0 }
    var signalLeft: Bool  { flags & (1 << 5) != 0 }
    var signalRight: Bool { flags & (1 << 6) != 0 }

    init?(data: Data) {
        guard data.count >= 64 else { return nil }

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

        time        = read(UInt32.self)
        car         = readString(4)
        flags       = read(UInt16.self)
        gear        = read(UInt8.self)
        plid        = read(UInt8.self)
        speed       = read(Float.self)
        rpm         = read(Float.self)
        turbo       = read(Float.self)
        engTemp     = read(Float.self)
        fuel        = read(Float.self)
        oilPressure = read(Float.self)
        oilTemp     = read(Float.self)
        throttle    = read(Float.self)
        brake       = read(Float.self)
        clutch      = read(Float.self)
    }
}
