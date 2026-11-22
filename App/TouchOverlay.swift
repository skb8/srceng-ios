import UIKit

final class TouchOverlay: UIView {
    private enum Behavior {
        case hold(SourceButtons)
        case tap(SourceButtons)
        case toggleCrouch
        case edit
    }

    private struct Control {
        let id: String
        let label: String
        let icon: String
        let region: CGRect
        let behavior: Behavior

        init(_ id: String, _ label: String, _ icon: String, _ behavior: Behavior,
             _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            self.id = id
            self.label = label
            self.icon = icon
            self.behavior = behavior
            self.region = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        }
    }

    // Source's Android default touch profile, expressed in fractions of the screen.
    private static let layout: [Control] = [
        .init("menu", "Меню игры", "line.3.horizontal", .tap(.menu), 0, 0, 0.08, 0.142222),
        .init("invprev", "Предыдущее оружие", "chevron.up", .tap(.previousWeapon), 0, 0.071111, 0.12, 0.284444),
        .init("reload", "Перезарядить", "arrow.clockwise", .hold(.reload), 0, 0.32, 0.12, 0.533333),
        .init("invnext", "Следующее оружие", "chevron.down", .tap(.nextWeapon), 0, 0.533333, 0.12, 0.746667),
        .init("speed", "Спринт", "figure.run", .hold(.sprint), 0.18, 0.568889, 0.28, 0.746667),
        .init("edit", "Редактировать раскладку", "slider.horizontal.3", .edit, 0.42, 0, 0.50, 0.151486),
        .init("tduck", "Приседание с фиксацией", "lock", .toggleCrouch, 0.56, 0.817778, 0.62, 0.924444),
        .init("zoom", "Приближение", "viewfinder", .hold(.zoom), 0.68, 0, 0.76, 0.142222),
        .init("loadquick", "Быстрая загрузка", "arrow.up.doc", .tap(.quickLoad), 0.76, 0, 0.84, 0.142222),
        .init("savequick", "Быстрое сохранение", "arrow.down.doc", .tap(.quickSave), 0.84, 0, 0.92, 0.142222),
        .init("flashlight", "Фонарь", "flashlight.on.fill", .tap(.flashlight), 0.92, 0, 1, 0.142222),
        .init("use", "Использовать", "hand.tap", .hold(.use), 0.88, 0.213333, 1, 0.426667),
        .init("attack2", "Альтернативный огонь", "scope", .hold(.alternateAttack), 0.76, 0.32, 0.88, 0.533333),
        .init("jump", "Прыжок", "arrow.up", .hold(.jump), 0.88, 0.462222, 1, 0.675556),
        .init("attack", "Огонь", "target", .hold(.attack), 0.76, 0.583333, 0.88, 0.796667),
        .init("duck", "Присесть", "arrow.down", .hold(.duck), 0.88, 0.746667, 1, 0.96),
    ]

    private static let positionKey = "androidTouchLayoutPositions"

    private let moveIndicator = MoveIndicator()
    private let editLabel = UILabel()
    private let resetControl = TouchGlyph(icon: "arrow.uturn.backward", label: "Сбросить раскладку")
    private var glyphs: [TouchGlyph] = []
    private var positions: [String: [Double]] = UserDefaults.standard.dictionary(forKey: positionKey)
        as? [String: [Double]] ?? [:]
    private var input = SourceInput()
    private var pressedControls: [UITouch: Int] = [:]
    private var movementTouch: UITouch?
    private var movementOrigin = CGPoint.zero
    private var lookTouch: UITouch?
    private var lookOrigin = CGPoint.zero
    private var crouchLocked = false
    private var editing = false
    private var editTouch: UITouch?
    private var movingControl: Int?
    private var dragOffset = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        moveIndicator.isUserInteractionEnabled = false
        addSubview(moveIndicator)

        editLabel.text = "Перетащите кнопки"
        editLabel.font = .preferredFont(forTextStyle: .headline)
        editLabel.textColor = .white
        editLabel.textAlignment = .center
        editLabel.isHidden = true
        addSubview(editLabel)

        resetControl.isHidden = true
        resetControl.activate = { [weak self] in self?.restoreLayout() }
        addSubview(resetControl)

