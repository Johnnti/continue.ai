import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct Interaction: Encodable, Sendable {
    let timestamp: String
    let type: String
    let appName: String?
    let windowTitle: String?
    let x: Double?
    let y: Double?
    let elementRole: String?
    let elementLabel: String?
}

struct Capture: Encodable {
    let timestamp: String
    let idleSeconds: Double
    let displayName: String
    let displayId: UInt32
    let width: Int
    let height: Int
    let screenshotBase64: String
    let screenshotMimeType: String
    let appName: String?
    let windowTitle: String?
    let url: String?
    let focusedElementRole: String?
    let focusedElementLabel: String?
    let interactions: [Interaction]
}

struct DesktopContext: Sendable {
    let appName: String?
    let windowTitle: String?
    let url: String?
    let windowBounds: CGRect?
    let focusedElementRole: String?
    let focusedElementLabel: String?
}

enum CaptureFailure: LocalizedError {
    case permissionDenied
    case timedOut
    case emptyImage

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission was not granted. Enable it for the app running continue.ai in System Settings > Privacy & Security > Screen Recording, restart that app, and try again."
        case .timedOut:
            return "macOS did not return a screenshot within 15 seconds. Verify Screen Recording permission, then restart the app running continue.ai."
        case .emptyImage:
            return "macOS completed the screenshot request without returning an image."
        }
    }
}

final class CaptureCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func runOnce(_ action: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        action()
    }
}

func isoTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func truncated(_ value: String?, limit: Int = 160) -> String? {
    guard let value else { return nil }
    let flattened = value.replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !flattened.isEmpty else { return nil }
    return String(flattened.prefix(limit))
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString, limit: Int = 160) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return truncated(value as? String, limit: limit)
}

func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func childElements(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
        return []
    }
    return value as? [AXUIElement] ?? []
}

func privacySafeURL(_ value: String) -> String? {
    guard let parsed = URL(string: value), parsed.scheme == "http" || parsed.scheme == "https",
          var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) else { return nil }
    components.user = nil
    components.password = nil
    components.query = nil
    components.fragment = nil
    return components.string
}

func browserURL(processIdentifier: pid_t, appName: String?) -> String? {
    let supportedBrowsers = ["safari", "chrome", "chromium", "edge", "brave", "arc", "firefox", "opera"]
    guard let normalizedAppName = appName?.lowercased(),
          supportedBrowsers.contains(where: normalizedAppName.contains) else { return nil }

    let application = AXUIElementCreateApplication(processIdentifier)
    guard let window = elementAttribute(application, kAXFocusedWindowAttribute as CFString) else { return nil }
    var pending: [(element: AXUIElement, depth: Int)] = [(window, 0)]
    var visited = 0
    while let current = pending.popLast(), visited < 500 {
        visited += 1
        let role = stringAttribute(current.element, kAXRoleAttribute as CFString)
        if role == (kAXTextFieldRole as String) || role == (kAXComboBoxRole as String) {
            let label = [
                stringAttribute(current.element, kAXTitleAttribute as CFString),
                stringAttribute(current.element, kAXDescriptionAttribute as CFString),
                stringAttribute(current.element, kAXHelpAttribute as CFString)
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            let isAddressControl = ["address", "location", "url", "search bar"].contains(where: label.contains)
            if isAddressControl,
               let value = stringAttribute(current.element, kAXValueAttribute as CFString, limit: 2_048),
               let safeURL = privacySafeURL(value) {
                return safeURL
            }
        }
        if current.depth < 9 {
            pending.append(contentsOf: childElements(current.element).map { ($0, current.depth + 1) })
        }
    }
    return nil
}

func roleAndLabel(for element: AXUIElement?) -> (String?, String?) {
    guard let element else { return (nil, nil) }
    let role = stringAttribute(element, kAXRoleAttribute as CFString)
    // Avoid text-field values: control names add context without collecting typed content.
    let label = stringAttribute(element, kAXTitleAttribute as CFString)
        ?? stringAttribute(element, kAXDescriptionAttribute as CFString)
        ?? stringAttribute(element, kAXHelpAttribute as CFString)
    return (role, label)
}

func focusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func element(at point: CGPoint) -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var result: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &result) == .success else {
        return nil
    }
    return result
}

func frontmostContext() -> DesktopContext {
    let application = NSWorkspace.shared.frontmostApplication
    let appName = truncated(application?.localizedName)
    var windowTitle: String?
    var url: String?
    var windowBounds: CGRect?
    if let pid = application?.processIdentifier,
       let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
        if let frontWindow = windows.first(where: { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                && (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }) {
            windowTitle = truncated(frontWindow[kCGWindowName as String] as? String)
            if let bounds = frontWindow[kCGWindowBounds as String] as? [String: Any] {
                windowBounds = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            }
        }
        url = browserURL(processIdentifier: pid, appName: appName)
    }
    let (role, label) = roleAndLabel(for: focusedElement())
    return DesktopContext(
        appName: appName,
        windowTitle: windowTitle,
        url: url,
        windowBounds: windowBounds,
        focusedElementRole: role,
        focusedElementLabel: label
    )
}

