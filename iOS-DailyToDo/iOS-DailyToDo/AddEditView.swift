import SwiftUI

/// 新增/编辑任务页
/// 日期开关：开 -> 内联月历选日；时间开关：开 -> 小时/分钟双滚轮（即提醒时间）
/// 只选日期无时间 = 不提醒；未选日期直接开时间 = 日期自动今天
struct AddEditView: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem?   // nil = 新增

    @State private var title = ""
    @State private var dateOn = false
    @State private var timeOn = false
    @State private var day: Date = Date()
    @State private var hour = Calendar.current.component(.hour, from: Date())
    @State private var minute = Calendar.current.component(.minute, from: Date())
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        titleField
                        dateRow
                        if dateOn { inlineCalendar }
                        timeRow
                        if timeOn { timePickers }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .background(
                    // 点空白收键盘：挂在底层，不拦截 DatePicker/TextField 的点击
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { hideKeyboard() }
                )

                Divider().background(Color(red: 0.15, green: 0.15, blue: 0.18))

                HStack(spacing: 12) {
                    Button(action: dismiss.callAsFunction) {
                        Text("取消")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color(red: 0.14, green: 0.14, blue: 0.17))
                            .cornerRadius(12)
                    }
                    Button(action: save) {
                        Text(task == nil ? "添加" : "保存")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                loadTask()
                // 新增和编辑都自动聚焦任务内容栏，直接弹键盘
                titleFocused = true
            }
        }
    }

    // MARK: - 控件

    private var titleField: some View {
        TextField("任务内容", text: $title, axis: .vertical)
            .font(.system(size: 17))
            .foregroundColor(.white)
            .lineLimit(1...6)
            .focused($titleFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    private var dateRow: some View {
        HStack {
            Text("日期")
                .font(.system(size: 16))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $dateOn)
                .labelsHidden()
                .tint(.orange)
                .onChange(of: dateOn) { _, on in
                    if on && !loaded { day = Date() }
                    hideKeyboard()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var inlineCalendar: some View {
        DatePicker("", selection: $day, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .colorScheme(.dark)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private var timeRow: some View {
        HStack {
            Text("时间")
                .font(.system(size: 16))
                .foregroundColor(.white)
            Text(timeOn ? "\(String(format: "%02d:%02d", hour, minute)) 提醒" : "")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Spacer()
            Toggle("", isOn: $timeOn)
                .labelsHidden()
                .tint(.orange)
                .onChange(of: timeOn) { _, on in
                    if on && !dateOn {
                        // 未选日期直接开时间：日期自动设为今天
                        dateOn = true
                        day = Date()
                    }
                    hideKeyboard()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var timePickers: some View {
        HStack(spacing: 0) {
            Picker("时", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Text(":")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            Picker("分", selection: $minute) {
                ForEach(0..<60, id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 150)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - 逻辑

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadTask() {
        if let t = task {
            title = t.title
            if let d = t.day {
                dateOn = true
                if let base = fmt.date(from: d) { day = base }
            }
            if t.hasTime, let h = t.hour, let m = t.minute {
                timeOn = true
                hour = h
                minute = m
            }
        } else {
            day = Date()
        }
        loaded = true
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        let item = TaskItem(
            id: task?.id ?? UUID(),
            title: t,
            day: dateOn ? fmt.string(from: day) : nil,
            hour: timeOn ? hour : nil,
            minute: timeOn ? minute : nil,
            done: task?.done ?? false,
            createdAt: task?.createdAt ?? Date()
        )
        if task == nil {
            store.add(item)
        } else {
            store.update(item)
        }
        dismiss()
    }
}
