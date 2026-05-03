import AppKit
import CoreImage
import CoreGraphics
import Foundation
import IOKit
import MetalKit
import os

private let logger = Logger(subsystem: "app.glowgoblin", category: "runtime")

@MainActor
private enum AppRetention {
    static let delegate = GlowGoblinAppDelegate()
}

@main
enum GlowGoblinMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = AppRetention.delegate
        app.run()
    }
}

@MainActor
final class GlowGoblinAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: XDRBoostController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = XDRBoostController()
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
final class XDRBoostController {
    private var triggerWindows: [CGDirectDisplayID: HDRTriggerWindowController] = [:]
    private var baselineTables: [CGDirectDisplayID: GammaTable] = [:]
    private var readyDisplays = Set<CGDirectDisplayID>()
    private var lastAppliedFactors: [CGDirectDisplayID: Float] = [:]
    private var notReadySince: [CGDirectDisplayID: Date] = [:]
    private var pollTimer: Timer?
    private var lastScreenRefresh = Date.distantPast
    private var pendingScreenRefresh = false
    private var lastBacklightLevel: Float?
    private var displayDecisionPauseUntil = Date.distantPast
    private var boostSuspendedForBrightnessMotion = false
    private var boostEnabledByBacklight = false

    private let hdrReadyThreshold: CGFloat = 1.05
    private let gammaRestoreDelay: TimeInterval = 8
    private let maxGammaFactor: Float = 1.59
    private let boostEnableBacklightThreshold: Float = 0.72
    private let boostDisableBacklightThreshold: Float = 0.66
    private let brightnessMotionThreshold: Float = 0.002
    private let brightnessSettleDelay: TimeInterval = 1.25

    func start() {
        CGDisplayRestoreColorSyncSettings()
        installObservers()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
        logger.info("GlowGoblin started")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        triggerWindows.values.forEach { $0.tearDown() }
        triggerWindows.removeAll()
        restoreGammaTables()
        readyDisplays.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("GlowGoblin stopped")
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWoke),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screenConfigurationChanged() {
        pendingScreenRefresh = true
    }

    @objc private func systemWoke() {
        refreshScreens()
    }

    @objc private func screensWoke() {
        refreshScreens()
    }

    private func tick() {
        let now = Date()
        updateBoostActivation()
        updateBrightnessMotion(now: now)

        guard boostEnabledByBacklight else {
            deactivateBoost()
            return
        }

        if now < displayDecisionPauseUntil {
            return
        }

        if boostSuspendedForBrightnessMotion {
            boostSuspendedForBrightnessMotion = false
            triggerWindows.values.forEach { $0.show() }
            lastAppliedFactors.removeAll()
        }

        if triggerWindows.isEmpty || pendingScreenRefresh || now.timeIntervalSince(lastScreenRefresh) > 2.0 {
            refreshScreens()
        }
        updateReadiness()
        applyBoost()
    }

    private func updateBoostActivation() {
        guard let backlight = BuiltInBacklight.rawLevel() else {
            boostEnabledByBacklight = false
            return
        }

        if boostEnabledByBacklight {
            boostEnabledByBacklight = backlight >= boostDisableBacklightThreshold
        } else {
            boostEnabledByBacklight = backlight >= boostEnableBacklightThreshold
        }
    }

    private func deactivateBoost() {
        guard !triggerWindows.isEmpty || !baselineTables.isEmpty || !readyDisplays.isEmpty else { return }

        triggerWindows.values.forEach { $0.tearDown() }
        triggerWindows.removeAll()
        restoreGammaTables()
        readyDisplays.removeAll()
        boostSuspendedForBrightnessMotion = false
        displayDecisionPauseUntil = Date.distantPast
    }

