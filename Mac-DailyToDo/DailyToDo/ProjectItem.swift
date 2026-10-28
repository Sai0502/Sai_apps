import Foundation
import SwiftData

/// 项目：如“俯卧撑×10”，一个项目下挂若干行（SetItem）。
/// 项目通过右上角加号新增（新增时填写每行组数 boxCount，默认 5）；删除项目会级联删除其下所有行。
/// 该项目所有行（含长按复制出的新行）的勾选框数量都等于 boxCount。
/// sortIndex 决定同一天内的显示顺序；dayReason 记录该天未完成理由（挂在当天任一项目上）。
@Model
final class ProjectItem {
    var name: String
    var date: Date
    var createdAt: Date
    var sortIndex: Int = 0
    /// 每行勾选框数量（新增项目时填写，钳制在 1-5）
    var boxCount: Int = 5
    var dayReason: String?
    @Relationship(deleteRule: .cascade, inverse: \SetItem.project)
    var sets: [SetItem]

    init(name: String, date: Date = Date(), createdAt: Date = Date(), sortIndex: Int = 0, boxCount: Int = 5, dayReason: String? = nil) {
        self.name = name
        self.date = date
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.boxCount = boxCount
        self.dayReason = dayReason
        self.sets = []
    }
}

/// 行：属于某个项目，每行的勾选框数量 = 所属项目的 boxCount（boxes 逐个记录勾选状态）。
/// 新增项目自动带第 1 行；长按任意行可复制出下一行（新行勾选全空）；
/// 第 1 行不可删除，第 2 行起左滑出现删除按钮点击删除。
@Model
final class SetItem {
    var index: Int
    var boxes: [Bool]
    var project: ProjectItem?
    var createdAt: Date

    init(index: Int, boxes: [Bool] = [], project: ProjectItem? = nil, createdAt: Date = Date()) {
        self.index = index
        self.boxes = boxes
        self.project = project
        self.createdAt = createdAt
    }
}
