import AppKit
import Vision

final class ScreenOCR {
    static let shared = ScreenOCR()

    private var window: OCRSelectionWindow?

    private init() {}

    func start(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard self.window == nil else {
                completion(nil)
                return
            }
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            guard let screen else {
                completion(nil)
                return
            }

            let window = OCRSelectionWindow(screen: screen)
            let view = OCRSelectionView(screen: screen) { [weak self, weak window] rect in
                guard let rect else {
                    window?.orderOut(nil)
                    self?.window = nil
                    completion(nil)
                    return
                }
                let selectedAt = Date()
                DispatchQueue.global(qos: .userInitiated).async {
                    let text = Self.recognizeText(in: rect, on: screen)
                    DispatchQueue.main.async {
                        let minimumFeedbackDuration: TimeInterval = 0.32
                        let elapsed = Date().timeIntervalSince(selectedAt)
                        let close = {
                            window?.orderOut(nil)
                            self?.window = nil
                            completion(text)
                        }
                        if elapsed < minimumFeedbackDuration {
                            DispatchQueue.main.asyncAfter(deadline: .now() + minimumFeedbackDuration - elapsed, execute: close)
                        } else {
                            close()
                        }
                    }
                }
            }
            window.contentView = view
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            NSCursor.crosshair.set()
        }
    }

    private static func recognizeText(in rect: CGRect, on screen: NSScreen) -> String? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let fullImage = CGDisplayCreateImage(CGDirectDisplayID(displayID.uint32Value)) else { return nil }

        let scaleX = CGFloat(fullImage.width) / screen.frame.width
        let scaleY = CGFloat(fullImage.height) / screen.frame.height
        let cropRect = CGRect(x: rect.minX * scaleX,
                              y: (screen.frame.height - rect.maxY) * scaleY,
                              width: rect.width * scaleX,
                              height: rect.height * scaleY)
            .integral
        guard cropRect.width >= 8, cropRect.height >= 8,
              let cropped = fullImage.cropping(to: cropRect) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = AppFlavor.uiLanguageIsEnglish ? ["en-US", "zh-Hans", "zh-Hant"] : ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            NSLog("Dob · OCR 失败：\(error)")
            return nil
        }
    }
}

private final class OCRSelectionWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
}

private final class OCRSelectionView: NSView {
    private let screen: NSScreen
    private let onComplete: (CGRect?) -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var confirmedRect: NSRect?
    private var isRecognizing = false

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        self.screen = screen
        self.onComplete = onComplete
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecognizing else { return }
        startPoint = event.locationInWindow
        currentPoint = startPoint
        confirmedRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isRecognizing else { return }
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !isRecognizing else { return }
        currentPoint = event.locationInWindow
        let rect = selectionRect
        guard rect.width >= 8 && rect.height >= 8 else {
            onComplete(nil)
            return
        }
        confirmedRect = rect
        isRecognizing = true
        needsDisplay = true
        onComplete(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !isRecognizing {
            onComplete(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect: NSRect
        if let confirmedRect {
            rect = confirmedRect
        } else if let startPoint, let currentPoint {
            rect = NSRect(x: min(startPoint.x, currentPoint.x),
                          y: min(startPoint.y, currentPoint.y),
                          width: abs(startPoint.x - currentPoint.x),
                          height: abs(startPoint.y - currentPoint.y))
        } else {
            return
        }

        NSColor.controlAccentColor.withAlphaComponent(isRecognizing ? 0.20 : 0.16).setFill()
        rect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = isRecognizing ? 3 : 2
        path.stroke()

        if isRecognizing {
            drawStatusPill(near: rect)
        }
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(x: min(startPoint.x, currentPoint.x),
                      y: min(startPoint.y, currentPoint.y),
                      width: abs(startPoint.x - currentPoint.x),
                      height: abs(startPoint.y - currentPoint.y))
            .intersection(CGRect(origin: .zero, size: screen.frame.size))
    }

    private func drawStatusPill(near rect: NSRect) {
        let title = AppFlavor.text("已框选，正在识别…", "Selection captured, recognizing...")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let pillSize = NSSize(width: textSize.width + 24, height: textSize.height + 12)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 8)
        if origin.y + pillSize.height > bounds.maxY {
            origin.y = rect.minY - pillSize.height - 8
        }
        origin.x = min(max(origin.x, bounds.minX + 12), bounds.maxX - pillSize.width - 12)
        origin.y = min(max(origin.y, bounds.minY + 12), bounds.maxY - pillSize.height - 12)

        let pillRect = NSRect(origin: origin, size: pillSize)
        let background = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
        background.fill()

        let textRect = NSRect(x: pillRect.minX + 12,
                              y: pillRect.minY + 6,
                              width: textSize.width,
                              height: textSize.height)
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