    private func refreshScreens() {
        pendingScreenRefresh = false
        lastScreenRefresh = Date()
        let screens = supportedScreens()
        let activeIDs = Set(screens.compactMap(\.displayID))

        for displayID in triggerWindows.keys where !activeIDs.contains(displayID) {
            triggerWindows[displayID]?.tearDown()
            triggerWindows.removeValue(forKey: displayID)
            baselineTables[displayID]?.restore(to: displayID)
            baselineTables.removeValue(forKey: displayID)
            readyDisplays.remove(displayID)
            lastAppliedFactors.removeValue(forKey: displayID)
            notReadySince.removeValue(forKey: displayID)
        }

        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            if triggerWindows[displayID] == nil {
                triggerWindows[displayID] = HDRTriggerWindowController(screen: screen)
                triggerWindows[displayID]?.show()
            } else {
                triggerWindows[displayID]?.update(screen: screen)
            }

            if baselineTables[displayID] == nil {
                baselineTables[displayID] = GammaTable.capture(displayID: displayID)
            }
        }
    }

    private func updateReadiness() {
        for screen in supportedScreens() {
            guard let displayID = screen.displayID else { continue }
            if screen.maximumExtendedDynamicRangeColorComponentValue > hdrReadyThreshold {
                readyDisplays.insert(displayID)
                notReadySince.removeValue(forKey: displayID)
            } else {
                readyDisplays.remove(displayID)
                triggerWindows[displayID]?.redraw()

                let firstDrop = notReadySince[displayID] ?? Date()
                notReadySince[displayID] = firstDrop
                if Date().timeIntervalSince(firstDrop) > gammaRestoreDelay {
                    baselineTables[displayID]?.restore(to: displayID)
                    lastAppliedFactors.removeValue(forKey: displayID)
                }
            }
        }
    }

    private func applyBoost() {
        for screen in supportedScreens() {
            guard
                let displayID = screen.displayID,
                readyDisplays.contains(displayID),
                let baseline = baselineTables[displayID]
            else { continue }

            let factor = gammaFactor(for: screen)
            if let last = lastAppliedFactors[displayID], abs(last - factor) < 0.003 {
                continue
            }
            baseline.apply(to: displayID, factor: factor)
            lastAppliedFactors[displayID] = factor
        }
    }

    private func gammaFactor(for screen: NSScreen) -> Float {
        let edr = Float(max(1.0, min(4.0, screen.maximumExtendedDynamicRangeColorComponentValue)))
        return min(maxGammaFactor, 1.0 + ((maxGammaFactor - 1.0) * edr / 4.0))
    }

    private func updateBrightnessMotion(now: Date) {
        guard let current = BuiltInBacklight.rawLevel() else { return }
        defer { lastBacklightLevel = current }

        guard let previous = lastBacklightLevel else { return }
        if abs(current - previous) > brightnessMotionThreshold {
            suspendBoostForBrightnessMotion(until: now.addingTimeInterval(brightnessSettleDelay))
        }
    }

    private func suspendBoostForBrightnessMotion(until pauseUntil: Date) {
        displayDecisionPauseUntil = pauseUntil
        guard !boostSuspendedForBrightnessMotion else { return }

        triggerWindows.values.forEach { $0.hide() }
        for screen in supportedScreens() {
            guard let displayID = screen.displayID else { continue }
            baselineTables[displayID]?.restore(to: displayID)
            lastAppliedFactors.removeValue(forKey: displayID)
        }
        boostSuspendedForBrightnessMotion = true
    }

    private func supportedScreens() -> [NSScreen] {
        NSScreen.screens.filter { screen in
            guard let displayID = screen.displayID else { return false }
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let looksLikeAppleXDR = screen.localizedName.localizedCaseInsensitiveContains("XDR")
            let supportsEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05
            return supportsEDR && (isBuiltIn || looksLikeAppleXDR)
        }
    }

    private func restoreGammaTables() {
        for (displayID, table) in baselineTables {
            table.restore(to: displayID)
        }
        baselineTables.removeAll()
        lastAppliedFactors.removeAll()
        notReadySince.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}

enum BuiltInBacklight {
    static func rawLevel() -> Float? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let parameters = IORegistryEntryCreateCFProperty(
                service,
                "IODisplayParameters" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
            let raw = parameters["rawBrightness"] as? [String: Any],
            let value = number(raw["value"]),
            let upper = number(raw["max"]),
            upper > 0
        else {
            return nil
        }

        return Swift.max(0, Swift.min(1, value / upper))
    }

    private static func number(_ value: Any?) -> Float? {
        switch value {
        case let value as NSNumber:
            value.floatValue
        case let value as Int:
            Float(value)
        case let value as Double:
            Float(value)
        case let value as Float:
            value
        default:
            nil
        }
    }
}

final class GammaTable {
    private static let tableSize: UInt32 = 256

    private let red: [CGGammaValue]
    private let green: [CGGammaValue]
    private let blue: [CGGammaValue]

