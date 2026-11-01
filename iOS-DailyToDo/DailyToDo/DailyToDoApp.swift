import SwiftUI
import WidgetKit

@main
struct DailyToDoApp: App {
    @StateObject private var store = TaskStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onAppear {
                    // 启动即请求通知权限（设置里才会出现「通知」项）
                    ReminderScheduler.requestPermission()
                    // 全量重排提醒：顺带收敛小组件侧做的勾选/取消
                    ReminderScheduler.resync(store.tasks)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // 回到前台重读磁盘：同步小组件里的勾选
                store.reload()
                // 顺手让小组件按磁盘现状重画一次：万一组件进程里那次刷新被系统吞掉，
                // 打开 App 也能把删除线/消失补上
                WidgetCenter.shared.reloadAllTimelines()
                // 小组件进程改不了通知中心，这里统一重排
                ReminderScheduler.resync(store.tasks)
            }
        }
    }
}
