import SwiftUI

/// 休息开始时的强制全屏遮罩：覆盖所有 APP（含已全屏的），展示休息倒计时
struct FullscreenBreakView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Flow 风格青绿背景
            LinearGradient(colors: [Color(red: 0.15, green: 0.47, blue: 0.40),
                                    Color(red: 0.20, green: 0.62, blue: 0.53)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: appState.phase == .longBreak ? "moon.zzz" : "cup.and.saucer")
                    .font(.system(size: 56))
                    .foregroundColor(.white.opacity(0.9))

                Text(appState.phase == .longBreak ? "长休息时间" : "休息时间")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.white)

                Text(formattedTime(appState.remainingSeconds))
                    .font(.system(size: 120, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)

                Text("站起来活动一下，喝口水")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))

                Button {
                    appState.skip()
                } label: {
                    Text("结束休息")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.15, green: 0.47, blue: 0.40))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            // ESC 键退出休息遮罩
            appState.skip()
        }
    }
}
