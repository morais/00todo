import SwiftUI

struct StartScheduleFields: View {
    @Binding var hasStart: Bool
    @Binding var start: Date
    @Binding var hasStartTime: Bool
    @Binding var startTime: Date

    var body: some View {
        Toggle("Start date", isOn: $hasStart)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(TodoDates.startShortcuts(), id: \.title) { shortcut in
                    let isSelected = hasStart && TodoDates.string(from: start) == TodoDates.string(from: shortcut.date)
                    Button(shortcut.title) {
                        start = shortcut.date
                        hasStart = true
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(isSelected ? .accentColor : .secondary)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        if hasStart {
            DatePicker("Available from", selection: $start, displayedComponents: .date)
            Toggle("Start time", isOn: $hasStartTime)
            if hasStartTime {
                DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
            }
        }
    }
}
