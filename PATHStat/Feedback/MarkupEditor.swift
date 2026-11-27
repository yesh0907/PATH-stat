import PencilKit
import SwiftUI
import UIKit

/// Full-screen red-pen markup over the screenshot (finger or Pencil). Done flattens the
/// drawing into the image.
struct MarkupEditor: View {
    let image: UIImage
    let done: (UIImage) -> Void
    let cancel: () -> Void

    @State private var canvas = CanvasHandle()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let size = Self.fit(image.size, in: proxy.size)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                    MarkupCanvas(handle: canvas)
                        .frame(width: size.width, height: size.height)
                        .accessibilityIdentifier("feedback-markup-canvas")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black)
            .navigationTitle("Mark up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .accessibilityIdentifier("feedback-markup-cancel")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { canvas.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .accessibilityIdentifier("feedback-markup-undo")
                    Spacer()
                    Button("Clear", role: .destructive) { canvas.clear() }
                        .accessibilityIdentifier("feedback-markup-clear")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { done(canvas.composite(onto: image)) }
                        .accessibilityIdentifier("feedback-markup-done")
                }
            }
        }
    }

    /// Aspect-fit `size` into `bounds`.
    static func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Lets the SwiftUI toolbar drive the `PKCanvasView`.
@MainActor
final class CanvasHandle {
    weak var view: PKCanvasView?

    func undo() {
        guard let view, !view.drawing.strokes.isEmpty else { return }
        var drawing = view.drawing
        drawing.strokes.removeLast()
        view.drawing = drawing
    }

    func clear() {
        view?.drawing = PKDrawing()
    }

    /// The image with the drawing on top, at the image's own size.
    func composite(onto image: UIImage) -> UIImage {
        guard let view, !view.drawing.strokes.isEmpty, view.bounds.width > 0 else { return image }
        let canvasBounds = view.bounds
        let scale = image.size.width / canvasBounds.width * image.scale
        let strokes = view.drawing.image(from: canvasBounds, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            strokes.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private struct MarkupCanvas: UIViewRepresentable {
    let handle: CanvasHandle

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.tool = PKInkingTool(.pen, color: .systemRed, width: 6)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isScrollEnabled = false
        view.overrideUserInterfaceStyle = .light   // keep the ink red, not inverted in Dark Mode
        handle.view = view
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {}
}
