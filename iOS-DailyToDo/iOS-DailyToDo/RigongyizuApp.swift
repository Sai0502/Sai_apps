import SwiftUI
import WidgetKit

@main
struct RigongyizuApp: App {
    @StateObject private var store = TaskStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .onAppear {
                    // 启动即请求通知权限（设置里才会出现「通知」项）
                    ReminderScheduler.requestPermission()
                    // 为存量未完成任务补调度提醒（编辑/新增时已各自调度）
                    for task in store.tasks where !task.done {
                        ReminderScheduler.schedule(task)
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // 回到前台重读磁盘：同步小组件里的勾选/删除
                store.reload()
            }
        }
    }
}
