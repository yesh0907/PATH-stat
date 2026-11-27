import PATHKit
import SwiftUI
import UIKit

/// Compose a report: screenshot (mark up / remove), note, category; then Send, which saves the
/// report first and shows whether it became an issue or is waiting to send.
struct FeedbackSheet: View {
    let center: FeedbackCenter
    let context: FeedbackContext
    let dismiss: () -> Void

    private enum Phase {
        case compose
        case sending
        case sent(CreatedIssue)
        case queued(String)
    }

    /// The captured screenshot, as marked up so far.
    @State private var image: UIImage?
    @State private var includeScreenshot: Bool
    @State private var note = ""
    @State private var category = FeedbackCategory.bug
    @State private var phase = Phase.compose
    @State private var showingMarkup = false
    @FocusState private var noteFocused: Bool

    init(center: FeedbackCenter, screenshot: Data?, context: FeedbackContext, dismiss: @escaping () -> Void) {
        self.center = center
        self.context = context
        self.dismiss = dismiss
        _image = State(initialValue: screenshot.flatMap(UIImage.init(data:)))
        _includeScreenshot = State(initialValue: screenshot != nil)
    }

    private var screenshotPNG: Data? {
        includeScreenshot ? image?.pngData() : nil
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmedNote.isEmpty || (includeScreenshot && image != nil) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .compose: compose
                case .sending: sending
                case .sent(let issue): sent(issue)
                case .queued(let reason): queued(reason)
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isComposeDirty)
        .accessibilityIdentifier("feedback-sheet")
        .fullScreenCover(isPresented: $showingMarkup) {
            if let image {
                MarkupEditor(image: image) { edited in
                    self.image = edited
                    showingMarkup = false
                } cancel: {
                    showingMarkup = false
                }
            }
        }
    }

    private var isComposeDirty: Bool {
        if case .sending = phase { return true }
        if case .compose = phase { return !trimmedNote.isEmpty }
        return false
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch phase {
        case .compose:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: dismiss)
                    .accessibilityIdentifier("feedback-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Send", action: send)
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedback-send")
            }
        case .sending:
            ToolbarItem(placement: .confirmationAction) { ProgressView() }
        case .sent, .queued:
            // Done is the prominent button in the confirmation itself.
            ToolbarItem(placement: .confirmationAction) { EmptyView() }
        }
    }

    // MARK: Compose

    private var compose: some View {
        Form {
            Section {
                TextField("Note", text: $note, prompt: Text("What happened? First line becomes the title"), axis: .vertical)
                    .lineLimit(3...10)
                    .focused($noteFocused)
                    .accessibilityIdentifier("feedback-note")
                categoryChips
            }
            Section("Screenshot") {
                screenshotSection
            }
            Section {
                shareLink(label: "Share instead")
            } footer: {
                Text("Includes app version, device, screen, trip, feed status and recent errors. Never your location.")
            }
        }
        .onAppear { noteFocused = true }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedbackCategory.allCases) { option in
                    let isSelected = option == category
                    Button { category = option } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("feedback-category-\(option.label)")
                }
            }
        }
    }

    @ViewBuilder
    private var screenshotSection: some View {
        if let image, includeScreenshot {
            HStack(alignment: .top, spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                    .accessibilityLabel("Screenshot")
                    .accessibilityIdentifier("feedback-screenshot")
                VStack(alignment: .leading, spacing: 12) {
                    Button { showingMarkup = true } label: {
                        Label("Mark up", systemImage: "pencil.tip.crop.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("feedback-markup")
                    Button(role: .destructive) { includeScreenshot = false } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("feedback-remove-screenshot")
                }
            }
        } else if image != nil {
            Button { includeScreenshot = true } label: {
                Label("Add screenshot back", systemImage: "photo")
            }
            .accessibilityIdentifier("feedback-remove-screenshot")
        } else {
            Text("No screenshot")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Results

    private var sending: some View {
        ProgressView("Sending…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("feedback-sending")
    }

    private func sent(_ issue: CreatedIssue) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Sent as #\(issue.number)")
                .font(.title2.bold())
                .accessibilityIdentifier("feedback-sent")
            Link("View issue on GitHub", destination: issue.htmlURL)
                .accessibilityIdentifier("feedback-issue-link")
            Button("Done", action: dismiss)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feedback-done")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func queued(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.up.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Saved — will send later")
                .font(.title2.bold())
                .accessibilityIdentifier("feedback-queued")
            Text(reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("feedback-queued-reason")
            shareLink(label: "Share now instead")
            Button("Done", action: dismiss)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feedback-done")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Share

    @ViewBuilder
    private func shareLink(label: String) -> some View {
        let report = FeedbackReport(note: note, category: category, context: context)
        let text = FeedbackShare.text(for: report, hasScreenshot: screenshotPNG != nil)
        let title = FeedbackIssueFormatter.title(for: report)
        Group {
            if let image, includeScreenshot {
                let preview = Image(uiImage: image)
                ShareLink(item: preview, subject: Text(title), message: Text(text), preview: SharePreview(title, image: preview)) {
                    Label(label, systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: text, subject: Text(title)) {
                    Label(label, systemImage: "square.and.arrow.up")
                }
            }
        }
        .accessibilityIdentifier("feedback-share")
    }

    // MARK: Send

    private func send() {
        let png = screenshotPNG
        let note = note
        let category = category
        phase = .sending
        Task {
            let outcome = await center.send(note: note, category: category, context: context, screenshot: png)
            switch outcome {
            case .sent(let issue):
                phase = .sent(issue)
            case .waiting(let error):
                phase = .queued(FeedbackShare.queuedReason(error))
            }
        }
    }
}

/// Text for sharing a report outside GitHub, and why a report is still queued.
enum FeedbackShare {
    static func text(for report: FeedbackReport, hasScreenshot: Bool) -> String {
        let draft = FeedbackIssueFormatter.draft(for: report, screenshotURL: nil)
        let body = hasScreenshot
            ? draft.body.replacingOccurrences(of: "_No screenshot._", with: "_Screenshot attached._")
            : draft.body
        return "\(draft.title)\n\n\(body)"
    }

    static func queuedReason(_ error: FeedbackSendError) -> String {
        switch error {
        case .noToken:
            "No GitHub token yet. Add one with the gear button next to Send feedback; it sends automatically after that."
        case .network:
            "Can't reach GitHub right now. It sends automatically when you're back online."
        default:
            "\(error.userMessage) It's saved and will be retried automatically."
        }
    }
}
