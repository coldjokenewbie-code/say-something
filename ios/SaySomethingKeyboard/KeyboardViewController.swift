import UIKit

/// SaySomething's custom keyboard: a remote control for the main App's
/// background recording session (Wispr Flow architecture — iOS keyboard
/// extensions are not allowed to record audio themselves). This keyboard
/// never touches AVFoundation; it only sends Darwin notification signals
/// and reads/writes the shared data channel (KeyboardBridge, shared with
/// the main App target).
final class KeyboardViewController: UIInputViewController {

    private var recording = false
    private var waitingForResult = false
    private var latestResult: String?
    private var resultTimeoutTimer: Timer?

    private let statusLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let launchButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let enterButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private var modeButtons: [String: UIButton] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        registerBridgeObservers()
        refreshModeHighlight()
        updateStatus(defaultStatusText())
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    deinit {
        resultTimeoutTimer?.invalidate()
        KeyboardBridge.removeObserver(.resultReady)
        KeyboardBridge.removeObserver(.resultError)
    }

    // MARK: - UI construction

    private func buildUI() {
        view.heightAnchor.constraint(equalToConstant: 268).isActive = true
        view.backgroundColor = UIColor.secondarySystemBackground

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center

        let modeScroll = buildModeRow()

        micButton.setTitle("🎤 開始", for: .normal)
        micButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        micButton.backgroundColor = .systemBlue
        micButton.setTitleColor(.white, for: .normal)
        micButton.layer.cornerRadius = 10
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        launchButton.setTitle("啟動 Say Something", for: .normal)
        launchButton.titleLabel?.font = .systemFont(ofSize: 13)
        launchButton.addTarget(self, action: #selector(launchTapped), for: .touchUpInside)

        insertButton.setTitle("插入最新結果", for: .normal)
        insertButton.titleLabel?.font = .systemFont(ofSize: 13)
        insertButton.addTarget(self, action: #selector(insertLatestTapped), for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [launchButton, insertButton])
        topRow.axis = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 8

        let micRow = UIStackView(arrangedSubviews: [micButton])
        micRow.axis = .horizontal
        micButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        configureKeyButton(backspaceButton, title: "⌫", action: #selector(backspaceTapped))
        configureKeyButton(spaceButton, title: "空白", action: #selector(spaceTapped))
        configureKeyButton(enterButton, title: "換行", action: #selector(enterTapped))
        configureKeyButton(globeButton, title: "🌐", action: #selector(globeTapped))

        let keyRow = UIStackView(arrangedSubviews: [globeButton, spaceButton, backspaceButton, enterButton])
        keyRow.axis = .horizontal
        keyRow.distribution = .fillEqually
        keyRow.spacing = 6
        keyRow.arrangedSubviews.forEach { $0.heightAnchor.constraint(equalToConstant: 40).isActive = true }

        let stack = UIStackView(arrangedSubviews: [statusLabel, modeScroll, micRow, topRow, keyRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
        ])
    }

    private func buildModeRow() -> UIScrollView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6

        for mode in Prompts.modes {
            let button = UIButton(type: .system)
            button.setTitle(mode.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12)
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            button.tag = Prompts.modes.firstIndex(where: { $0.id == mode.id }) ?? 0
            button.accessibilityIdentifier = mode.id
            button.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
            modeButtons[mode.id] = button
            row.addArrangedSubview(button)
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        scroll.heightAnchor.constraint(equalToConstant: 30).isActive = true
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.heightAnchor),
        ])
        return scroll
    }

    private func configureKeyButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.backgroundColor = UIColor.tertiarySystemBackground
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Mode switching (shares Prompts.swift with the main App target)

    @objc private func modeTapped(_ sender: UIButton) {
        guard sender.tag < Prompts.modes.count else { return }
        let mode = Prompts.modes[sender.tag]
        KeyboardBridge.setString(mode.id, for: .mode)
        refreshModeHighlight()
    }

    private func refreshModeHighlight() {
        let activeId = KeyboardBridge.string(for: .mode) ?? Prompts.modes[0].id
        for (id, button) in modeButtons {
            let active = id == activeId
            button.backgroundColor = active ? .systemBlue : UIColor.tertiarySystemBackground
            button.setTitleColor(active ? .white : .label, for: .normal)
        }
    }

    // MARK: - Mic / session control

    @objc private func micTapped() {
        if waitingForResult { return }
        if recording {
            stopRecording()
            return
        }
        guard KeyboardBridge.isSessionAlive() else {
            launchTapped()
            updateStatus("正在啟動 App…請稍候切回鍵盤後再按一次麥克風")
            return
        }
        startRecording()
    }

    private func startRecording() {
        KeyboardBridge.post(.recordStart)
        recording = true
        micButton.setTitle("⏹ 停止", for: .normal)
        micButton.backgroundColor = .systemRed
        updateStatus("錄音中…再按一次停止")
    }

    private func stopRecording() {
        KeyboardBridge.post(.recordStop)
        recording = false
        waitingForResult = true
        micButton.setTitle("🎤 開始", for: .normal)
        micButton.backgroundColor = .systemBlue
        updateStatus("處理中…")
        armResultTimeout()
    }

    private func armResultTimeout() {
        resultTimeoutTimer?.invalidate()
        resultTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self, self.waitingForResult else { return }
            self.waitingForResult = false
            self.updateStatus("逾時,沒有收到結果,請再試一次")
        }
    }

    @objc private func launchTapped() {
        openMainApp(KeyboardBridge.sessionURL)
    }

    /// Responder-chain trick: `UIApplication.shared` is unavailable inside
    /// extensions, so we walk `next` looking for a responder that answers
    /// to `openURL:` (UIApplication itself, further up the real app's
    /// chain isn't reachable from here — but the keyboard's own responder
    /// chain terminates at UIApplication in practice on iOS 16 for custom
    /// keyboards with open access). Falls back to an on-screen hint.
    private func openMainApp(_ url: URL) {
        let openURLSelector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: openURLSelector) {
                current.perform(openURLSelector, with: url)
                return
            }
            responder = current.next
        }
        updateStatus("請先手動開啟 SaySomething App")
    }

