import Foundation
import CryptoKit
import zlib

/// QrProtocol — формат содержимого QR-кодов (единый с Android-версией).
///
/// Заголовок сессии ("t":"h"):
///   {"v":1,"t":"h","sid":"<16 hex>","name":"photo.jpg","mime":"image/jpeg",
///    "size":5242880,"sha":"<sha256 hex>","total":6554,"cs":800,"nonce":"<8 hex>"}
///
/// Фрагмент данных ("t":"d"):
///   {"v":1,"t":"d","sid":"<16 hex>","i":123,"d":"<base64>","c":"0a1b2c3d"}
///
/// Каждая сессия начинается со случайного sid, а заголовок содержит случайный
/// nonce, поэтому QR-коды всегда разные — даже для одного и того же файла.
enum QrProtocol {
    static let version = 1
    static let chunkRawSize = 800
    static let maxFileSize: Int64 = 100 * 1024 * 1024

    static func newSessionId() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func crc32Value(_ data: Data) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        return data.withUnsafeBytes { buf -> UInt32 in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return zlib.crc32(0, base, uInt(data.count))
        }
    }

    static func crcHex(_ value: UInt32) -> String {
        String(format: "%08x", value)
    }

    static func buildHeader(
        sid: String,
        name: String,
        mime: String,
        size: Int64,
        sha: String,
        total: Int,
        chunkRaw: Int = chunkRawSize,
        nonce: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    ) -> String {
        let object: [String: Any] = [
            "v": version, "t": "h", "sid": sid, "name": name, "mime": mime,
            "size": size, "sha": sha, "total": total, "cs": chunkRaw, "nonce": nonce
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    static func buildData(sid: String, index: Int, raw: Data, crc: UInt32) -> String {
        let object: [String: Any] = [
            "v": version, "t": "d", "sid": sid, "i": index,
            "d": raw.base64EncodedString(), "c": crcHex(crc)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    static func chunkCount(for size: Int64, chunkRaw: Int = chunkRawSize) -> Int {
        Int((size + Int64(chunkRaw) - 1) / Int64(chunkRaw))
    }
}

struct ReceivedHeader {
    let sid: String
    let name: String
    let mime: String
    let size: Int64
    let sha: String
    let total: Int
    let chunkRaw: Int
}

struct ReceivedChunk {
    let sid: String
    let index: Int
    let bytes: Data
    let crc: UInt32
}

func parseHeader(_ json: String) -> ReceivedHeader? {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (object["v"] as? Int) == QrProtocol.version,
          (object["t"] as? String) == "h",
          let sid = object["sid"] as? String,
          let name = object["name"] as? String,
          let size = object["size"] as? Int64,
          let sha = object["sha"] as? String,
          let total = object["total"] as? Int else { return nil }
    let mime = object["mime"] as? String ?? "application/octet-stream"
    let chunkRaw = object["cs"] as? Int ?? QrProtocol.chunkRawSize
    return ReceivedHeader(
        sid: sid, name: name, mime: mime, size: size,
        sha: sha, total: total, chunkRaw: chunkRaw
    )
}

func parseChunk(_ json: String) -> ReceivedChunk? {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (object["v"] as? Int) == QrProtocol.version,
          (object["t"] as? String) == "d",
          let sid = object["sid"] as? String,
          let index = object["i"] as? Int,
          let b64 = object["d"] as? String,
          let bytes = Data(base64Encoded: b64) else { return nil }
    let crc = UInt32((object["c"] as? String) ?? "0", radix: 16) ?? 0
    return ReceivedChunk(sid: sid, index: index, bytes: bytes, crc: crc)
}