import Foundation
import Network
import Observation
import os
import PATHKit
import SwiftUI
import UIKit

/// Shake-or-tap feedback: captures a screenshot and app context, presents `FeedbackSheet` over
/// whatever is on screen, saves reports to the durable `FeedbackQueue`, and retries delivery to
/// GitHub on launch, foreground, network recovery, token changes and background refresh.
@MainActor
@Observable
final class FeedbackCenter {
    enum Trigger: String {
        case button
        case shake
    }

    /// Makes the issue service for a token; nil means "no token yet".
    typealias ServiceFactory = @MainActor (_ token: String?) -> (any FeedbackIssueService)?

    private(set) var pending: [QueuedFeedback] = []
    private(set) var sent: [SentFeedback] = []
    private(set) var lastOutcome: [UUID: FeedbackDeliveryOutcome] = [:]
    private(set) var isRetrying = false
    /// Masked token for display ("github_pat_…1a2b"), nil without one.
    private(set) var maskedToken: String?
    /// Which screen is showing, for report context ("main", "station picker", …).
    var currentScreen = "main"
    /// Fills in trip / feed / location / Live Activity fields; set by the main screen.
    @ObservationIgnored var contextProvider: (@MainActor (inout FeedbackContext) -> Void)?

    var pendingCount: Int { pending.count }

