import AppKit

// Simple text inputs shared by the remaining settings panes.
protocol ProviderFieldInput: NSView {
    var stringValue: String { get set }
    var placeholderString: String? { get set }
    var font: NSFont? { get set }
}

extension NSTextField: ProviderFieldInput {}

/// Secure input that shows a small eye button on the right; clicking it swaps
/// to a plain field so the user can read back the value they typed.
final class RevealableSecureField: NSView, ProviderFieldInput, NSTextFieldDelegate {
    private let secureField = PasteableSecureTextField()
    private let plainField = PasteableTextField()
    private let toggleButton = NSButton()
    private var isRevealed = false

    var stringValue: String {
        get { (isRevealed ? plainField : secureField).stringValue }
        set {
            secureField.stringValue = newValue
            plainField.stringValue = newValue
        }
    }

    var placeholderString: String? {
        get { secureField.placeholderString }
        set {
            secureField.placeholderString = newValue
            plainField.placeholderString = newValue
        }
    }

    var font: NSFont? {
        get { secureField.font }
        set {
            secureField.font = newValue
            plainField.font = newValue
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for f in [secureField, plainField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.delegate = self
            addSubview(f)
        }
        plainField.isHidden = true

        toggleButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show secret")
        toggleButton.imagePosition = .imageOnly
        toggleButton.isBordered = false
        toggleButton.bezelStyle = .accessoryBarAction
        toggleButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        toggleButton.target = self
        toggleButton.action = #selector(toggleReveal)
        toggleButton.refusesFirstResponder = true
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleButton)

        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor),
            secureField.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -6),

            plainField.leadingAnchor.constraint(equalTo: secureField.leadingAnchor),
            plainField.trailingAnchor.constraint(equalTo: secureField.trailingAnchor),
            plainField.topAnchor.constraint(equalTo: secureField.topAnchor),
            plainField.bottomAnchor.constraint(equalTo: secureField.bottomAnchor),

            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 22),
            toggleButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggleReveal() {
        isRevealed.toggle()
        secureField.isHidden = isRevealed
        plainField.isHidden = !isRevealed
        let symbol = isRevealed ? "eye.slash" : "eye"
        toggleButton.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: isRevealed ? "Hide secret" : "Show secret"
        )

        // If the user was editing the field, transfer focus + caret to the
        // newly visible one so they can keep typing without re-clicking.
        guard let win = window else { return }
        let wasFirstResponder = (win.firstResponder as? NSText)?.delegate as? NSTextField === (isRevealed ? secureField : plainField)
        if wasFirstResponder {
            let target = isRevealed ? plainField : secureField
            win.makeFirstResponder(target)
            if let editor = target.currentEditor() {
                editor.selectedRange = NSRange(location: target.stringValue.count, length: 0)
            }
        }
    }

    // Keep the two fields in sync so toggling at any moment shows the latest value.
    func controlTextDidChange(_ obj: Notification) {
        guard let src = obj.object as? NSTextField else { return }
        if src === secureField {
            plainField.stringValue = secureField.stringValue
        } else if src === plainField {
            secureField.stringValue = plainField.stringValue
        }
    }
}

// MARK: - Pasteable text fields

// SaiShot is an LSUIElement app with no main menu, so the standard Edit-menu
// key equivalents that normally route Cmd+X/C/V/A to the field editor never
// fire. These subclasses handle the shortcuts directly via the responder chain.

private func dispatchEditingShortcut(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
        return false
    }
    let action: Selector
    switch event.charactersIgnoringModifiers {
    case "x": action = #selector(NSText.cut(_:))
    case "c": action = #selector(NSText.copy(_:))
    case "v": action = #selector(NSText.paste(_:))
    case "a": action = #selector(NSText.selectAll(_:))
    default: return false
    }
    return NSApp.sendAction(action, to: nil, from: nil)
}

final class PasteableTextField: NSTextField {
    var onFocus: ((PasteableTextField) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocus?(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocus?(self)
        }
        return didBecome
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if dispatchEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private final class PasteableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if dispatchEditingShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
