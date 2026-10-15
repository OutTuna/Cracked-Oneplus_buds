import AppKit
import Combine
import EncoCore

final class EarbudsModel: ObservableObject {
    @Published var connected = false
    @Published var connecting = false
    @Published var busy = false
    @Published var mode: ANCMode?
    @Published var batteries: [UInt8: BatteryEntry] = [:]
    @Published var firmware = "—"
    @Published var notice: String?
    @Published var panelOpen = false
    @Published var deviceName = "OPPO Enco Air5 Pro"
    private var transport: RFCOMMTransport?
    private var session: Session?
    private var device: DeviceProtocol?
    private var timer: Timer?
    private var generation = 0

    var connectionLabel: String { connecting ? "Connecting" : connected ? "Connected" : "Not connected" }

    func start() {
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, !self.busy else { return }
            if self.connected { self.refresh() } else if !self.connecting { self.connect() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    @objc private func willSleep() { disconnect() }
    @objc private func didWake() { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.connect() } }

    func disconnect() {
        generation += 1
        session?.cancel()
        transport?.close()
        device = nil
        session = nil
        transport = nil
        connected = false
        connecting = false
        busy = false
        mode = nil
        batteries = [:]
    }

    func connect() {
        guard !connecting, !connected else { return }
        disconnect()
        let candidates = RFCOMMTransport.pairedDevices().filter { $0.name.localizedCaseInsensitiveContains("Enco Air5 Pro") }
        guard let target = candidates.first(where: \.connected) ?? candidates.first else {
            notice = "Connect your Enco Air5 Pro in Bluetooth settings."
            return
        }
        let transport = RFCOMMTransport()
        let session = Session()
        let device = DeviceProtocol(session: session)
        self.transport = transport
        self.session = session
        self.device = device
        deviceName = target.name
        connecting = true
        busy = true
        notice = nil
        let token = generation
        let failure: (Error) -> Void = { [weak self] error in
            guard let self, self.generation == token else { return }
            if case SessionError.rejected = error, self.connected {
                self.busy = false
                self.notice = "The earbuds couldn’t apply this change. Try again."
            } else {
                self.disconnect()
                self.notice = "Connection interrupted. Open the case or disconnect HeyMelody, then retry."
            }
        }
        transport.onError = failure
        session.onError = failure
        device.onError = failure
        device.onStateChanged = { [weak self, weak device] in
            guard let self, self.generation == token, let device else { return }
            for entry in device.battery { self.batteries[entry.deviceType] = entry }
            self.mode = device.noiseState?.capturedMode
        }
        session.send = { [weak transport] bytes in
            guard let transport else { throw TransportError.unavailable("Disconnected") }
            try transport.write(bytes)
        }
        transport.onData = { [weak session] in session?.receive($0) }
        transport.onOpen = { [weak self, weak device] in
            guard let self, self.generation == token, let device else { return }
            device.initialize { [weak self, weak device] in
                guard let self, self.generation == token, let device else { return }
                device.readBattery { [weak self, weak device] _ in
                    guard let self, self.generation == token, let device else { return }
                    device.readNoiseState { [weak self, weak device] _ in
                        guard let self, self.generation == token, let device else { return }
                        device.readVersion { [weak self] components in
                            guard let self, self.generation == token else { return }
                            self.firmware = components.filter { $0.versionType == "2" }.map(\.value).joined(separator: ".")
                            self.connected = true
                            self.connecting = false
                            self.busy = false
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self, self.generation == token, self.connecting else { return }
            failure(TransportError.unavailable("Connection timeout"))
        }
        transport.open(address: target.address)
    }

    func refresh() {
        guard connected, !busy, let device else { return }
        busy = true
        let token = generation
        device.readBattery { [weak self, weak device] _ in
            guard let self, self.generation == token, let device else { return }
            device.readNoiseState { [weak self] _ in
                guard let self, self.generation == token else { return }
                self.busy = false
            }
        }
    }

    func select(_ mode: ANCMode) {
        guard connected, !busy, let device else { return }
        busy = true
        notice = nil
        let token = generation
        device.setANC(mode) { [weak self] state in
            guard let self, self.generation == token else { return }
            self.mode = state.capturedMode
            self.busy = false
            if state.capturedMode != mode { self.notice = "The earbuds reported a different listening mode." }
        }
    }

    func stop() { timer?.invalidate(); disconnect() }
}
