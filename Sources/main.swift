import AppKit
import IOKit.ps
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var sleeping = false
    private var screenSleeping = false
    private var displayState = PowerDisplayState()
    private var usageDisplayState = PowerDisplayState()
    private var reading: PowerReading?
    private var history = PowerHistory()
    private let pane = PowerPaneController()
    private let popover = NSPopover()
    private let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Charger input")
    private let drain = NSImage(systemSymbolName: "arrow.down.right", accessibilityDescription: "Mac power use")
    private var lastExternal: Bool?
    private var loginEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        status.button?.imagePosition = .imageLeading
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        bolt?.isTemplate = true
        drain?.isTemplate = true
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = pane
        pane.onResize = { [weak self] size in self?.popover.contentSize = size }
        pane.onLogin = { [weak self] in self?.toggleLogin() }
        pane.onQuit = { NSApp.terminate(nil) }
        _ = pane.view
        popover.contentSize = pane.preferredContentSize

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if !app.sleeping && !app.screenSleeping { app.refresh() }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        refresh()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        guard !sleeping && !screenSleeping else { timer = nil; return }
        let newTimer = Timer(timeInterval: 2, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        newTimer.tolerance = 0.2
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    @objc private func timerFired() { if !sleeping && !screenSleeping { refresh() } }
    @objc private func willSleep() { sleeping = true; timer?.invalidate(); timer = nil }
    @objc private func didWake() { sleeping = false; powerbar_smc_close(); if !screenSleeping { refresh(); startTimer() } }
    @objc private func screenDidSleep() { screenSleeping = true; timer?.invalidate(); timer = nil }
    @objc private func screenDidWake() { screenSleeping = false; if !sleeping { refresh(); startTimer() } }

    fileprivate func refresh() {
        let now = Date()
        reading = PowerReading.read()
        var input: Double?
        var usage: Double?
        if let reading {
            input = displayState.value(for: reading, now: now)
            usage = usageDisplayState.value(externalPower: reading.externalPower, watts: reading.systemWatts, now: now)
            history.append(time: now, input: reading.externalPower ? input : 0, usage: usage)
            let title = PowerDisplayState.title(externalPower: reading.externalPower, input: input, usage: usage)
            if status.button?.title != title { status.button?.title = title }
            if lastExternal != reading.externalPower {
                status.button?.image = reading.externalPower ? bolt : drain
                lastExternal = reading.externalPower
            }
            func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "Updating…" }
            status.button?.toolTip = "\(reading.externalPower ? "Charger → Mac: " + watts(input) + "\n" : "")Mac power use: \(watts(usage))\nClick for details and graph"
        } else {
            status.button?.title = "— W"
            status.button?.toolTip = "Power reading unavailable"
        }
        if popover.isShown {
            pane.update(reading: reading, input: input, usage: usage, samples: history.samples, now: now,
                        loginEnabled: loginEnabled)
        }
    }

    private func showPopover() {
        guard let button = status.button else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        refresh()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            refresh()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "Keep PowerBar in a permanent location, then try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        powerbar_smc_close()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

if CommandLine.arguments.contains("--read-once") {
    if let reading = PowerReading.read() {
        print("\(reading.externalPower ? "Charger input" : "Battery draw"): \(reading.formattedWatts)")
        print("Mac use: \(reading.systemWatts.map { String(format: "%.1f W", $0) } ?? "Unavailable")")
        print("Battery net power: \(reading.batteryWatts.map { String(format: "%.1f W", $0) } ?? "Unavailable")")
    } else { fputs("Battery telemetry unavailable\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
