import UIKit

final class TouchOverlay: UIView {
    private let stick = MoveStick()
    private let lookPad = UIView()
    private var input = SourceInput()

    override init(frame: CGRect) {
        super.init(frame: frame)

        lookPad.translatesAutoresizingMaskIntoConstraints = false
        let lookGesture = UIPanGestureRecognizer(target: self, action: #selector(look(_:)))
        lookGesture.maximumNumberOfTouches = 1
        lookPad.addGestureRecognizer(lookGesture)
        addSubview(lookPad)

        stick.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stick)
        stick.onMove = { [weak self] point in
            self?.input.moveRight = Float(point.x)
            self?.input.moveForward = -Float(point.y)
        }

        let actions = UIStackView(arrangedSubviews: [
            makeButton("Прыжок", .jump),
            makeButton("Действие", .use),
            makeButton("Огонь", .attack),
        ])
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actions)

        let secondary = UIStackView(arrangedSubviews: [
            makeButton("Присесть", .duck),
            makeButton("Сменить магазин", .reload),
        ])
        secondary.spacing = 8
        secondary.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secondary)

        let menu = makeButton("Меню", .menu)
        menu.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menu)

        let safe = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            lookPad.leadingAnchor.constraint(equalTo: centerXAnchor),
            lookPad.trailingAnchor.constraint(equalTo: trailingAnchor),
            lookPad.topAnchor.constraint(equalTo: topAnchor),
            lookPad.bottomAnchor.constraint(equalTo: bottomAnchor),
            stick.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            stick.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
            stick.widthAnchor.constraint(equalToConstant: 112),
            stick.heightAnchor.constraint(equalTo: stick.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
            secondary.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
            secondary.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -8),
            menu.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            menu.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
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
        stick.reset()
        for recognizer in lookPad.gestureRecognizers ?? [] {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    @objc private func look(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended
        else { return }
        let delta = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        let scale = Float(max(1, min(bounds.width, bounds.height)))
        input.lookRight += Float(delta.x) / scale
        input.lookDown += Float(delta.y) / scale
    }

    private func makeButton(_ title: String, _ action: SourceButtons) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = .black.withAlphaComponent(0.7)
        configuration.baseForegroundColor = .white
        let button = UIButton(configuration: configuration)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.press(action) }, for: .touchDown)
        let release = UIAction { [weak self] _ in self?.release(action) }
        button.addAction(release, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return button
    }

    private func press(_ action: SourceButtons) {
        guard !input.held.contains(action) else { return }
        input.held.insert(action)
        input.pressed.insert(action)
    }

    private func release(_ action: SourceButtons) {
        guard input.held.contains(action) else { return }
        input.held.remove(action)
        input.released.insert(action)
    }
}

private final class MoveStick: UIView {
    var onMove: ((CGPoint) -> Void)?
    private var activeTouch: UITouch?
    private let knob = CALayer()
    private var offset = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black.withAlphaComponent(0.55)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.75).cgColor
        layer.addSublayer(knob)
        isAccessibilityElement = true
        accessibilityLabel = "Движение"
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        updateKnob()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        update(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { update(activeTouch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { reset() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    func reset() {
        activeTouch = nil
        offset = .zero
        onMove?(.zero)
        updateKnob()
    }

    private func update(_ touch: UITouch) {
        let point = touch.location(in: self)
        let radius = max(1, bounds.width * 0.33)
        let x = (point.x - bounds.midX) / radius
        let y = (point.y - bounds.midY) / radius
        let magnitude = max(1, hypot(x, y))
        offset = CGPoint(x: x / magnitude, y: y / magnitude)
        onMove?(offset)
        updateKnob()
    }

    private func updateKnob() {
        let radius = bounds.width * 0.33
        let diameter = bounds.width * 0.32
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        knob.cornerRadius = diameter / 2
        knob.position = CGPoint(x: bounds.midX + radius * offset.x,
                                y: bounds.midY + radius * offset.y)
        CATransaction.commit()
    }
}