    private init(red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    static func capture(displayID: CGDirectDisplayID) -> GammaTable? {
        var red = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var green = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var blue = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var count: UInt32 = 0

        let result = CGGetDisplayTransferByTable(displayID, tableSize, &red, &green, &blue, &count)
        guard result == .success, count > 0 else {
            logger.error("Failed to capture gamma table for display \(displayID)")
            return nil
        }

        return GammaTable(red: red, green: green, blue: blue)
    }

    func apply(to displayID: CGDirectDisplayID, factor: Float) {
        var adjustedRed = red
        var adjustedGreen = green
        var adjustedBlue = blue

        for index in adjustedRed.indices {
            adjustedRed[index] = red[index] * factor
            adjustedGreen[index] = green[index] * factor
            adjustedBlue[index] = blue[index] * factor
        }

        let result = CGSetDisplayTransferByTable(
            displayID,
            Self.tableSize,
            &adjustedRed,
            &adjustedGreen,
            &adjustedBlue
        )

        if result != .success {
            logger.error("Failed to apply gamma factor \(factor, privacy: .public) to display \(displayID)")
        }
    }

    func restore(to displayID: CGDirectDisplayID) {
        var restoredRed = red
        var restoredGreen = green
        var restoredBlue = blue
        _ = CGSetDisplayTransferByTable(
            displayID,
            Self.tableSize,
            &restoredRed,
            &restoredGreen,
            &restoredBlue
        )
    }
}

@MainActor
final class HDRTriggerWindowController: NSWindowController, NSWindowDelegate {
    private var targetScreen: NSScreen

    init(screen: NSScreen) {
        self.targetScreen = screen
        let window = HDRTriggerWindow()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window = window as? HDRTriggerWindow else { return }
        window.setFrame(triggerFrame(for: targetScreen), display: true)
        window.orderFrontRegardless()
        window.installTriggerView()
        window.triggerView?.redraw()
    }

    func update(screen: NSScreen) {
        targetScreen = screen
        guard let window = window as? HDRTriggerWindow else { return }
        let frame = triggerFrame(for: screen)
        if window.frame != frame {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            window.triggerView?.redraw()
        }
    }

    func redraw() {
        guard let window = window as? HDRTriggerWindow else { return }
        window.orderFrontRegardless()
        window.triggerView?.redraw()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func tearDown() {
        window?.close()
    }

    func windowDidMove(_ notification: Notification) {
        window?.setFrame(triggerFrame(for: targetScreen), display: true)
    }

    private func triggerFrame(for screen: NSScreen) -> NSRect {
        screen.frame
    }
}

@MainActor
final class HDRTriggerWindow: NSWindow {
    var triggerView: HDRTriggerView?

    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        level = .mainMenu
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        canHide = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 1
    }

    func installTriggerView() {
        if triggerView == nil {
            let view = HDRTriggerView(frame: contentView?.bounds ?? frame)
            view.autoresizingMask = [.width, .height]
            triggerView = view
            contentView = view
        }
    }
}

@MainActor
final class HDRTriggerView: MTKView, MTKViewDelegate {
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    private let queue: MTLCommandQueue?
    private var renderContext: CIContext?
    private var image: CIImage?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        queue = metalDevice?.makeCommandQueue()
        super.init(frame: frameRect, device: metalDevice)
        configure()
    }

    required init(coder: NSCoder) {
        queue = nil
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        framebufferOnly = false
        autoResizeDrawable = true
        colorPixelFormat = .rgba16Float
        colorspace = colorSpace
        preferredFramesPerSecond = 10
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = self

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.isOpaque = false
            metalLayer.compositingFilter = "multiplyBlendMode"
        }

        if let queue {
            renderContext = CIContext(mtlCommandQueue: queue, options: [
                .name: "GlowGoblinOverlay",
                .workingColorSpace: colorSpace ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                .workingFormat: CIFormat.RGBAf,
                .cacheIntermediates: true,
                .allowLowPower: false
            ])
        }

        let workingSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        guard
            let color = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0, colorSpace: workingSpace),
            let filter = CIFilter(name: "CIColorControls")
        else {
            image = CIImage(color: .white)
            return
        }

        filter.setValue(CIImage(color: color), forKey: kCIInputImageKey)
        filter.setValue(1.0, forKey: kCIInputContrastKey)
        filter.setValue(1.0, forKey: kCIInputBrightnessKey)
        image = filter.outputImage ?? CIImage(color: color)
    }

    func redraw() {
        needsDisplay = true
        displayIfNeeded()
    }

    func draw(in view: MTKView) {
        guard
            let queue,
            let renderContext,
            let image,
            let renderColorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
            let commandBuffer = queue.makeCommandBuffer(),
            let drawable = currentDrawable
        else {
            return
        }

        let bounds = CGRect(origin: .zero, size: drawableSize)
        renderContext.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: renderColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