    @ObservationIgnored private(set) var notices = RecentNotices()
    @ObservationIgnored let queue: FeedbackQueue
    @ObservationIgnored private let tokenStore: any FeedbackTokenStore
    @ObservationIgnored private let makeService: ServiceFactory
    @ObservationIgnored private let isLive: Bool
    @ObservationIgnored private var presented: UIViewController?
    @ObservationIgnored private var presentationDelegate: PresentationDelegate?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var shakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var debugShakeWindow: UIWindow?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "feedback")

    init(queue: FeedbackQueue, tokenStore: any FeedbackTokenStore, isLive: Bool, makeService: @escaping ServiceFactory) {
        self.queue = queue
        self.tokenStore = tokenStore
        self.isLive = isLive
        self.makeService = makeService
        maskedToken = tokenStore.token().map(KeychainTokenStore.masked)
        shakeObserver = NotificationCenter.default.addObserver(forName: .pathStatDeviceDidShake, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.present(trigger: .shake) }
        }
    }

    /// Live: Keychain token, GitHub, `Application Support/Feedback`.
    static func live() -> FeedbackCenter {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return FeedbackCenter(
            queue: FeedbackQueue(directory: base.appending(path: "Feedback", directoryHint: .isDirectory)),
            tokenStore: KeychainTokenStore(),
            isLive: true,
            makeService: { token in token.map { GitHubClient(token: $0) } }
        )
    }

    var isPresented: Bool { presented != nil }

    // MARK: Lifecycle

    /// At launch: load the queue, retry, and (live) watch for the network coming back.
    func start() {
        guard !started else { return }
        started = true
        if isLive { startPathMonitor() }
        Task { await retry(force: false) }
    }

    func sceneDidBecomeActive() {
        guard started else { return }
        Task { await retry(force: false) }
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.networkPathChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.yesh0907.PATHStat.feedback.path"))
        pathMonitor = monitor
    }

    @ObservationIgnored private var networkSatisfied: Bool?

    /// Retries (forced, since earlier failures were network ones) only on the way back online.
    private func networkPathChanged(satisfied: Bool) {
        defer { networkSatisfied = satisfied }
        guard satisfied, networkSatisfied == false else { return }
        Task { await retry(force: true) }
    }

    // MARK: Notices

    /// Remembers a user-visible problem for the next report's context.
    func record(_ notice: String) {
        notices.record(notice)
    }

    // MARK: Presenting

    /// Screenshots the key window, then presents the feedback sheet over the topmost screen.
    /// Ignored while the sheet is already up.
    func present(trigger: Trigger) {
        guard presented == nil, let window = Self.keyWindow() else { return }
        let screenshot = Self.capture(window)
        let context = makeContext(window: window)
        var top = window.rootViewController
        while let next = top?.presentedViewController { top = next }
        guard let top else { return }

        let host = UIHostingController(rootView: FeedbackSheet(
            center: self,
            screenshot: screenshot,
            context: context,
            dismiss: { [weak self] in self?.dismissSheet() }
        ))
        let delegate = PresentationDelegate { [weak self] in
            self?.presented = nil
        }
        host.presentationController?.delegate = delegate
        presentationDelegate = delegate
        presented = host
        logger.info("Feedback sheet opened by \(trigger.rawValue, privacy: .public)")
        top.present(host, animated: true)
    }

    func dismissSheet() {
        guard let presented else { return }
        presented.dismiss(animated: true)
        self.presented = nil
    }

    private final class PresentationDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
        let didDismiss: @MainActor () -> Void
        init(didDismiss: @escaping @MainActor () -> Void) { self.didDismiss = didDismiss }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            MainActor.assumeIsolated { didDismiss() }
        }
    }

    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows).filter { !($0 is DebugShakeWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    /// PNG of the window as it is right now (before the sheet appears), at 2× scale.
    static func capture(_ window: UIWindow) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.pngData { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    func makeContext(window: UIWindow?) -> FeedbackContext {
        let traits = window?.traitCollection ?? UITraitCollection.current
        var context = FeedbackContext(
            appVersion: AppInfo.version,
            gitCommit: AppInfo.gitCommit,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: AppInfo.deviceModel,
            screen: currentScreen,
            appearance: traits.userInterfaceStyle == .dark ? "dark" : "light",
            dynamicTypeSize: DynamicTypeSize(traits.preferredContentSizeCategory).map { String(describing: $0) }
                ?? traits.preferredContentSizeCategory.rawValue,
            timestamp: .now
        )
        contextProvider?(&context)
        context.screen = currentScreen
        context.recentNotices = notices.descriptions
        return context
    }

    // MARK: Sending

    /// Saves the report first (so it is never lost), then tries to send everything now.
    func send(note: String, category: FeedbackCategory, context: FeedbackContext, screenshot: Data?) async -> FeedbackDeliveryOutcome {
        let report = FeedbackReport(note: note, category: category, context: context)
        do {
            try await queue.enqueue(report, screenshot: screenshot)
        } catch {
            logger.error("Couldn't save feedback \(report.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return .waiting(.validation("Couldn't save the report on this device."))
        }
        logger.info("Queued feedback \(report.id.uuidString, privacy: .public)")
        await retry(force: true)
        return lastOutcome[report.id] ?? .waiting(maskedToken == nil ? .noToken : .network(""))
    }

    /// Sends waiting reports (only those due, unless `force`), refreshes the lists, and
    /// schedules one foreground retry for the earliest backed-off report.
    func retry(force: Bool) async {
        isRetrying = true
        defer { isRetrying = false }
        let outcomes = await queue.process(using: makeService(tokenStore.token()), now: .now, force: force)
        lastOutcome.merge(outcomes) { _, new in new }
        for (id, outcome) in outcomes {
            switch outcome {
            case .sent(let issue):
                logger.info("Feedback \(id.uuidString, privacy: .public) sent as #\(issue.number, privacy: .public)")
            case .waiting(let error):
                logger.notice("Feedback \(id.uuidString, privacy: .public) waiting: \(error.userMessage, privacy: .public)")
            }
        }
        await reload()
        await scheduleRetry()
    }

    func reload() async {
        pending = await queue.pending()
        sent = await queue.sent()
    }

    private func scheduleRetry() async {
        retryTask?.cancel()
        retryTask = nil
        guard maskedToken != nil, let date = await queue.nextAttemptDate else { return }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            } catch {
                return
            }
            await self?.retry(force: false)
        }
    }

    func screenshot(for id: UUID) async -> Data? {
        await queue.screenshot(for: id)
    }

    // MARK: Token

    func saveToken(_ token: String) throws {
        try tokenStore.save(token)
        maskedToken = tokenStore.token().map(KeychainTokenStore.masked)
        logger.info("Feedback token saved")
        Task { await retry(force: true) }
    }

    func removeToken() throws {
        try tokenStore.delete()
        maskedToken = nil
        retryTask?.cancel()
        logger.info("Feedback token removed")
    }

    /// Checks the saved token can see the repository.
    func testConnection() async -> FeedbackSendError? {
        guard let service = makeService(tokenStore.token()) else { return .noToken }
        do {
            try await service.verifyAccess()
            return nil
        } catch {
            return FeedbackSendError.from(error)
        }
    }

    // MARK: Scenario "Simulate shake"

    /// Scenario mode only: a near-invisible 44×44 button in its own window, above any sheet,
    /// that posts the same shake notification (XCUITest can't shake the simulator).
    func installDebugShakeButton() {
        guard !isLive, debugShakeWindow == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let size: CGFloat = 44
        let window = DebugShakeWindow(windowScene: scene)
        // Leading edge, mid-height: clear of the status bar (whose touches the system takes)
        // and of the controls tests tap, on the main screen and on sheets.
        window.frame = CGRect(x: 0, y: (scene.screen.bounds.height - size) / 2, width: size, height: size)
        window.windowLevel = .alert + 1
        let controller = UIViewController()
        let button = UIButton(type: .custom, primaryAction: UIAction { _ in
            NotificationCenter.default.post(name: .pathStatDeviceDidShake, object: nil)
        })
        button.frame = CGRect(x: 0, y: 0, width: size, height: size)
        button.backgroundColor = .systemGray
        button.alpha = 0.02
        button.accessibilityIdentifier = "debug-simulate-shake"
        button.accessibilityLabel = "Simulate shake"
        controller.view.addSubview(button)
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false
        debugShakeWindow = window
    }
}

/// The scenario-only window holding the "Simulate shake" button; never captured or presented on.
final class DebugShakeWindow: UIWindow {}

/// Build and device facts for report context.
enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// `PATHStatGitCommit`, written into the built Info.plist by the "Embed Git Commit" phase.
    static var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "PATHStatGitCommit") as? String
    }

    /// "iPhone18,1"; the simulated model's identifier on the Simulator.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
