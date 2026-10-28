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

    public static func sections(_ notices: [Notice]) -> [NotificationSection] {
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
            // A summary and one child still form a group. A lone child or
            // summary remains a normal notification with its original actions.
            if children.count > 1 || (summary != nil && !children.isEmpty) {
                return NotificationSection(id: id.stableID, notice: children[0], summary: summary, children: children)
            }
            return NotificationSection(id: "notice:\(notice.key)", notice: notice, summary: nil, children: [])
        }
    }
}
