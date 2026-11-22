import UIKit
import UniformTypeIdentifiers

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = LauncherViewController()
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

private final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let status = UILabel()
    private let importButton = UIButton()
    private let playButton = UIButton()
    private let previewButton = UIButton()
    private var importing = false
    private var baseURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.065, green: 0.071, blue: 0.084, alpha: 1)

        let title = UILabel()
        title.text = "Half-Life 2"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits = .header
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = .secondaryLabel

        configure(importButton, title: "Импортировать папку игры", primary: false,
                  action: #selector(selectFolder))
        configure(playButton, title: "Запустить HL2", primary: true, action: #selector(play))
        configure(previewButton, title: "Проверить Metal и управление", primary: false,
                  action: #selector(preview))

        let stack = UIStackView(arrangedSubviews: [title, status, importButton, playButton, previewButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        let safe = view.safeAreaLayoutGuide
        let preferredWidth = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor,
                                                          constant: -40)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            preferredWidth,
        ])
        refresh()
    }

    private func configure(_ button: UIButton, title: String, primary: Bool, action: Selector) {
        var configuration = primary ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        configuration.title = title
        configuration.baseBackgroundColor = primary ? .systemOrange : .tertiarySystemFill
        configuration.baseForegroundColor = primary ? .black : .label
        button.configuration = configuration
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func refresh() {
        baseURL = GameFiles.installedBase()
        importButton.isEnabled = !importing
        playButton.isEnabled = !importing && baseURL != nil && EngineSession.isLinked
        previewButton.isEnabled = !importing

        if importing {
            status.text = "Копирование файлов Half-Life 2…"
        } else {
            let files = baseURL == nil ? "Выберите папку с hl2/gameinfo.txt." : "Файлы игры импортированы."
            status.text = EngineSession.isLinked ? files : files + " Запуск HL2 требует сборки движка для iOS."
        }
    }

    @objc private func selectFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !importing, let folder = urls.first else { return }
        importing = true
        refresh()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try GameFiles.install(from: folder) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.importing = false
                self.refresh()
                if case let .failure(error) = result { self.show(error) }
            }
        }
    }

    @objc private func play() {
        if let baseURL { open(baseURL: baseURL) }
    }

    @objc private func preview() { open(baseURL: nil) }

    private func open(baseURL: URL?) {
        do {
            let controller = try PlayViewController(baseURL: baseURL)
            present(controller, animated: true)
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        let alert = UIAlertController(title: "Source iOS", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
