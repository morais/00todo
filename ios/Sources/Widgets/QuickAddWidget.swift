import AppIntents
import SwiftUI
import WidgetKit

struct AvailableWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "00Todo Available"
    static var description = IntentDescription("Show available tasks and projects.")

    @Parameter(title: "Expand projects", default: true)
    var expandProjects: Bool
}

private struct AvailableEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
}

private struct AvailableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AvailableEntry {
        AvailableEntry(date: .now, items: [])
    }

    func snapshot(for configuration: AvailableWidgetConfiguration, in context: Context) async -> AvailableEntry {
        entry(at: .now, expandProjects: configuration.expandProjects)
    }

    func timeline(for configuration: AvailableWidgetConfiguration, in context: Context) async -> Timeline<AvailableEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        let changes = snapshot?.upcomingStartDates(after: now) ?? []
        let dates = [now] + changes.filter { $0 < now.addingTimeInterval(30 * 24 * 60 * 60) }
        let entries = dates.map { date in entry(at: date, expandProjects: configuration.expandProjects, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 60 * 60)))
    }

    private func entry(at date: Date, expandProjects: Bool, snapshot: WidgetSnapshot? = nil) -> AvailableEntry {
        AvailableEntry(date: date, items: (snapshot ?? WidgetSnapshotStore.load())?.availableItems(at: date, expandProjects: expandProjects) ?? [])
    }
}

private struct AvailableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AvailableEntry

    private let voiceURL = URL(string: "\(AppBrand.urlScheme)://quick-add/voice")!
    private let textURL = URL(string: "\(AppBrand.urlScheme)://quick-add/text")!
    private let homeURL = URL(string: "\(AppBrand.urlScheme)://open/home")!

    private var rowLimit: Int {
        switch family {
        case .systemMedium: 3
        case .systemLarge: 7
        case .systemExtraLarge: 12
        default: 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 10) {
            HStack {
                Label("\(AppBrand.name)", systemImage: "checkmark.square.fill")
                    .font(family == .systemSmall ? .subheadline.bold() : .headline.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text("\(entry.items.count) available")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            if family == .systemSmall {
                Spacer(minLength: 0)
                Text(entry.items.count, format: .number)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(entry.items.count) available items")
                Spacer(minLength: 0)
            } else if entry.items.isEmpty {
                Spacer(minLength: 0)
                Label("All clear", systemImage: "checkmark.circle")
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.items.prefix(rowLimit)) { item in
                        if let destination = WidgetDestination(item: item) {
                            Link(destination: destination.url) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: item.isProject ? "folder" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 0.42, green: 0.76, blue: 1))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .lineLimit(1)
                                            .font(.subheadline)
                                        if family != .systemMedium, let projectName = item.projectName {
                                            Text(projectName).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Open \(item.isProject ? "project" : "task") \(item.title)")
                        }
                    }
                    if entry.items.count > rowLimit {
                        Text("+ \(entry.items.count - rowLimit) more")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Link(destination: voiceURL) {
                    Image(systemName: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Speak to \(AppBrand.name)")
                Link(destination: textURL) {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Quick Add")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, family == .systemSmall ? 6 : 8)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(family == .systemSmall ? 12 : 14)
        .containerBackground(Color(red: 0.07, green: 0.17, blue: 0.31), for: .widget)
        .widgetURL(family == .systemSmall ? textURL : homeURL)
    }
}

private struct AvailableTodoWidget: Widget {
    let kind = WidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AvailableWidgetConfiguration.self, provider: AvailableProvider()) { entry in
            AvailableWidgetView(entry: entry)
        }
        .configurationDisplayName("\(AppBrand.name) Available")
        .description("See available items. Choose whether to expand projects in Edit Widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main struct ZeroZeroTodoWidgetBundle: WidgetBundle {
    var body: some Widget { AvailableTodoWidget() }
}
