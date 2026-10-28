import AppKit

protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidRequestClose(_ view: OverlayView)
    func overlayViewDidRequestRatioEdit(_ view: OverlayView)
    func overlayView(_ view: OverlayView, didBeginInteraction zone: HitZone, mouseScreenPoint: NSPoint)
    func overlayView(_ view: OverlayView, didContinueInteraction mouseScreenPoint: NSPoint)
    func overlayViewDidEndInteraction(_ view: OverlayView)
}

final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?

    var strokeColor: NSColor = NSColor(calibratedWhite: 1.0, alpha: 0.78) {
        didSet { needsDisplay = true }
    }

    var ratioText: String = "16:9" {
        didSet { needsDisplay = true }
    }

    let visualLineWidth: CGFloat = 1.5
    let interactionInset: CGFloat = 10
    let closeButtonSize: CGFloat = 12
    let labelHeight: CGFloat = 16
    let labelHorizontalPadding: CGFloat = 7
    let labelHotInset: CGFloat = 6
    let controlGap: CGFloat = 4
    let infoPanelMinWidth: CGFloat = 72
    let infoPanelHeight: CGFloat = 36

    private var activeInteraction = false

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let borderRect = frameRect().insetBy(dx: visualLineWidth / 2, dy: visualLineWidth / 2)
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = visualLineWidth
        path.setLineDash([6, 4], count: 2, phase: 0)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = .zero
        shadow.set()
        strokeColor.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let closeRect = closeButtonRect()
        let closePath = NSBezierPath(ovalIn: closeRect)
        NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.33, alpha: 0.88).setFill()
        closePath.fill()

        let cross = NSBezierPath()
        cross.lineWidth = 1.2
        let inset: CGFloat = 3.2
        cross.move(to: NSPoint(x: closeRect.minX + inset, y: closeRect.minY + inset))
        cross.line(to: NSPoint(x: closeRect.maxX - inset, y: closeRect.maxY - inset))
        cross.move(to: NSPoint(x: closeRect.maxX - inset, y: closeRect.minY + inset))
        cross.line(to: NSPoint(x: closeRect.minX + inset, y: closeRect.maxY - inset))
        NSColor.white.withAlphaComponent(0.95).setStroke()
        cross.stroke()

        drawLabel(text: "Any", in: anyLabelRect())
        drawLabel(text: "Fix", in: fixLabelRect())
        drawInfoPanel(in: infoPanelRect())
    }

    func hitZone(at localPoint: NSPoint) -> HitZone {
        guard bounds.contains(localPoint) else { return .none }

        if closeButtonRect().insetBy(dx: -4, dy: -4).contains(localPoint) {
            return .closeButton
        }

        if anyLabelHitRect().contains(localPoint) {
            return .resize(.bottomLeftAny)
        }
        if fixLabelHitRect().contains(localPoint) {
            return .resize(.bottomRightFix)
        }
        if infoPanelHitRect().contains(localPoint) {
            return .move
        }
        let frame = frameRect()
        let nearLeft = localPoint.x >= frame.minX && localPoint.x <= frame.minX + interactionInset && localPoint.y >= frame.minY && localPoint.y <= frame.maxY
        let nearRight = localPoint.x <= frame.maxX && localPoint.x >= frame.maxX - interactionInset && localPoint.y >= frame.minY && localPoint.y <= frame.maxY
        let nearBottom = localPoint.y >= frame.minY && localPoint.y <= frame.minY + interactionInset && localPoint.x >= frame.minX && localPoint.x <= frame.maxX
        let nearTop = localPoint.y <= frame.maxY && localPoint.y >= frame.maxY - interactionInset && localPoint.x >= frame.minX && localPoint.x <= frame.maxX

        if nearLeft || nearRight || nearBottom || nearTop {
            return .move
        }

        return .none
    }

    func isInteractive(at localPoint: NSPoint) -> Bool {
        switch hitZone(at: localPoint) {
        case .none:
            return false
        default:
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let zone = hitZone(at: localPoint)
        if event.clickCount >= 2, shouldOpenRatioEditor(at: localPoint) {
            delegate?.overlayViewDidRequestRatioEdit(self)
            return
        }

        switch zone {
        case .none:
            return
        case .closeButton:
            delegate?.overlayViewDidRequestClose(self)
            return
        default:
            break
        }

        activeInteraction = true
        delegate?.overlayView(self, didBeginInteraction: zone, mouseScreenPoint: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeInteraction else { return }
        delegate?.overlayView(self, didContinueInteraction: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard activeInteraction else { return }
        activeInteraction = false
        delegate?.overlayViewDidEndInteraction(self)
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    private func drawLabel(text: String, in rect: NSRect) {
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        labelBackgroundColor().setFill()
        backgroundPath.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: labelTextColor()
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 + 0.5,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func drawInfoPanel(in rect: NSRect) {
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        labelBackgroundColor().setFill()
        backgroundPath.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: labelTextColor()
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: labelTextColor().withAlphaComponent(0.95)
        ]

        let ratioRect = NSRect(x: rect.minX + 6, y: rect.maxY - 17, width: rect.width - 12, height: 12)
        ratioText.draw(in: ratioRect, withAttributes: titleAttributes)

        let frame = frameRect()
        let sizeText = String(format: "%.0f x %.0f", frame.width, frame.height)
        let sizeRect = NSRect(x: rect.minX + 6, y: rect.minY + 5, width: rect.width - 12, height: 11)
        sizeText.draw(in: sizeRect, withAttributes: detailAttributes)
    }

    private func closeButtonRect() -> NSRect {
        NSRect(
            x: frameRect().minX - closeButtonSize - controlGap,
            y: frameRect().maxY - closeButtonSize,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    private func anyLabelRect() -> NSRect {
        labelRect(alignedToRight: false, text: "Any")
    }

    private func fixLabelRect() -> NSRect {
        labelRect(alignedToRight: true, text: "Fix")
    }

    private func labelRect(alignedToRight: Bool, text: String) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        let textSize = text.size(withAttributes: attributes)
        let width = ceil(textSize.width) + labelHorizontalPadding * 2
        let frame = frameRect()
        let originX = alignedToRight ? frame.maxX + controlGap : frame.minX - width - controlGap
        let originY = frame.minY

        return NSRect(
            x: originX,
            y: originY,
            width: width,
            height: labelHeight
        )
    }

    private func infoPanelRect() -> NSRect {
        let frame = frameRect()
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ]
        let ratioWidth = ceil(ratioText.size(withAttributes: titleAttributes).width)
        let sizeText = String(format: "%.0f x %.0f", frame.width, frame.height)
        let sizeWidth = ceil(sizeText.size(withAttributes: detailAttributes).width)
        let width = max(infoPanelMinWidth, max(ratioWidth, sizeWidth) + 12)
        return NSRect(
            x: frame.maxX + controlGap,
            y: frame.maxY - infoPanelHeight,
            width: width,
            height: infoPanelHeight
        )
    }

    private func anyLabelHitRect() -> NSRect {
        anyLabelRect().insetBy(dx: -labelHotInset, dy: -labelHotInset)
    }

    private func fixLabelHitRect() -> NSRect {
        fixLabelRect().insetBy(dx: -labelHotInset, dy: -labelHotInset)
    }

    private func infoPanelHitRect() -> NSRect {
        infoPanelRect().insetBy(dx: -labelHotInset, dy: -labelHotInset)
    }

    private func labelBackgroundColor() -> NSColor {
        let rgb = strokeColor.usingColorSpace(.deviceRGB) ?? strokeColor
        return NSColor(
            calibratedRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: rgb.alphaComponent
        )
    }

    private func labelTextColor() -> NSColor {
        let rgb = labelBackgroundColor().usingColorSpace(.deviceRGB) ?? .white
        let luminance = (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
        return luminance > 0.6 ? NSColor.black.withAlphaComponent(0.9) : NSColor.white.withAlphaComponent(0.95)
    }

    private func frameRect() -> NSRect {
        NSRect(
            x: OverlayChromeMetrics.leftInset,
            y: OverlayChromeMetrics.bottomInset,
            width: bounds.width - OverlayChromeMetrics.leftInset - OverlayChromeMetrics.rightInset,
            height: max(bounds.height - OverlayChromeMetrics.topInset - OverlayChromeMetrics.bottomInset, 80)
        )
    }

    private func shouldOpenRatioEditor(at localPoint: NSPoint) -> Bool {
        infoPanelHitRect().contains(localPoint)
    }
}
