import Foundation

/// Presentation groups use Android's explicit group key, scoped to its app.
/// Keep input order (the feed is newest first), including groups without a summary.
public struct NotificationSection: Identifiable {
    public let id: String
    public let notice: Notice
    public let summary: Notice?
    public let children: [Notice]

    private struct GroupID: Hashable {
        let app: String
        let key: String
        var stableID: String { "group:\(app.utf8.count):\(app)\(key)" }
    }

    public static func count(_ notices: [Notice]) -> Int {
        sections(notices).reduce(0) { $0 + ($1.children.isEmpty ? 1 : $1.children.count) }
    }

    public static func sections(_ notices: [Notice]) -> [NotificationSection] {
        // Repeated transport updates share a stable Android key. Do not merge
        // distinct notifications merely because their text happens to match.
        var seenKeys: Set<String> = []
        let notices = notices.filter { seenKeys.insert($0.key).inserted }
        func group(_ notice: Notice) -> GroupID? {
            guard let key = notice.groupKey else { return nil }
            return GroupID(app: notice.packageName ?? notice.app, key: key)
        }
        let groups = Dictionary(grouping: notices.compactMap { notice in
            group(notice).map { ($0, notice) }
        }, by: { $0.0 })
        var seen: Set<GroupID> = []
        return notices.compactMap { notice in
            guard let id = group(notice), let members = groups[id]?.map({ $0.1 }) else {
                return NotificationSection(id: "notice:\(notice.key)", notice: notice, summary: nil, children: [])
            }
            guard seen.insert(id).inserted else { return nil }
            let summary = members.first { $0.groupSummary == true }
            let children = members.filter { $0.groupSummary != true }
            // Summaries are containers, so only actual children make a stack.
            if children.count > 1 {
                return NotificationSection(id: id.stableID, notice: children[0], summary: summary, children: children)
            }
            if let child = children.first {
                return NotificationSection(id: "notice:\(child.key)", notice: child, summary: summary, children: [])
            }
            return NotificationSection(id: "notice:\(notice.key)", notice: notice, summary: nil, children: [])
        }
    }
}
