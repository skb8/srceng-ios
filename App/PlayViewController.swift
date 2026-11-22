import MetalKit
import UIKit

final class PlayViewController: UIViewController, MTKViewDelegate {
    private let baseURL: URL?
    private let surface: MTKView
    private let controls = TouchOverlay(frame: .zero)
    private var preview: MetalPreview?
    private var session: EngineSession?

    init(baseURL: URL?) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw PlayError.metalUnavailable }
        self.baseURL = baseURL
        self.surface = MTKView(frame: .zero, device: device)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        surface.colorPixelFormat = .bgra8Unorm
        surface.depthStencilPixelFormat = .depth32Float
        surface.clearColor = MTLClearColor(red: 0.035, green: 0.042, blue: 0.054, alpha: 1)
        surface.preferredFramesPerSecond = 60
        surface.isPaused = true

        if let baseURL {
            session = try EngineSession.open(baseURL: baseURL, metalView: surface)
        } else {
            preview = try MetalPreview(view: surface)
        }
    }

    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        view = UIView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Назад"
        configuration.baseBackgroundColor = .black.withAlphaComponent(0.7)
        let exit = UIButton(configuration: configuration,
                            primaryAction: UIAction { [weak self] _ in self?.leave() })
        exit.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exit)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            controls.topAnchor.constraint(equalTo: surface.topAnchor),
            controls.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            exit.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            exit.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            exit.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        surface.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
                                               name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume),
                                               name: UIScene.didActivateNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resume()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        suspend()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let input = controls.consumeInput()
        if let session {
            if !session.frame(in: view, input: input) {
                surface.isPaused = true
                DispatchQueue.main.async { [weak self] in self?.leave() }
            }
        } else {
            preview?.draw(in: view, input: input)
        }
    }

    @objc private func suspend() {
        surface.isPaused = true
        controls.reset()
        session?.setSuspended(true)
    }

    @objc private func resume() {
        guard viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive else { return }
        session?.setSuspended(false)
        surface.isPaused = false
    }

    private func leave() {
        suspend()
        session?.close()
        session = nil
        dismiss(animated: true)
    }

    private enum PlayError: LocalizedError {
        case metalUnavailable

        var errorDescription: String? { "Metal недоступен на этом устройстве." }
    }
}