    @objc private func insertLatestTapped() {
        guard let text = latestResult, !text.isEmpty else {
            updateStatus("尚無結果可插入")
            return
        }
        textDocumentProxy.insertText(text)
    }

    // MARK: - Basic keys

    @objc private func backspaceTapped() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func spaceTapped() {
        textDocumentProxy.insertText(" ")
    }

    @objc private func enterTapped() {
        textDocumentProxy.insertText("\n")
    }

    @objc private func globeTapped() {
        advanceToNextInputMode()
    }

    // MARK: - Bridge notifications: app → keyboard

    private func registerBridgeObservers() {
        KeyboardBridge.addObserver(.resultReady) { [weak self] in self?.handleResultReady() }
        KeyboardBridge.addObserver(.resultError) { [weak self] in self?.handleResultError() }
    }

    private func handleResultReady() {
        resultTimeoutTimer?.invalidate()
        waitingForResult = false
        guard let text = KeyboardBridge.string(for: .result), !text.isEmpty else {
            updateStatus("完成,但沒有取得文字")
            return
        }
        latestResult = text
        textDocumentProxy.insertText(text)
        updateStatus("完成,已插入")
    }

    private func handleResultError() {
        resultTimeoutTimer?.invalidate()
        waitingForResult = false
        let message = KeyboardBridge.string(for: .error) ?? "發生未知錯誤"
        updateStatus(message)
    }

    private func defaultStatusText() -> String {
        KeyboardBridge.isSessionAlive() ? "按麥克風開始說話" : "請先按「啟動 Say Something」開始 session"
    }

    private func updateStatus(_ text: String) {
        statusLabel.text = text
    }
}
