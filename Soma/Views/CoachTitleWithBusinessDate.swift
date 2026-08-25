import SwiftData
import SwiftUI

struct CoachTitleWithBusinessDate: View {
    let businessDate: Date
    let onChangeBusinessDate: (Date) -> Void
    @State var showsPicker = false
    @State var pendingDate = Date.now

    var body: some View {
        VStack(spacing: 1) {
            Text("Soma")
                .font(.headline.weight(.medium))
            Button {
                pendingDate = businessDate
                showsPicker = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    Text(businessDate.formatted(.dateTime.month().day()))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("本次对话的记录日期")
            .accessibilityValue(
                businessDate.formatted(date: .long, time: .omitted)
            )
            .accessibilityHint("更改后，本次对话新增的记录默认使用这个日期")
        }
        .sheet(isPresented: $showsPicker) {
            NavigationStack {
                DatePicker(
                    "Session 日期",
                    selection: $pendingDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("默认记录日期")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onChangeBusinessDate(pendingDate)
                            showsPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
