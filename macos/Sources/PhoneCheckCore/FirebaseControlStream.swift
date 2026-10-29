import Foundation

/// Small, bounded control-state stream, separate from the encrypted notification mailboxes.
public struct FirebaseControlStream {
    private var line = Data()
    private var event = ""
    private var data = ""
    public private(set) var value: [String: Any] = [:]
    public init() {}
    public mutating func append(_ byte: UInt8) throws -> Bool {
        if byte != 10 {
            guard line.count < 16_384 else { throw FirebaseRESTError.stream }
            line.append(byte); return false
        }
        if line.last == 13 { line.removeLast() }
        guard let text = String(data: line, encoding: .utf8) else { throw FirebaseRESTError.stream }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { event = ""; data = "" }
            if event == "" || event == "keep-alive" { return false }
            guard event == "put" || event == "patch",
                  let json = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  let path = json["path"] as? String, path.hasPrefix("/"), let update = json["data"] else {
                throw FirebaseRESTError.stream
            }
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count < 8 else { throw FirebaseRESTError.stream }
            if event == "patch" {
                guard let updates = update as? [String: Any], updates.count <= 32 else { throw FirebaseRESTError.stream }
                for (key, child) in updates {
                    value = try Self.assign(value, path: parts + key.split(separator: "/").map(String.init), value: child)
                }
            } else { value = try Self.assign(value, path: parts, value: update) }
            guard try JSONSerialization.data(withJSONObject: value).count <= 16_384 else { throw FirebaseRESTError.stream }
            return true
        }
        if text.hasPrefix("event:") { event = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        else if text.hasPrefix("data:") {
            guard data.utf8.count + text.utf8.count < 16_384 else { throw FirebaseRESTError.stream }
            data += String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces) + "\n"
        }
        return false
    }
    private static func assign(_ tree: [String: Any], path: [String], value: Any) throws -> [String: Any] {
        guard path.count < 8 else { throw FirebaseRESTError.stream }
        guard let key = path.first else {
            if value is NSNull { return [:] }
            guard let dictionary = value as? [String: Any] else { throw FirebaseRESTError.stream }
            return dictionary
        }
        var result = tree
        if path.count == 1 {
            if value is NSNull { result.removeValue(forKey: key) } else { result[key] = value }
        } else {
            result[key] = try assign(result[key] as? [String: Any] ?? [:], path: Array(path.dropFirst()), value: value)
        }
        return result
    }
}
