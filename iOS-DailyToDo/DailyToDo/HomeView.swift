import SwiftUI

/// 主界面：全部任务（按天分组），下拉新增，点击行编辑，左滑删除
struct HomeView: View {
    @EnvironmentObject var store: TaskStore

    @State private var pullOffset: CGFloat = 0
    @State private var topOffset: CGFloat = 0
    @State private var showAdd = false
    @State private var editingTask: TaskItem?

    private let pullLimit: CGFloat = 100

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    VStack(spacing: 0) {
                        orangePullArea
                        taskList
                    }
                }
                .coordinateSpace(name: "scroll")
                .background(
                    OffsetReader(topOffset: $topOffset)
                )
                .simultaneousGesture(pullGesture)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $editingTask) { t in
                AddEditView(task: t)
            }
            .fullScreenCover(isPresented: $showAdd) {
                AddEditView(task: nil)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 15))
            TextField("搜索任务", text: $store.searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// 下拉时显示的橘色新增区，跟手展开
    private var orangePullArea: some View {
        ZStack(alignment: .center) {
            if pullOffset > 0 {
                Color(red: 1.0, green: 0.5, blue: 0.15)
            }
            if pullOffset > 40 {
                Text("松开新增任务")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .frame(height: pullOffset)
        .clipped()
        .opacity(pullOffset > 0 ? 1 : 0)
    }

    @ViewBuilder
    private var taskList: some View {
        let groups = store.filtered.groupedByDay()
        if groups.isEmpty {
            VStack(spacing: 10) {
                Spacer().frame(height: 120)
                Text("暂无任务")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                Text("下拉屏幕添加新任务")
                    .font(.system(size: 13))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        } else {
            ForEach(groups) { group in
                groupHeader(group.title)
                ForEach(group.items) { task in
                    SwipeableTaskRow(task: task,
                                     onToggle: { store.toggleDone(task) },
                                     onEdit: { editingTask = task },
                                     onDelete: { withAnimation { store.delete(task) } })
                }
            }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    /// 下拉手势：仅在列表处于顶部时生效；横向为主的手势不触发（避免左滑删除误入新增）
    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { v in
                guard topOffset > -2 else { return }
                // 横向分量大于纵向分量 -> 是横滑（如左滑删除），不触发下拉
                if abs(v.translation.width) > abs(v.translation.height) * 1.1 {
                    pullOffset = 0
                    return
                }
                let h = max(0, v.translation.height)
                pullOffset = min(h, 140)
            }
            .onEnded { _ in
                if pullOffset >= pullLimit {
                    showAdd = true
                }
                withAnimation(.spring(duration: 0.22)) {
                    pullOffset = 0
                }
            }
    }
}

/// 任务行：左侧勾选框 + 内容，点击行进入编辑
struct TaskRow: View {
    let task: TaskItem
    var onToggle: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.done ? Color.orange : Color.gray.opacity(0.6),
                                      lineWidth: 1.6)
                        .frame(width: 22, height: 22)
                    if task.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "未命名任务" : task.title)
                    .font(.system(size: 16))
                    .foregroundColor(task.done ? Color.gray.opacity(0.6) : .white)
                    .strikethrough(task.done, color: .gray)
                    .lineLimit(3)
                if task.hasTime {
                    Text("提醒 \(task.timeText)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

/// 可左滑删除的任务行：左滑露出红色删除按钮；
/// 继续左滑把删除按钮拉离右缘（越过阈值）松手即直接删除；否则回弹/展开
struct SwipeableTaskRow: View {
    let task: TaskItem
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0

    private let deleteWidth: CGFloat = 72
    private let bgColor = Color(red: 0.05, green: 0.05, blue: 0.06)

    var body: some View {
        ZStack(alignment: .trailing) {
            // 底层删除区（右侧，滑动过程中露出）
            HStack(spacing: 10) {
                Spacer()
                Button(action: confirmDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 42)
                        .background(Color.red)
                        .cornerRadius(9)
                }
                .frame(width: deleteWidth, alignment: .trailing)
            }
            .padding(.trailing, 8)

            // 上层内容行
            TaskRow(task: task, onToggle: onToggle, onEdit: onEdit)
                .background(bgColor)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            // 只跟随水平位移；最多把删除区完全拉出再多 80pt
                            let next = min(0, max(v.translation.width, -deleteWidth - 80))
                            offset = next
                        }
                        .onEnded { _ in
                            if offset < -deleteWidth - 28 {
                                // 删除按钮被拉离右缘 -> 滑出删除
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = -UIScreen.main.bounds.width
                                }
                                onDelete()
                                offset = 0
                            } else {
                                // 未过阈值 -> 回弹
                                withAnimation(.spring(duration: 0.24)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .contentShape(Rectangle())
    }

    private func confirmDelete() {
        onDelete()
        offset = 0
    }
}

/// 读取滚动内容顶部位置，判断是否停在顶部
struct OffsetReader: View {
    @Binding var topOffset: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: OffsetKey.self,
                            value: geo.frame(in: .named("scroll")).minY)
                .onPreferenceChange(OffsetKey.self) { v in
                    topOffset = v
                }
        }
        .frame(height: 0)
    }
}

struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
