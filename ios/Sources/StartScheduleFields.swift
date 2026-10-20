import SwiftUI

struct StartScheduleFields: View {
    @Binding var hasStart: Bool
    @Binding var start: Date
    @Binding var hasStartTime: Bool
    @Binding var startTime: Date

    var body: some View {
        Toggle("Start date", isOn: $hasStart)
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(TodoDates.startShortcuts(now: timeline.date), id: \.title) { shortcut in
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
                    ForEach(TodoDates.todayStartTimeShortcuts(now: timeline.date), id: \.time) { shortcut in
                        let isSelected = hasStart && hasStartTime
                            && TodoDates.string(from: start) == TodoDates.string(from: shortcut.date)
                            && TodoDates.timeString(from: startTime) == shortcut.time
                        Button("Today \(TodoDates.displayTime(shortcut.time))") {
                            // A chip may linger briefly while the periodic view updates.
                            guard shortcut.date > Date() else { return }
                            start = shortcut.date
                            startTime = shortcut.date
                            hasStart = true
                            hasStartTime = true
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(isSelected ? .accentColor : .secondary)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        if hasStart {
            DatePicker("Available from", selection: $start, displayedComponents: .date)
            Toggle("Start time", isOn: $hasStartTime)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(TodoDates.startTimeShortcuts, id: \.self) { time in
                        let isSelected = hasStartTime && TodoDates.timeString(from: startTime) == time
                        Button(TodoDates.displayTime(time)) {
                            startTime = TodoDates.timeDate(from: time)
                            hasStartTime = true
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(isSelected ? .accentColor : .secondary)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            if hasStartTime {
                DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
            }
        }
    }
}
