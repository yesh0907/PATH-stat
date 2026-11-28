import Compression
import Foundation

enum ScheduleZIP {
    static func extract(_ archive: Data, names: Set<String>) throws -> [String: Data] {
        let bytes = [UInt8](archive)
        let limit = 16 * 1024 * 1024
        guard bytes.count >= 22, bytes.count <= limit else { throw ScheduleError.invalidArchive }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x06054b50 && $0 + 22 + u16($0 + 20) == bytes.count }),
              u16(end + 4) == 0, u16(end + 6) == 0, u16(end + 8) == u16(end + 10)
        else { throw ScheduleError.invalidArchive }
        var offset = u32(end + 16)
        guard offset + u32(end + 12) == end else { throw ScheduleError.invalidArchive }
        var budget = limit
        var files: [String: Data] = [:]
        for _ in 0..<u16(end + 10) {
            guard offset + 46 <= end, u32(offset) == 0x02014b50 else { throw ScheduleError.invalidArchive }
            let start = offset + 46
            let nameEnd = start + u16(offset + 28)
            let next = nameEnd + u16(offset + 30) + u16(offset + 32)
            guard next <= end else { throw ScheduleError.invalidArchive }
            defer { offset = next }
            let name = String(decoding: bytes[start..<nameEnd], as: UTF8.self)
            guard names.contains(name) else { continue }
            let local = u32(offset + 42)
            let packed = u32(offset + 20)
            let size = u32(offset + 24)
            guard files[name] == nil, u16(offset + 8) & 1 == 0, local + 30 <= offset,
                  u32(local) == 0x04034b50, size <= budget
            else { throw ScheduleError.invalidArchive }
            let dataStart = local + 30 + u16(local + 26) + u16(local + 28)
            guard dataStart + packed <= offset else { throw ScheduleError.invalidArchive }
            budget -= size
            switch u16(offset + 10) {
            case 0 where packed == size:
                files[name] = Data(bytes[dataStart..<(dataStart + packed)])
            case 8 where size > 0 && packed > 0:
                var data = Data(count: size + 1)
                let decoded = data.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                    bytes.withUnsafeBufferPointer { input in
                        compression_decode_buffer(
                            output.bindMemory(to: UInt8.self).baseAddress!, size + 1,
                            input.baseAddress! + dataStart, packed, nil, COMPRESSION_ZLIB
                        )
                    }
                }
                guard decoded == size else { throw ScheduleError.invalidArchive }
                data.removeLast()
                files[name] = data
            default:
                throw ScheduleError.invalidArchive
            }
        }
        guard offset == end else { throw ScheduleError.invalidArchive }
        return files
    }
}