        for (index, control) in Self.layout.enumerated() {
            let glyph = TouchGlyph(icon: control.icon, label: control.label)
            glyph.activate = { [weak self] in self?.activate(index) }
            addSubview(glyph)
            glyphs.append(glyph)
        }
    }

    required init?(coder: NSCoder) { return nil }

    private var layoutArea: CGRect {
        bounds.inset(by: safeAreaInsets).insetBy(dx: 6, dy: 5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let area = layoutArea
        guard area.width > 0, area.height > 0 else { return }
        for (index, control) in Self.layout.enumerated() {
            let saved = positions[control.id]
            let center = saved.flatMap { point -> CGPoint? in
                guard point.count == 2, point[0].isFinite, point[1].isFinite else { return nil }
                return CGPoint(x: point[0], y: point[1])
            } ?? defaultCenter(for: control)
            let longest = control.id == "attack" ? CGFloat(72) : CGFloat(55)
            let size = max(44, min(longest, area.width * control.region.width, area.height * control.region.height))
            let glyph = glyphs[index]
            glyph.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            glyph.center = clampedCenter(
                CGPoint(x: area.minX + area.width * center.x, y: area.minY + area.height * center.y),
                radius: size / 2
            )
        }

        editLabel.frame = CGRect(x: area.minX, y: area.midY - 18, width: area.width, height: 36)
        resetControl.frame = CGRect(x: area.midX - 22, y: area.midY + 24, width: 44, height: 44)
        updateMovementIndicator()
    }

    // The Android menu and previous-weapon regions overlap. Offset the left
    // column's upper button enough to keep both iOS touch targets separate.
    private func defaultCenter(for control: Control) -> CGPoint {
        CGPoint(x: control.region.midX, y: control.id == "invprev" ? 0.21 : control.region.midY)
    }

    private func clampedCenter(_ point: CGPoint, radius: CGFloat) -> CGPoint {
        let safe = layoutArea.insetBy(dx: radius, dy: radius)
        return CGPoint(x: min(max(point.x, safe.minX), safe.maxX),
                       y: min(max(point.y, safe.minY), safe.maxY))
    }

    func consumeInput() -> SourceInput {
        let snapshot = input
        input.lookRight = 0
        input.lookDown = 0
        input.pressed = []
        input.released = []
        return snapshot
    }

    func reset() {
        let released = input.released.union(input.held)
        input = SourceInput()
        input.released = released
        pressedControls.removeAll()
        movementTouch = nil
        lookTouch = nil
        editTouch = nil
        movingControl = nil
        crouchLocked = false
        updateMovementIndicator()
        updateGlyphs()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        for touch in touches {
            let location = touch.location(in: self)
            let matched = glyphs.indices.reversed().first { glyphs[$0].frame.contains(location) }
            if editing && resetControl.frame.contains(location) {
                restoreLayout()
                continue
            }
            if let matched, case .edit = Self.layout[matched].behavior {
                activate(matched)
                continue
            }
            if editing {
                beginEditingTouch(touch, control: matched, at: location)
                continue
            }
            if let matched {
                pressedControls[touch] = matched
                switch Self.layout[matched].behavior {
                case .hold:
                    updateHeld()
                case .tap, .toggleCrouch:
                    activate(matched)
                case .edit:
                    break
                }
                updateGlyphs()
            }
            if location.x < bounds.midX, movementTouch == nil {
                movementTouch = touch
                movementOrigin = location
                updateMovementIndicator()
            } else if location.x >= bounds.midX, lookTouch == nil {
                lookTouch = touch
                lookOrigin = location
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if editing {
            if let editTouch, touches.contains(editTouch) { moveEditingTouch(editTouch) }
            return
        }
        if let movementTouch, touches.contains(movementTouch) {
            let point = movementTouch.location(in: self)
            let x = (point.x - movementOrigin.x) / max(1, bounds.width * 0.06)
            let y = (movementOrigin.y - point.y) / max(1, bounds.height * 0.06)
            input.moveRight = Float(min(1, max(-1, x)))
            input.moveForward = Float(min(1, max(-1, y)))
            updateMovementIndicator()
        }
        if let lookTouch, touches.contains(lookTouch) {
            let point = lookTouch.location(in: self)
            input.lookRight += Float((point.x - lookOrigin.x) / max(1, bounds.width))
            input.lookDown += Float((point.y - lookOrigin.y) / max(1, bounds.height))
            lookOrigin = point
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches)
    }

    private func finishTouches(_ touches: Set<UITouch>) {
        for touch in touches { pressedControls.removeValue(forKey: touch) }
        if let movementTouch, touches.contains(movementTouch) {
            self.movementTouch = nil
            input.moveRight = 0
            input.moveForward = 0
            updateMovementIndicator()
        }
        if let lookTouch, touches.contains(lookTouch) { self.lookTouch = nil }
        if let editTouch, touches.contains(editTouch) {
            self.editTouch = nil
            movingControl = nil
            UserDefaults.standard.set(positions, forKey: Self.positionKey)
        }
        updateHeld()
        updateGlyphs()
    }

    private func activate(_ index: Int) {
        switch Self.layout[index].behavior {
        case .hold(let action):
            if !input.held.contains(action) {
                input.pressed.insert(action)
                input.released.insert(action)
            }
        case .tap(let action):
            input.pressed.insert(action)
        case .toggleCrouch:
            crouchLocked.toggle()
            updateHeld()
            updateGlyphs()
        case .edit:
            reset()
            editing.toggle()
            editLabel.isHidden = !editing
            resetControl.isHidden = !editing
            updateGlyphs()
        }
    }

    private func updateHeld() {
        var held: SourceButtons = crouchLocked ? .duck : []
        for index in pressedControls.values {
            if case .hold(let action) = Self.layout[index].behavior { held.insert(action) }
        }
        input.pressed.formUnion(held.subtracting(input.held))
        input.released.formUnion(input.held.subtracting(held))
        input.held = held
    }

    private func updateGlyphs() {
        for (index, glyph) in glyphs.enumerated() {
            let control = Self.layout[index]
            let selected = (control.id == "tduck" && crouchLocked) || (control.id == "edit" && editing)
            glyph.setActive(selected || pressedControls.values.contains(index))
            if control.id == "tduck" || control.id == "edit" {
                glyph.accessibilityValue = selected ? "Включено" : "Выключено"
            }
        }
    }

    private func updateMovementIndicator() {
        let active = movementTouch != nil
        moveIndicator.isHidden = editing
        moveIndicator.alpha = active ? 1 : 0.48
        moveIndicator.bounds = CGRect(x: 0, y: 0, width: 78, height: 78)
        moveIndicator.center = active
            ? movementOrigin
            : CGPoint(x: layoutArea.minX + layoutArea.width * 0.27, y: layoutArea.minY + layoutArea.height * 0.77)
        moveIndicator.offset = CGPoint(x: CGFloat(input.moveRight), y: -CGFloat(input.moveForward))
    }

    private func beginEditingTouch(_ touch: UITouch, control: Int?, at point: CGPoint) {
        guard editTouch == nil, let control else { return }
        editTouch = touch
        movingControl = control
        let center = glyphs[control].center
        dragOffset = CGPoint(x: center.x - point.x, y: center.y - point.y)
    }

    private func moveEditingTouch(_ touch: UITouch) {
        guard let movingControl, layoutArea.width > 0, layoutArea.height > 0 else { return }
        let point = touch.location(in: self)
        let glyph = glyphs[movingControl]
        glyph.center = clampedCenter(CGPoint(x: point.x + dragOffset.x, y: point.y + dragOffset.y),
                                     radius: glyph.bounds.width / 2)
        positions[Self.layout[movingControl].id] = [
            Double((glyph.center.x - layoutArea.minX) / layoutArea.width),
            Double((glyph.center.y - layoutArea.minY) / layoutArea.height),
        ]
    }

    private func restoreLayout() {
        positions.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        setNeedsLayout()
    }
}

private final class TouchGlyph: UIView {
    private let imageView: UIImageView
    var activate: (() -> Void)?

    init(icon: String, label: String) {
        imageView = UIImageView(image: UIImage(systemName: icon, withConfiguration:
                                                UIImage.SymbolConfiguration(weight: .semibold)))
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .button
        layer.borderWidth = 1
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        setActive(false)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        imageView.frame = bounds.insetBy(dx: bounds.width * 0.24, dy: bounds.height * 0.24)
    }

    override func accessibilityActivate() -> Bool {
        activate?()
        return activate != nil
    }

    func setActive(_ active: Bool) {
        backgroundColor = active ? .systemOrange.withAlphaComponent(0.82) : .black.withAlphaComponent(0.55)
        layer.borderColor = UIColor.white.withAlphaComponent(active ? 0.65 : 0.42).cgColor
        imageView.tintColor = active ? .black : .white
    }
}

private final class MoveIndicator: UIView {
    private let knob = CALayer()
    var offset = CGPoint.zero {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.48).cgColor
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.65).cgColor
        layer.addSublayer(knob)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        let radius = bounds.width * 0.27
        let diameter = bounds.width * 0.31
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        knob.cornerRadius = diameter / 2
        knob.position = CGPoint(x: bounds.midX + radius * offset.x, y: bounds.midY + radius * offset.y)
        CATransaction.commit()
    }
}
