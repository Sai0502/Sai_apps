import AppKit
import Foundation

protocol OverlayControllerDelegate: AnyObject {
    func overlayControllerDidUpdate(_ controller: OverlayController)
    func overlayControllerDidRequestRatioEdit(_ controller: OverlayController)
}

final class OverlayController: NSObject, OverlayViewDelegate {
    weak var delegate: OverlayControllerDelegate?

    private let settingsStore = ZoneStore.shared
    private let logger = ZoneLogger.shared

    private var window: OverlayWindow?
    private var overlayView: OverlayView?
    private var hoverTimer: Timer?
    private var currentRatio: ParsedRatio?

    private enum InteractionState {
        case move(startMouse: NSPoint, startFrame: NSRect, visibleFrame: NSRect)
        case resize(handle: ResizeHandle, startMouse: NSPoint, startFrame: NSRect, visibleFrame: NSRect)
    }

    private var interactionState: InteractionState?

    func start() {
        startHoverTimer()
    }

    func stop() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideZone()
    }

    func showZone(using ratioText: String) throws {
        let ratio = try parseRatio(ratioText)
        guard let screen = screenForCurrentMouse() else {
            throw NSError(domain: "FitRecordZone", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到当前鼠标所在屏幕"])
        }

        currentRatio = ratio
        let visibleFrame = screen.visibleFrame
        let captureFrame = initialFrame(for: ratio, visibleFrame: visibleFrame)
        let frame = windowFrame(forCaptureFrame: captureFrame)

        let overlayWindow = window ?? OverlayWindow(frame: frame)
        overlayWindow.setFrame(frame, display: true)
        overlayWindow.orderFrontRegardless()

        let view: OverlayView
        if let existing = overlayView {
            view = existing
        } else {
            view = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.autoresizingMask = [.width, .height]
            view.delegate = self
            overlayWindow.contentView = view
            overlayView = view
        }

        view.frame = NSRect(origin: .zero, size: frame.size)
        view.strokeColor = settingsStore.current.strokeColor.nsColor()
        view.ratioText = ratio.text

        overlayWindow.ignoresMouseEvents = true
        window = overlayWindow

        settingsStore.update {
            $0.lastRatioText = ratio.text
            $0.lastFrameWidth = captureFrame.width
            $0.lastFrameHeight = captureFrame.height
        }

        logger.log("overlay_shown", details: [
            "ratio": ratio.text,
            "screen": screen.localizedName,
            "frame": captureFrame.debugDescription
        ])
        delegate?.overlayControllerDidUpdate(self)
    }

    func showUsingLastRatio() throws {
        try showZone(using: settingsStore.current.lastRatioText)
    }

    func hideZone() {
        window?.orderOut(nil)
        interactionState = nil
        logger.log("overlay_hidden")
        delegate?.overlayControllerDidUpdate(self)
    }

    func isVisible() -> Bool {
        window?.isVisible == true
    }

    func applyStrokeColor(_ color: NSColor) {
        settingsStore.update { $0.strokeColor = CodableColor(nsColor: color) }
        overlayView?.strokeColor = color
        logger.log("stroke_color_updated", details: [
            "rgba": rgbaString(for: color)
        ])
        delegate?.overlayControllerDidUpdate(self)
    }

    func currentSnapshot() -> OverlaySnapshot? {
        guard let ratio = currentRatio else {
            return OverlaySnapshot(
                visible: false,
                ratioText: settingsStore.current.lastRatioText,
                ratioWidth: 0,
                ratioHeight: 0,
                frame: nil,
                screenName: nil
            )
        }

        return OverlaySnapshot(
            visible: isVisible(),
            ratioText: ratio.text,
            ratioWidth: ratio.width,
            ratioHeight: ratio.height,
            frame: window.map { CodableRect(captureFrame(fromWindowFrame: $0.frame)) },
            screenName: window?.screen?.localizedName
        )
    }

    func currentMouseLocation() -> NSPoint {
        NSEvent.mouseLocation
    }

    func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelDidChange(_:)))
        panel.color = settingsStore.current.strokeColor.nsColor()
        panel.showsAlpha = true
        panel.orderFrontRegardless()
    }

    @objc private func colorPanelDidChange(_ sender: NSColorPanel) {
        applyStrokeColor(sender.color)
    }

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateMouseInteractivity()
        }
        RunLoop.main.add(hoverTimer!, forMode: .common)
    }

    private func updateMouseInteractivity() {
        guard let window, let overlayView, window.isVisible else { return }
        guard interactionState == nil else {
            window.ignoresMouseEvents = false
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let localPoint = window.convertPoint(fromScreen: mouseLocation)
        let shouldInteract = overlayView.isInteractive(at: localPoint)
        window.ignoresMouseEvents = !shouldInteract
    }

    private func parseRatio(_ rawText: String) throws -> ParsedRatio {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            throw NSError(domain: "FitRecordZone", code: 2, userInfo: [NSLocalizedDescriptionKey: "比例格式无效，请输入类似 16:9"])
        }

        return ParsedRatio(text: text, width: width, height: height)
    }

    private func screenForCurrentMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }

    private func initialFrame(for ratio: ParsedRatio, visibleFrame: NSRect) -> NSRect {
        let width: CGFloat
        let height: CGFloat

        if let storedWidth = settingsStore.current.lastFrameWidth,
           let storedHeight = settingsStore.current.lastFrameHeight,
           storedWidth > 0,
           storedHeight > 0 {
            let fitted = fittedSize(
                for: ratio,
                inside: NSSize(
                    width: min(CGFloat(storedWidth), visibleFrame.width),
                    height: min(CGFloat(storedHeight), visibleFrame.height)
                )
            )
            width = fitted.width
            height = fitted.height
        } else {
            let targetHeight = visibleFrame.height * 0.5
            let fitted = fittedSize(
                for: ratio,
                inside: NSSize(width: targetHeight * ratio.value, height: targetHeight)
            )
            width = min(fitted.width, visibleFrame.width)
            height = min(fitted.height, visibleFrame.height)
        }

        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )

        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    private func windowFrame(forCaptureFrame captureFrame: NSRect) -> NSRect {
        NSRect(
            x: captureFrame.origin.x - OverlayChromeMetrics.leftInset,
            y: captureFrame.origin.y - OverlayChromeMetrics.bottomInset,
            width: captureFrame.width + OverlayChromeMetrics.leftInset + OverlayChromeMetrics.rightInset,
            height: captureFrame.height + OverlayChromeMetrics.topInset + OverlayChromeMetrics.bottomInset
        )
    }

    private func captureFrame(fromWindowFrame windowFrame: NSRect) -> NSRect {
        NSRect(
            x: windowFrame.origin.x + OverlayChromeMetrics.leftInset,
            y: windowFrame.origin.y + OverlayChromeMetrics.bottomInset,
            width: windowFrame.width - OverlayChromeMetrics.leftInset - OverlayChromeMetrics.rightInset,
            height: max(windowFrame.height - OverlayChromeMetrics.topInset - OverlayChromeMetrics.bottomInset, 80)
        )
    }

    private func fittedSize(for ratio: ParsedRatio, inside container: NSSize) -> NSSize {
        let safeWidth = max(container.width, 80)
        let safeHeight = max(container.height, 80)
        let containerRatio = safeWidth / safeHeight

        if containerRatio > ratio.value {
            let height = safeHeight
            let width = height * ratio.value
            return NSSize(width: width, height: height)
        } else {
            let width = safeWidth
            let height = width / ratio.value
            return NSSize(width: width, height: height)
        }
    }

    private func saveCurrentFrame() {
        guard let frame = window.map({ captureFrame(fromWindowFrame: $0.frame) }) else { return }
        overlayView?.ratioText = currentRatio?.text ?? settingsStore.current.lastRatioText
        settingsStore.update {
            $0.lastFrameWidth = frame.width
            $0.lastFrameHeight = frame.height
            if let ratio = currentRatio {
                $0.lastRatioText = ratio.text
            }
        }
        delegate?.overlayControllerDidUpdate(self)
    }

    private func rgbaString(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "%.3f,%.3f,%.3f,%.3f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }

    func overlayViewDidRequestClose(_ view: OverlayView) {
        hideZone()
    }

    func overlayViewDidRequestRatioEdit(_ view: OverlayView) {
        delegate?.overlayControllerDidRequestRatioEdit(self)
    }

    func overlayView(_ view: OverlayView, didBeginInteraction zone: HitZone, mouseScreenPoint: NSPoint) {
        guard let window else { return }
        let visibleFrame = window.screen?.visibleFrame ?? window.frame
        let captureFrame = captureFrame(fromWindowFrame: window.frame)

        switch zone {
        case .move:
            interactionState = .move(startMouse: mouseScreenPoint, startFrame: captureFrame, visibleFrame: visibleFrame)
            logger.log("drag_move_begin", details: ["frame": captureFrame.debugDescription])
        case .resize(let handle):
            interactionState = .resize(handle: handle, startMouse: mouseScreenPoint, startFrame: captureFrame, visibleFrame: visibleFrame)
            logger.log("drag_resize_begin", details: [
                "handle": handle.rawValue,
                "mode": handle.mode.rawValue,
                "frame": captureFrame.debugDescription
            ])
        case .closeButton, .none:
            interactionState = nil
        }

        window.ignoresMouseEvents = false
    }

    func overlayView(_ view: OverlayView, didContinueInteraction mouseScreenPoint: NSPoint) {
        guard let window else { return }

        switch interactionState {
        case .move(let startMouse, let startFrame, let visibleFrame):
            let deltaX = mouseScreenPoint.x - startMouse.x
            let deltaY = mouseScreenPoint.y - startMouse.y
            var frame = startFrame.offsetBy(dx: deltaX, dy: deltaY)
            frame = clampedFrame(frame, inside: visibleFrame)
            window.setFrame(windowFrame(forCaptureFrame: frame), display: true)
        case .resize(let handle, let startMouse, let startFrame, let visibleFrame):
            let frame: NSRect
            switch handle.mode {
            case .fixedAspect:
                guard let ratio = currentRatio else { return }
                frame = resizeFrameFixed(
                    startFrame: startFrame,
                    startMouse: startMouse,
                    currentMouse: mouseScreenPoint,
                    visibleFrame: visibleFrame,
                    aspectRatio: ratio.value
                )
            case .freeform:
                frame = resizeFrameFreeform(
                    startFrame: startFrame,
                    startMouse: startMouse,
                    currentMouse: mouseScreenPoint,
                    visibleFrame: visibleFrame
                )
                currentRatio = ParsedRatio.from(size: frame.size)
                overlayView?.ratioText = currentRatio?.text ?? settingsStore.current.lastRatioText
            }
            window.setFrame(windowFrame(forCaptureFrame: frame), display: true)
        case .none:
            break
        }

        saveCurrentFrame()
    }

    func overlayViewDidEndInteraction(_ view: OverlayView) {
        interactionState = nil
        window?.ignoresMouseEvents = true
        saveCurrentFrame()
        logger.log("interaction_end", details: [
            "frame": window.map { captureFrame(fromWindowFrame: $0.frame).debugDescription } ?? ""
        ])
    }

    private func clampedFrame(_ frame: NSRect, inside visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.origin.x = min(max(result.origin.x, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }

    private func resizeFrameFixed(
        startFrame: NSRect,
        startMouse: NSPoint,
        currentMouse: NSPoint,
        visibleFrame: NSRect,
        aspectRatio: CGFloat
    ) -> NSRect {
        let minBase: CGFloat = 80
        let minWidth = max(minBase, minBase * aspectRatio)

        let deltaX = currentMouse.x - startMouse.x
        let deltaY = currentMouse.y - startMouse.y
        let widthFromX = startFrame.width + deltaX
        let widthFromY = (startFrame.height - deltaY) * aspectRatio

        var width = max(minWidth, min(widthFromX, widthFromY))
        let anchor = NSPoint(x: startFrame.minX, y: startFrame.maxY)
        let maxWidth = maxWidthAllowed(anchor: anchor, corner: .bottomRight, visibleFrame: visibleFrame, aspectRatio: aspectRatio)
        width = min(width, maxWidth)
        let height = width / aspectRatio

        return NSRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
    }

    private func maxWidthAllowed(anchor: NSPoint, corner: CornerHandle, visibleFrame: NSRect, aspectRatio: CGFloat) -> CGFloat {
        let horizontalLimit: CGFloat
        let verticalLimit: CGFloat

        switch corner {
        case .topLeft:
            horizontalLimit = anchor.x - visibleFrame.minX
            verticalLimit = visibleFrame.maxY - anchor.y
        case .topRight:
            horizontalLimit = visibleFrame.maxX - anchor.x
            verticalLimit = visibleFrame.maxY - anchor.y
        case .bottomLeft:
            horizontalLimit = anchor.x - visibleFrame.minX
            verticalLimit = anchor.y - visibleFrame.minY
        case .bottomRight:
            horizontalLimit = visibleFrame.maxX - anchor.x
            verticalLimit = anchor.y - visibleFrame.minY
        }

        return min(horizontalLimit, verticalLimit * aspectRatio)
    }

    private func resizeFrameFreeform(
        startFrame: NSRect,
        startMouse: NSPoint,
        currentMouse: NSPoint,
        visibleFrame: NSRect
    ) -> NSRect {
        let minSize: CGFloat = 80
        let deltaX = currentMouse.x - startMouse.x
        let deltaY = currentMouse.y - startMouse.y

        let maxX = startFrame.maxX
        let maxY = startFrame.maxY

        let width = max(minSize, startFrame.width - deltaX)
        let height = max(minSize, startFrame.height - deltaY)

        let minX = max(visibleFrame.minX, maxX - visibleFrame.width)
        let minY = max(visibleFrame.minY, maxY - visibleFrame.height)

        let originX = min(max(maxX - width, minX), maxX - minSize)
        let originY = min(max(maxY - height, minY), maxY - minSize)

        return NSRect(x: originX, y: originY, width: maxX - originX, height: maxY - originY)
    }
}
