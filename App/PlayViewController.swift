import MetalKit
import UIKit

final class PlayViewController: UIViewController, MTKViewDelegate {
    private let baseURL: URL?
    private let surface: MTKView
    private let controls = TouchOverlay(frame: .zero)
    private var preview: MetalPreview?
    private var session: EngineSession?
    private var attemptedGameStart = false

    init(baseURL: URL?) throws {
        let device = MTLCreateSystemDefaultDevice()
#if targetEnvironment(simulator)
        if baseURL != nil && device == nil { throw PlayError.metalUnavailable }
#else
        guard device != nil else { throw PlayError.metalUnavailable }
#endif
        self.baseURL = baseURL
        self.surface = MTKView(frame: .zero, device: device)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        surface.colorPixelFormat = .bgra8Unorm
        surface.depthStencilPixelFormat = .depth32Float
        surface.clearColor = MTLClearColor(red: 0.035, green: 0.042, blue: 0.054, alpha: 1)
        surface.preferredFramesPerSecond = 60
        surface.isPaused = true

        if baseURL == nil && surface.device != nil {
            preview = try MetalPreview(view: surface)
        }
    }

    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor(red: 0.035, green: 0.042, blue: 0.054, alpha: 1)
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        if surface.device == nil {
            let message = UILabel()
            message.text = "Metal недоступен в этом симуляторе."
            message.textColor = .secondaryLabel
            message.font = .preferredFont(forTextStyle: .body)
            message.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(message)
            NSLayoutConstraint.activate([
                message.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                message.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            ])
        }

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
        startGameIfNeeded()
        resume()
    }

    private func startGameIfNeeded() {
        guard let baseURL, !attemptedGameStart else { return }
        attemptedGameStart = true
        view.layoutIfNeeded()
        do {
            session = try EngineSession.open(baseURL: baseURL, metalView: surface)
        } catch {
            let alert = UIAlertController(title: "Не удалось запустить Half-Life 2",
                                          message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Назад", style: .default) { [weak self] _ in self?.leave() })
            present(alert, animated: true)
        }
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
        guard viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive,
              baseURL == nil || session != nil else { return }
        session?.setSuspended(false)
        surface.isPaused = surface.device == nil
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
