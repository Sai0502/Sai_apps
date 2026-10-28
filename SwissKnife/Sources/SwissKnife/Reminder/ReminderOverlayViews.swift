import SwiftUI
import AppKit

// MARK: - 角落倒计时浮层（到点前 5→1 预警）

/// 共享的倒计时数值（由 ReminderModule 更新，视图观察）
@MainActor
final class CountdownOverlayModel: ObservableObject {
    static let shared = CountdownOverlayModel()
    @Published var seconds: Int = 5
    var onCancel: (() -> Void)?
}

/// 半透明圆圈 + 大号数字倒计时（纯数字，无文字，双击取消）
struct CountdownCircle: View {
    let seconds: Int
    var onCancel: (() -> Void)? = nil

    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 96, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .frame(width: 190, height: 190)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
            .shadow(radius: 14)
            .onTapGesture(count: 2) {
                onCancel?()
            }
            .help("双击取消本次提醒")
    }
}

/// 主屏右上角的圆形倒计时浮层（到点前 5 秒预警）
struct CountdownOverlayView: View {
    @EnvironmentObject var model: CountdownOverlayModel

    var body: some View {
        CountdownCircle(seconds: model.seconds, onCancel: model.onCancel)
    }
}

// MARK: - 全屏图片提醒（到点展示，右上角倒计时，双击圆圈跳过）

/// 全屏图片提醒视图：完整显示图片（黑边补背景），右上角半透明圆圈倒计时 10→1，
/// 双击圆圈即关闭全屏（跳过）；倒计时归零自动关闭。
/// 关闭只收起全屏，不停止应用内音频、不影响外部视频播放器。
struct ScheduledImageOverlayView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var remaining = 10
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)   // 完整显示，黑边补背景
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            CountdownCircle(seconds: remaining)
                .onTapGesture(count: 2) {        // 双击圆圈 = 跳过
                    onClose()
                }
                .help("双击跳过")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(28)
        }
        .onAppear { startCountdown() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            MainActor.assumeIsolated {
                if remaining > 1 {
                    remaining -= 1
                } else {
                    t.invalidate()
                    onClose()
                }
            }
        }
    }
}
