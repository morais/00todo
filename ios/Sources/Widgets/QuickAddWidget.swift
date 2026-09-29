import SwiftUI
import WidgetKit

private struct QuickAddEntry: TimelineEntry {
    let date: Date
}

private struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: .now)], policy: .never))
    }
}

private struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let voiceURL = URL(string: "zerozerotodo://quick-add/voice")!
    private let textURL = URL(string: "zerozerotodo://quick-add/text")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(Color(red: 0.34, green: 0.69, blue: 1))
                if family != .systemSmall {
                    Text("00Todo")
                        .font(.headline)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(.white)

            if family == .systemMedium {
                Text("A thought, a task, a shopping list.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Link(destination: voiceURL) {
                    Group {
                        if family == .systemSmall {
                            Image(systemName: "mic.fill")
                        } else {
                            Label("Speak", systemImage: "mic.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Speak to 00Todo")
                Link(destination: textURL) {
                    Group {
                        if family == .systemSmall {
                            Image(systemName: "square.and.pencil")
                        } else {
                            Label("Type", systemImage: "square.and.pencil")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Type a Quick Add")
            }
            .font((family == .systemSmall ? Font.title3 : Font.subheadline).weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .containerBackground(Color(red: 0.07, green: 0.17, blue: 0.31), for: .widget)
        .widgetURL(textURL)
    }
}

private struct QuickAddWidget: Widget {
    let kind = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("00Todo Quick Add")
        .description("Speak or type a task or shopping list.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct ZeroZeroTodoWidgetBundle: WidgetBundle {
    var body: some Widget { QuickAddWidget() }
}
