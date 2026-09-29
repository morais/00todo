import SwiftUI

struct StartScheduleFields: View {
    @Binding var hasStart: Bool
    @Binding var start: Date
    @Binding var hasStartTime: Bool
    @Binding var startTime: Date

    var body: some View {
        Toggle("Start date", isOn: $hasStart)
        if hasStart {
            DatePicker("Available from", selection: $start, displayedComponents: .date)
            Toggle("Start time", isOn: $hasStartTime)
            if hasStartTime {
                DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
            }
        }
    }
}
