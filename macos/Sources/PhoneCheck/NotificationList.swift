import SwiftUI
import PhoneCheckCore

/// Keep explicit Android groups together without hiding ungrouped notifications.
struct NotificationList: View {
    let notices: [Notice]
    @ObservedObject var commands: NotificationCommandController
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(sections) { section in
                if section.children.isEmpty {
                    RichNoticeRow(notice: section.notice, commands: commands)
                } else {
                    DisclosureGroup {
                        RichNoticeRow(notice: section.notice, commands: commands)
                        ForEach(section.children) { child in
                            RichNoticeRow(notice: child, commands: commands)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.stack").foregroundStyle(.secondary)
                            Text(section.notice.title.isEmpty ? section.notice.app : section.notice.title)
                                .font(.body.weight(.medium))
                            Spacer()
                            Text("\(section.children.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
        }
    }
    private struct Section: Identifiable {
        let notice: Notice
        let children: [Notice]
        var id: String { notice.key }
    }
    private var sections: [Section] {
        var summaries: [String: Notice] = [:]
        var children: [String: [Notice]] = [:]
        for notice in notices {
            guard let group = notice.groupKey else { continue }
            if notice.groupSummary == true {
                if summaries[group] == nil { summaries[group] = notice }
            } else { children[group, default: []].append(notice) }
        }
        var seen: Set<String> = []
        var result: [Section] = []
        for notice in notices {
            if let group = notice.groupKey, let summary = summaries[group], let grouped = children[group], !grouped.isEmpty,
               notice.groupSummary != true || notice.key == summary.key {
                if seen.insert(group).inserted { result.append(Section(notice: summary, children: grouped)) }
            } else { result.append(Section(notice: notice, children: [])) }
        }
        return result
    }
}
