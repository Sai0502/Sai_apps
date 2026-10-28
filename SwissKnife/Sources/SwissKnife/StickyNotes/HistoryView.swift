import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: NoteStore
    var onRestore: (ArchivedNote) -> Void

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 按删除日期分组, 新的在前
    private var grouped: [(day: Date, notes: [ArchivedNote])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.archived) { cal.startOfDay(for: $0.deletedAt) }
        return dict.keys.sorted(by: >).map { day in
            (day, dict[day]!.sorted { $0.deletedAt > $1.deletedAt })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏: 删除所有历史
            HStack {
                Spacer()
                if !store.archived.isEmpty {
                    Button(role: .destructive) {
                        store.removeAllArchived()
                    } label: {
                        Label("清空全部历史", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Group {
                if store.archived.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                        Text("还没有历史便签")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("删除的便签会按日期归档到这里")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                ForEach(group.notes) { item in
                                    row(item)
                                }
                            } header: {
                                Text(Self.dayFormatter.string(from: group.day))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }

    @ViewBuilder
    private func row(_ item: ArchivedNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 主题色圆点
            Circle()
                .fill(Color(nsColor: item.theme.bar))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color(nsColor: item.theme.accent).opacity(0.4), lineWidth: 1))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("📝 文字便签")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Self.timeFormatter.string(from: item.deletedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                content(item)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    onRestore(item)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("恢复成便签")

                Button {
                    store.removeArchived(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("彻底删除")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func content(_ item: ArchivedNote) -> some View {
        // 首行图片缩略 + 文字预览 (待办行带勾选框图标, 图片 token 隐藏)
        VStack(alignment: .leading, spacing: 6) {
            if let thumb = firstImage(item), let image = ImageStore.shared.load(thumb.file) {
                let ratio = max(thumb.ratio, 0.01)
                let w: CGFloat = 160
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(width: w, height: min(w / ratio, 120))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    }
            }
            ForEach(Array(previewLines(item).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let (done, text) = todoPrefix(line) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundStyle(done
                                ? Color(nsColor: item.theme.accent).opacity(0.8)
                                : Color.secondary.opacity(0.6))
                        Text(text)
                            .font(.system(size: 13))
                            .strikethrough(done)
                            .foregroundStyle(done ? .secondary : .primary)
                    } else {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func firstImage(_ item: ArchivedNote) -> NoteImage? {
        let pattern = try? NSRegularExpression(pattern: #"!\[([0-9A-Fa-f-]{36})\]"#)
        let ns = item.text as NSString
        var uuid: String?
        pattern?.enumerateMatches(in: item.text,
                                  range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.numberOfRanges > 1 else { return }
            uuid = ns.substring(with: m.range(at: 1))
            stop.pointee = true
        }
        guard let uuid else { return nil }
        return item.images[uuid]
    }

    /// 去掉图片 token 后按行拆开 (最多 8 行), 待办行原样保留 "[ ] "/"[x] " 前缀
    private func previewLines(_ item: ArchivedNote) -> [String] {
        let cleaned = item.text.replacingOccurrences(
            of: #"!\[[0-9A-Fa-f-]{36}\]"#, with: "", options: .regularExpression)
        var lines = cleaned.components(separatedBy: "\n")
        while lines.count > 8 { lines.removeLast() }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 待办行: "[ ] xxx" / "[x] xxx" → (完成, 文字)
    private func todoPrefix(_ line: String) -> (Bool, String)? {
        if line.hasPrefix("[ ] ") { return (false, String(line.dropFirst(4))) }
        if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") {
            return (true, String(line.dropFirst(4)))
        }
        return nil
    }
}