func captureDisplay(for context: DesktopContext, from displays: [SCDisplay]) -> SCDisplay? {
    if let windowBounds = context.windowBounds {
        var displayIds = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        if CGGetDisplaysWithRect(windowBounds, UInt32(displayIds.count), &displayIds, &displayCount) == .success {
            let bestId = displayIds.prefix(Int(displayCount)).max { left, right in
                let leftIntersection = CGDisplayBounds(left).intersection(windowBounds)
                let rightIntersection = CGDisplayBounds(right).intersection(windowBounds)
                return leftIntersection.width * leftIntersection.height < rightIntersection.width * rightIntersection.height
            }
            if let bestId, let display = displays.first(where: { $0.displayID == bestId }) {
                return display
            }
        }
    }

    if let cursor = CGEvent(source: nil)?.location {
        var displayId: CGDirectDisplayID = 0
        var displayCount: UInt32 = 0
        if CGGetDisplaysWithPoint(cursor, 1, &displayId, &displayCount) == .success,
           displayCount > 0,
           let display = displays.first(where: { $0.displayID == displayId }) {
            return display
        }
    }

    let mainDisplayId = CGMainDisplayID()
    return displays.first(where: { $0.displayID == mainDisplayId }) ?? displays.first
}

func captureConfiguration(for display: SCDisplay, maxWidth: Int) -> SCStreamConfiguration {
    let scale = min(1, Double(maxWidth) / Double(display.width))
    let configuration = SCStreamConfiguration()
    configuration.showsCursor = false
    configuration.width = max(1, Int(Double(display.width) * scale))
    configuration.height = max(1, Int(Double(display.height) * scale))
    return configuration
}

final class ActivityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Interaction] = []
    private var eventMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    @MainActor
    init() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.record(event)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.append(Interaction(
                timestamp: isoTimestamp(), type: "app_switch", appName: truncated(app?.localizedName),
                windowTitle: nil, x: nil, y: nil, elementRole: nil, elementLabel: nil
            ))
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func record(_ event: NSEvent) {
        let context = frontmostContext()
        if event.type == .scrollWheel {
            append(Interaction(
                timestamp: isoTimestamp(), type: "scroll", appName: context.appName,
                windowTitle: context.windowTitle, x: nil, y: nil,
                elementRole: context.focusedElementRole, elementLabel: context.focusedElementLabel
            ))
            return
        }
        let point = event.cgEvent?.location ?? NSEvent.mouseLocation
        let (role, label) = roleAndLabel(for: element(at: point))
        append(Interaction(
            timestamp: isoTimestamp(), type: "click", appName: context.appName,
            windowTitle: context.windowTitle, x: point.x, y: point.y,
            elementRole: role, elementLabel: label
        ))
    }

    private func append(_ interaction: Interaction) {
        lock.lock()
        pending.append(interaction)
        if pending.count > 100 { pending.removeFirst(pending.count - 100) }
        lock.unlock()
    }

    func drain() -> [Interaction] {
        lock.lock()
        defer { lock.unlock() }
        let result = pending
        pending.removeAll(keepingCapacity: true)
        return result
    }
}

func jpegData(for image: CGImage, quality: Double) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw NSError(domain: "ContinueScreenCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create JPEG encoder"])
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "ContinueScreenCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode screenshot"])
    }
    return data as Data
}

func positiveIntegerEnvironment(_ key: String, fallback: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[key], let value = Int(raw), value > 0 else { return fallback }
    return value
}

func secondsSinceLastUserInput() -> Double {
    // Quartz defines kCGAnyInputEventType as the all-bits-set event type. This
    // returns only an elapsed duration; it does not expose key or pointer data.
    guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else { return 0 }
    let idleSeconds = CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: anyInputEvent
    )
    return idleSeconds.isFinite ? max(0, idleSeconds) : 0
}

func captureImage(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration
) async throws -> CGImage {
    try await withCheckedThrowingContinuation { continuation in
        let gate = CaptureCompletionGate()
        let timeout = DispatchWorkItem {
            gate.runOnce { continuation.resume(throwing: CaptureFailure.timedOut) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)

        SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
            gate.runOnce {
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CaptureFailure.emptyImage)
                }
            }
        }
    }
}

@main
struct ContinueScreenCapture {
    @MainActor
    static func main() async {
        do {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw CaptureFailure.permissionDenied
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else {
                throw NSError(domain: "ContinueScreenCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "No display is available. Grant Screen Recording permission in System Settings and retry."])
            }

            let intervalSeconds = positiveIntegerEnvironment("CONTINUE_CAPTURE_INTERVAL_SECONDS", fallback: 30)
            let maxWidth = positiveIntegerEnvironment("CONTINUE_CAPTURE_MAX_WIDTH", fallback: 1440)
            let quality = Double(ProcessInfo.processInfo.environment["CONTINUE_CAPTURE_JPEG_QUALITY"] ?? "0.55") ?? 0.55

            let activityMonitor = ActivityMonitor()
            let encoder = JSONEncoder()
            while !Task.isCancelled {
                let context = frontmostContext()
                guard let display = captureDisplay(for: context, from: content.displays) else {
                    throw NSError(domain: "ContinueScreenCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "No active display is available."])
                }
                let configuration = captureConfiguration(for: display, maxWidth: maxWidth)
                let image = try await captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration
                )
                let jpeg = try jpegData(for: image, quality: quality)
                let capture = Capture(
                    timestamp: isoTimestamp(), idleSeconds: secondsSinceLastUserInput(),
                    displayName: "Display \(display.displayID)", displayId: display.displayID,
                    width: image.width, height: image.height,
                    screenshotBase64: jpeg.base64EncodedString(), screenshotMimeType: "image/jpeg",
                    appName: context.appName, windowTitle: context.windowTitle,
                    url: context.url,
                    focusedElementRole: context.focusedElementRole, focusedElementLabel: context.focusedElementLabel,
                    interactions: activityMonitor.drain()
                )
                FileHandle.standardOutput.write(try encoder.encode(capture))
                FileHandle.standardOutput.write(Data([0x0A]))
                fflush(stdout)
                try await Task.sleep(for: .seconds(intervalSeconds))
            }
        } catch {
            FileHandle.standardError.write(Data("ScreenCaptureKit error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
