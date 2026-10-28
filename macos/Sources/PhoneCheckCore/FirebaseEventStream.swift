import Foundation

/// Bounded SSE parser. Read bytes rather than a Unicode line iterator: SSE uses ASCII
/// line endings and its blank lines delimit events. Chunk boundaries are irrelevant.
public struct FirebaseEventStream {
    public enum Event { case value(String?) }
    private var line = Data()
    private var event = ""
    private var data = ""
    public init() {}
    public mutating func append(_ byte: UInt8) throws -> Event? {
        guard byte == 10 else {
            guard line.count < Wire.maxFrame * 2 + 1024 else { throw FirebaseRESTError.stream }
            line.append(byte); return nil
        }
        if line.last == 13 { line.removeLast() }
        guard let text = String(data: line, encoding: .utf8) else { throw FirebaseRESTError.stream }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { event = ""; data = "" }
            switch event {
            case "put":
                guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                      object["path"] as? String == "/" else { throw FirebaseRESTError.stream }
                let value = object["data"]
                guard value is String || value is NSNull else { throw FirebaseRESTError.stream }
                return .value(value as? String)
            case "keep-alive", "": return nil
            default: throw FirebaseRESTError.stream
            }
        }
        if text.hasPrefix("event:") {
            event = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if text.hasPrefix("data:") {
            guard data.utf8.count + text.utf8.count <= Wire.maxFrame * 2 + 1024 else { throw FirebaseRESTError.stream }
            data += String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces) + "\n"
        }
        return nil
    }
}
