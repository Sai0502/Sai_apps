import SwiftUI
import SwiftData
import UIKit

/// 主界面：单页时间线，每天一张卡片（日期行 + 项目），最新一天在最上方。
/// 项目通过右上角加号新增（弹窗填项目名 + 每行组数 1-5，第一行即按组数生成方形勾选框）；
/// 点击勾选框打卡；长按任意行复制下一行（新行按该项目组数、勾选全空）；
/// 第 1 行不可删、第 2 行起左滑出现删除按钮点击删除；
/// 单击项目标题改名、左滑出现删除按钮点击删除；
/// 跨天复制全部项目与行（勾选全空）：隔 ≥1 天没打开时不逐天补卡，
/// 在「今天」卡片正下方插入一条红条「N 天没打开过 APP」（N = 中间缺的天数，不含今天）；
/// 今天之外的历史卡片置灰不可改。
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ProjectItem.createdAt) private var projects: [ProjectItem]
    @Query(sort: \GapItem.createdAt) private var gapItems: [GapItem]
    @Query(sort: \CheckItem.createdAt) private var legacyItems: [CheckItem]

    @State private var showEditSheet = false
    @State private var editingProject: ProjectItem?
    @State private var editText = ""
    /// 新增项目时填写的每行组数（1-5）；留空时保存按 5 处理
    @State private var editBoxCount = ""

    /// 保存失败时的提示文案（不再用 try? 把错误吞掉）
    @State private var saveErrorText: String?

    /// 任意位置点击时自增，驱动所有行的左滑删除条收起（点击屏幕任何位置恢复原状）
    @State private var collapseTick = 0

    /// 模拟"新的一天"的日期偏移：0 = 真实今天；每点一次 +1。
    /// 只用它计算"今天"基准，不改动任何真实数据，可反复点击。
    /// 注意：测试按钮已从界面上隐藏，如需恢复测试入口可把函数接回 toolbar。
    @State private var simulateOffset: Int = 0

    /// 当前界面的"今天"（真实今天 + 模拟偏移）
    private var simulatedToday: Date {
        calendar.date(byAdding: .day, value: simulateOffset, to: calendar.startOfDay(for: Date()))
            ?? calendar.startOfDay(for: Date())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private var calendar: Calendar { Calendar.current }

    private struct DayBlock: Identifiable {
        let day: Date
        let projects: [ProjectItem]
        var id: Date { day }
    }

    /// 时间线里的一行：要么是一天的卡片，要么是一条"多天没打开"提示
    private enum TimelineItem: Identifiable {
        case day(DayBlock)
        case gap(GapItem)

        var id: String {
            switch self {
            case .day(let block):
                return "day-\(block.day.timeIntervalSince1970)"
            case .gap(let gap):
                return "gap-\(gap.createdAt.timeIntervalSince1970)"
            }
        }

        /// 排序用：卡片取当天零点，提示条取它所属那天的零点
        var sortDate: Date {
            switch self {
            case .day(let block):
                return block.day
            case .gap(let gap):
                return Calendar.current.startOfDay(for: gap.endDay)
            }
        }

        var isDayCard: Bool {
            if case .day = self { return true }
            return false
        }
    }

    /// 按项目归属日期分组（当天零点），从新到旧排序；同天内按手动排序 sortIndex
    private var dayBlocks: [DayBlock] {
        let groups = Dictionary(grouping: projects) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { DayBlock(day: $0.key, projects: $0.value.sorted {
                ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt)
            }) }
            .sorted { $0.day > $1.day }
    }

    /// 卡片 + 提示条混排的时间线：新到旧；同一天内卡片在前、提示条紧随其后
    private var timeline: [TimelineItem] {
        var items = dayBlocks.map { TimelineItem.day($0) }
        items += gapItems.map { TimelineItem.gap($0) }
        return items.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            return lhs.isDayCard && !rhs.isDayCard
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty && gapItems.isEmpty {
                    emptyState
                } else {
                    dayList
                }
            }
            .navigationTitle("细狗翻身仗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addProject) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .onAppear {
                migrateLegacyDataIfNeeded()
                ensureTodayItems()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    ensureTodayItems()
                }
            }
            .overlay {
                if showEditSheet {
                    EditProjectOverlay(
                        editing: editingProject,
                        name: $editText,
                        boxCount: $editBoxCount,
                        onCancel: { showEditSheet = false },
                        onSave: saveProject
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(9)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showEditSheet)
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { saveErrorText != nil },
                    set: { if !$0 { saveErrorText = nil } }
                )
            ) {
                Button("知道了", role: .cancel) { saveErrorText = nil }
            } message: {
                Text(saveErrorText ?? "")
            }
        }
    }

    private var dayList: some View {
        List {
            ForEach(timeline) { item in
                switch item {
                case .day(let block):
                    dayCard(for: block, isToday: calendar.isDate(block.day, inSameDayAs: simulatedToday))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                case .gap(let gap):
                    gapBanner(missingDays: gap.missingDays)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollContentBackground(.hidden)
        // 点击列表任意位置：所有行收起左滑删除条
        .simultaneousGesture(
            TapGesture().onEnded { collapseTick += 1 }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.secondary)
            Text("还没有项目")
                .font(.headline)
            Text("点右上角 + 添加第一个项目")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
    }

    /// 一天 = 一张白色圆角卡片：顶部日期行 + 项目列表；历史天整体置灰
    private func dayCard(for block: DayBlock, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader(for: block.day)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(block.projects) { project in
                ProjectRowView(
                    project: project,
                    editable: isToday,
                    collapseTick: collapseTick,
                    onToggleBox: { toggleBox($0, at: $1) },
                    onEdit: {
                        editingProject = project
                        editText = project.name
                        editBoxCount = String(project.boxCount)
                        showEditSheet = true
                    },
                    onDuplicate: { duplicateSet($0) },
                    onDelete: { deleteProject(project) },
                    onDeleteSet: { deleteSet($0) }
                )
                .padding(.vertical, 3)
            }

            // 卡片底部留白
            Spacer()
                .frame(height: 8)
                .padding(.bottom, 2)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            // 历史天：黑色半透明蒙版盖住整卡（含隐藏的删除条），内容隐约可见且不可操作
            if !isToday {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.45))
            }
        }
        .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func dayHeader(for day: Date) -> some View {
        HStack(spacing: 8) {
            Text(Self.dayFormatter.string(from: day))
                .font(.system(size: 16, weight: .bold))
            if calendar.isDate(day, inSameDayAs: simulatedToday) {
                Text("今天")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    /// 「N 天没打开过 APP」提示条：红底白字、文字居中。
    /// 断档 ≥1 天时出现，代替逐天补出来的灰卡
    private func gapBanner(missingDays: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text("\(missingDays) 天没打开过 APP")
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// 切换某行第 boxIndex 个勾选框（带动画）。
    /// 数组元素级修改需显式写回数组，SwiftData 才会感知变化并刷新 UI
    private func toggleBox(_ set: SetItem, at boxIndex: Int) {
        guard set.boxes.indices.contains(boxIndex) else { return }
        var newBoxes = set.boxes
        withAnimation(.easeInOut(duration: 0.15)) {
            newBoxes[boxIndex].toggle()
            set.boxes = newBoxes
        }
        persist()
    }

    /// 长按复制行：在当前项目末尾生成序号 +1 的新行，
    /// 勾选框数量 = 所属项目的 boxCount，全部为空
    private func duplicateSet(_ set: SetItem) {
        guard let project = set.project else { return }
        let nextIndex = (project.sets.map(\.index).max() ?? 0) + 1
        let copy = SetItem(index: nextIndex, boxes: Array(repeating: false, count: max(1, project.boxCount)), project: project, createdAt: Date())
        context.insert(copy)
        project.sets.append(copy)
        persist()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 删除一行（带动画）：先从所属项目的关系数组移除，再删除对象，
    /// 避免删除动画期间视图仍访问已失效的 SetItem 而崩溃（SwiftData full future backing data）。
    /// 第 1 行在手势层已禁用左滑，不会走到这里。
    private func deleteSet(_ set: SetItem) {
        guard let project = set.project else { return }
        project.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        withAnimation(.easeInOut(duration: 0.3)) {
            context.delete(set)
        }
        persist()
    }

    /// 删除一个项目（级联删除其下所有行）：先给行列表拍快照并清空关系，
    /// 再逐个删除行、最后删项目本体。避免"边遍历边删"和"动画渲染访问已失效对象"
    /// 两类崩溃（SwiftData full future backing data）
    private func deleteProject(_ project: ProjectItem) {
        let sets = Array(project.sets)
        project.sets = []
        for set in sets {
            context.delete(set)
        }
        context.delete(project)
        persist()
    }

    /// 统一保存：失败时把错误显示出来，避免 `try?` 静默吞掉、数据悄悄丢失
    private func persist() {
        do {
            try context.save()
        } catch {
            saveErrorText = error.localizedDescription
        }
    }

    /// 模拟按钮（测试用，UI 已隐藏）：仅把"今天"基准向后推一天（不动任何真实数据），
    /// 随后自动生成新的"今天"（复制最近一天的项目与行、勾选重置）。可反复点击，不会重复。
    private func simulateNewDay() {
        simulateOffset += 1
        ensureTodayItems()
    }

    /// 右上角 + ：新增项目（弹窗填项目名 + 每行组数，排到当天最后）
    private func addProject() {
        editingProject = nil
        editText = ""
        editBoxCount = ""
        showEditSheet = true
    }

    private func saveProject() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 每行组数：解析 1-5 并钳制；非法输入时——改名保持原组数，新增回退 5
        let parsed = Int(editBoxCount.trimmingCharacters(in: .whitespacesAndNewlines))
        let boxCount: Int
        if let p = parsed {
            boxCount = min(max(p, 1), 5)
        } else if let project = editingProject {
            boxCount = project.boxCount
        } else {
            boxCount = 5
        }
        if let project = editingProject {
            if trimmed.isEmpty {
                deleteProject(project)
            } else {
                project.name = trimmed
                // 组数变更：更新项目组数，并把所有已有行统一到新框数
                // （变多则补未勾选框，变少则截断多余框）
                if project.boxCount != boxCount {
                    project.boxCount = boxCount
                    resizeAllRows(to: boxCount, in: project)
                }
            }
        } else if !trimmed.isEmpty {
            let todayStart = calendar.startOfDay(for: simulatedToday)
            let maxSort = projects
                .filter { calendar.isDate(calendar.startOfDay(for: $0.date), inSameDayAs: todayStart) }
                .map(\.sortIndex)
                .max() ?? -1
            let project = ProjectItem(name: trimmed, date: simulatedToday, sortIndex: maxSort + 1, boxCount: boxCount)
            context.insert(project)
            let first = SetItem(index: 1, boxes: Array(repeating: false, count: boxCount), project: project)
            context.insert(first)
            project.sets.append(first)
        }
        persist()
        editingProject = nil
        showEditSheet = false
    }

    /// 把项目所有行的勾选框数组统一调整到新组数：变多补未勾选框，变少截断多余框
    private func resizeAllRows(to boxCount: Int, in project: ProjectItem) {
        for set in project.sets {
            if set.boxes.count == boxCount { continue }
            if set.boxes.count < boxCount {
                set.boxes += Array(repeating: false, count: boxCount - set.boxes.count)
            } else {
                set.boxes = Array(set.boxes.prefix(boxCount))
            }
        }
    }

    /// 跨天时的补齐：
    /// - 隔 ≥1 天没打开（跨度 ≥2 天）：不补任何历史灰卡，只插入一条「N 天没打开过 APP」提示（N = 中间缺的天数，不含今天）
    /// 之后总是再生成"今天"的卡片（勾选全空、可编辑）
    private func ensureTodayItems() {
        let today = calendar.startOfDay(for: simulatedToday)
        guard let latestDay = projects.map({ calendar.startOfDay(for: $0.date) }).max(),
              latestDay < today else { return }

        let source = projects
            .filter { calendar.isDate(calendar.startOfDay(for: $0.date), inSameDayAs: latestDay) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }

        let span = calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0
        let missingDays = max(0, span - 1)

        // 统一规则：隔 ≥1 天没打开（跨度 ≥2 天）一律插红条，不再补任何历史灰卡
        if missingDays >= 1 {
            let gap = GapItem(missingDays: missingDays, endDay: today)
            context.insert(gap)
        }

        insertDay(copying: source, on: today)
        persist()
    }

    /// 按 source 的项目结构，在指定日期生成一整套"项目 + 行"，勾选框全部为空
    private func insertDay(copying source: [ProjectItem], on day: Date) {
        for project in source {
            let copy = ProjectItem(name: project.name, date: day, createdAt: Date(), sortIndex: project.sortIndex, boxCount: project.boxCount)
            context.insert(copy)
            for set in project.sets.sorted(by: { $0.index < $1.index }) {
                let setCopy = SetItem(index: set.index, boxes: Array(repeating: false, count: max(1, project.boxCount)), project: copy, createdAt: Date())
                context.insert(setCopy)
                copy.sets.append(setCopy)
            }
        }
    }

    /// 一次性迁移：把旧版 CheckItem（每条一个条目）合并成"项目 + 行"。
    /// 同一天内同名的条目合并为一个项目，按创建顺序编行、赋排序号；
    /// 旧勾选状态映射到第 1 个方框，其余 5 个方框为空。
    private func migrateLegacyDataIfNeeded() {
        guard !legacyItems.isEmpty else { return }

        let dayGroups = Dictionary(grouping: legacyItems) { calendar.startOfDay(for: $0.date) }
        for (day, dayItems) in dayGroups {
            let sorted = dayItems.sorted { $0.createdAt < $1.createdAt }
            var names: [String] = []
            var grouped: [String: [CheckItem]] = [:]
            for item in sorted {
                if grouped[item.text] == nil { names.append(item.text) }
                grouped[item.text, default: []].append(item)
            }
            for (i, name) in names.enumerated() {
                let project = ProjectItem(name: name, date: day, createdAt: Date(), sortIndex: i, boxCount: 5)
                context.insert(project)
                for (j, ci) in (grouped[name] ?? []).enumerated() {
                    var boxes = Array(repeating: false, count: 5)
                    if ci.isDone { boxes[0] = true }
                    let set = SetItem(index: j + 1, boxes: boxes, project: project, createdAt: Date())
                    context.insert(set)
                    project.sets.append(set)
                }
            }
        }
        for item in legacyItems { context.delete(item) }
        persist()
    }

    /// 项目行：项目标题（单击改名、左滑出现删除按钮点击删除）+ 行列表；
    /// 项目之间无横线，靠间距分隔；历史天不可编辑（置灰禁手势）
    private struct ProjectRowView: View {
        let project: ProjectItem
        let editable: Bool
        let collapseTick: Int
        let onToggleBox: (SetItem, Int) -> Void
        let onEdit: () -> Void
        let onDuplicate: (SetItem) -> Void
        let onDelete: () -> Void
        let onDeleteSet: (SetItem) -> Void

        @State private var titleDragOffset: CGFloat = 0

        private var sortedSets: [SetItem] {
            project.sets.sorted { $0.index < $1.index }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // 项目标题行：单击文字区改名、左滑出现删除按钮点击删除
                ZStack(alignment: .trailing) {
                    // 白色内容（底层，左滑整体左移、露出右侧删除条）
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(editable ? Color.primary : Color.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Color.white)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editable { onEdit() }
                    }
                    .offset(x: editable ? titleDragOffset : 0)

                    // 删除条（最上层：仅在左滑露出时显示；固定 90pt 宽整块可点，点击必删除）
                    if editable, titleDragOffset < -1 {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("删除")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 90)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onDelete()
                        }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if editable, value.translation.width < -15 {
                                titleDragOffset = min(0, max(value.translation.width, -90))
                            }
                        }
                        .onEnded { value in
                            if editable {
                                if value.translation.width < -60 {
                                    // 锁定露出删除按钮，点击按钮删除；右滑或点任意处回弹恢复
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        titleDragOffset = -90
                                    }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        titleDragOffset = 0
                                    }
                                }
                            } else {
                                titleDragOffset = 0
                            }
                        }
                )
                // 点击列表任意位置：收起标题删除条
                .onChange(of: collapseTick) { _, _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        titleDragOffset = 0
                    }
                }

                ForEach(sortedSets) { set in
                    RowView(
                        set: set,
                        boxCount: max(1, project.boxCount),
                        editable: editable,
                        isFirstRow: set.index == (sortedSets.map(\.index).min() ?? set.index),
                        collapseTick: collapseTick,
                        onToggleBox: { onToggleBox(set, $0) },
                        onDuplicate: { onDuplicate(set) },
                        onDelete: { onDeleteSet(set) }
                    )
                    .padding(.leading, 24)
                }
            }
        }
    }

    /// 打卡行：每行若干个方形勾选框横排（数量 = 所属项目的 boxCount）；点击方框勾选/取消；
    /// 长按行任意位置复制出下一行（新行按同样框数、全空）；
    /// 第 1 行左滑无效，第 2 行起左滑露出红色"删除"按钮、点击删除（无确认）；
    /// 点击屏幕任意位置恢复原状；历史天不可编辑（置灰禁手势）。
    private struct RowView: View {
        let set: SetItem
        let boxCount: Int
        let editable: Bool
        let isFirstRow: Bool
        let collapseTick: Int
        let onToggleBox: (Int) -> Void
        let onDuplicate: () -> Void
        let onDelete: () -> Void

        @State private var dragOffset: CGFloat = 0

        var body: some View {
            ZStack(alignment: .trailing) {
                // 勾选框（数量 = boxCount；底层，左滑整体左移、露出右侧删除条）
                HStack(spacing: 0) {
                    ForEach(0..<boxCount, id: \.self) { i in
                        let checked = set.boxes.indices.contains(i) && set.boxes[i]
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 26))
                            .foregroundStyle(checked ? Color.green : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if editable { onToggleBox(i) }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color.white)
                // 历史行强制不偏移（防止从"今天"变成历史后删除条残留）
                .offset(x: editable ? dragOffset : 0)

                // 删除条（最上层：非首行且左滑露出时显示；固定 90pt 宽整块可点，点击必删除）
                if editable, !isFirstRow, dragOffset < -1 {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text("删除")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 90)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDelete()
                    }
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) {
                if editable { onDuplicate() }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if editable, !isFirstRow, value.translation.width < -15 {
                            dragOffset = min(0, max(value.translation.width, -90))
                        }
                    }
                    .onEnded { value in
                        if editable {
                            if !isFirstRow, value.translation.width < -60 {
                                // 锁定露出删除按钮，点击按钮删除；右滑或点任意处回弹恢复
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    dragOffset = -90
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    dragOffset = 0
                                }
                            }
                        } else {
                            dragOffset = 0
                        }
                    }
            )
            // 点击列表任意位置：收起删除条
            .onChange(of: collapseTick) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    dragOffset = 0
                }
            }
        }
    }

    /// 新增/改名项目弹窗：黑色半透明遮罩 + 居中卡片。
    /// 新增与改名都显示：项目名称 + 每行组数（1-5，numberPad，改名时预填当前组数）。
    /// 名称留空时保存不可用；遮罩点击不关闭。
    private struct EditProjectOverlay: View {
        let editing: ProjectItem?
        @Binding var name: String
        @Binding var boxCount: String
        let onCancel: () -> Void
        let onSave: () -> Void

        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var isNew: Bool { editing == nil }

        var body: some View {
            ZStack {
                // 半透明黑色遮罩，覆盖全屏并拦截下层交互
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                // 卡片整体略偏上，键盘弹出后按钮仍可见
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 90)

                    VStack(spacing: 0) {
                        Text(isNew ? "新增项目" : "修改项目")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.top, 22)

                        fieldLabel("项目名称")
                        TextField("例：俯卧撑×10", text: $name)
                            .font(.system(size: 16))
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        fieldLabel("每行组数")
                        TextField("例：1-5", text: $boxCount)
                            .font(.system(size: 16))
                            .keyboardType(.numberPad)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        HStack(spacing: 12) {
                            Button(action: onCancel) {
                                Text("取消")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button(action: onSave) {
                                Text("保存")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(trimmedName.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(trimmedName.isEmpty)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                    .frame(width: 320)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color.black.opacity(0.2), radius: 16, y: 6)

                    Spacer()
                }
            }
        }

        private func fieldLabel(_ text: String) -> some View {
            HStack {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ProjectItem.self, SetItem.self, CheckItem.self, GapItem.self], inMemory: true)
}
