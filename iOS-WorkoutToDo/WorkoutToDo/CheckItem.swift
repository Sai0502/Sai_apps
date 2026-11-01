import Foundation
import SwiftData

/// 一条打卡记录：内容、是否完成、归属日期、创建顺序
@Model
final class CheckItem {
    var text: String
    var isDone: Bool
    var date: Date
    var createdAt: Date

    init(text: String, isDone: Bool = false, date: Date = Date(), createdAt: Date = Date()) {
        self.text = text
        self.isDone = isDone
        self.date = date
        self.createdAt = createdAt
    }
}
