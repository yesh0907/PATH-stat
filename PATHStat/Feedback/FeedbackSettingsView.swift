import PATHKit
import SwiftUI

/// GitHub token, waiting and sent reports, and one-time setup steps.
struct FeedbackSettingsView: View {
    let center: FeedbackCenter

    static let newTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput = ""
    @State private var tokenMessage: String?
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                tokenSection
                waitingSection
                sentSection
                setupSection
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("feedback-settings-done")
                }
            }
        }
        .accessibilityIdentifier("feedback-settings")
        .task { await center.reload() }
        .onAppear { center.currentScreen = "feedback settings" }
        .onDisappear { center.currentScreen = "main" }
    }

    // MARK: Token

    private var tokenSection: some View {
        Section {
            if let masked = center.maskedToken {
                LabeledContent("Token", value: masked)
                    .accessibilityIdentifier("feedback-token-masked")
            }
            SecureField(center.maskedToken == nil ? "Paste token" : "Paste a new token", text: $tokenInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("feedback-token-field")
            Button("Save") {
                do {
                    try center.saveToken(tokenInput)
                    tokenInput = ""
                    tokenMessage = "Saved."
                    testResult = nil
                } catch {
                    tokenMessage = error.localizedDescription
                }
            }
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("feedback-token-save")
            if center.maskedToken != nil {
                Button {
                    isTesting = true
                    testResult = nil
                    Task {
                        let error = await center.testConnection()
                        testResult = error.map { "Failed: \($0.userMessage)" } ?? "Connected to \(GitHubRepo.pathStat.fullName)."
                        isTesting = false
                    }
                } label: {
                    HStack {
                        Text("Test connection")
                        if isTesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isTesting)
                .accessibilityIdentifier("feedback-token-test")
                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(testResult.hasPrefix("Failed") ? .red : .green)
                        .accessibilityIdentifier("feedback-token-test-result")
                }
                Button("Remove token", role: .destructive) {
                    try? center.removeToken()
                    tokenMessage = "Removed."
                    testResult = nil
                }
                .accessibilityIdentifier("feedback-token-remove")
            }
            if let tokenMessage {
                Text(tokenMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("feedback-token-message")
            }
        } header: {
            Text("GitHub token")
        } footer: {
            Text("Stored only in this device's Keychain.")
        }
    }

    // MARK: Reports

    private var waitingSection: some View {
        Section {
            if center.pending.isEmpty {
                Text("Nothing waiting.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.pending) { item in
                    PendingRow(center: center, item: item)
                }
                Button {
                    Task { await center.retry(force: true) }
                } label: {
                    HStack {
                        Text("Retry now")
                        if center.isRetrying { Spacer(); ProgressView() }
                    }
                }
                .disabled(center.isRetrying)
                .accessibilityIdentifier("feedback-retry")
            }
        } header: {
            Text("Waiting to send (\(center.pendingCount))")
        }
    }

    private var sentSection: some View {
        Section("Sent") {
            if center.sent.isEmpty {
                Text("No reports sent yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.sent) { item in
                    Link(destination: item.issue.htmlURL) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(item.issue.number) \(item.title)")
                                .lineLimit(2)
                            Text(item.sentAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("feedback-sent-\(item.issue.number)")
                }
            }
        }
    }

    // MARK: Setup

    private var setupSection: some View {
        Section("One-time setup") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. On GitHub: Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token.")
                Text("2. Resource owner: yesh0907. Expiration: e.g. 1 year.")
                Text("3. Repository access: Only select repositories → yesh0907/PATH-stat.")
                Text("4. Permissions: Contents read and write, Issues read and write (Metadata read-only is added automatically). Nothing else.")
                Text("5. Generate, copy, paste above, tap Save, then Test connection.")
            }
            .font(.footnote)
            Link("Create a fine-grained token", destination: Self.newTokenURL)
                .accessibilityIdentifier("feedback-token-link")
        }
    }
}

/// One waiting report: title, attempts, last error, and Share.
private struct PendingRow: View {
    let center: FeedbackCenter
    let item: QueuedFeedback

    @State private var screenshot: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FeedbackIssueFormatter.title(for: item.report))
                .lineLimit(2)
            Text(item.attempts == 1 ? "1 attempt" : "\(item.attempts) attempts")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = item.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            share
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feedback-pending-\(item.id.uuidString)")
        .task(id: item.id) {
            if item.hasScreenshot, let data = await center.screenshot(for: item.id) {
                screenshot = UIImage(data: data)
            }
        }
    }

    @ViewBuilder
    private var share: some View {
        let text = FeedbackShare.text(for: item.report, hasScreenshot: screenshot != nil)
        let title = FeedbackIssueFormatter.title(for: item.report)
        Group {
            if let screenshot {
                let image = Image(uiImage: screenshot)
                ShareLink(item: image, subject: Text(title), message: Text(text), preview: SharePreview(title, image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: text, subject: Text(title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }
}
