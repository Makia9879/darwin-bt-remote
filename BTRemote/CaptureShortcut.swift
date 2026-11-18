#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

struct CaptureShortcut: Codable, Equatable {
    let code: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let standard = Self(code: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | shiftKey), keyLabel: "R")

    static func mask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
            .reduce(0) { $0 | (flags.contains($1.0) ? UInt32($1.1) : 0) }
    }

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }

    var reservedBySystem: Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let entries = list?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains {
            $0[kHISymbolicHotKeyEnabled] as? Bool == true && $0[kHISymbolicHotKeyCode] as? UInt32 == code &&
                $0[kHISymbolicHotKeyModifiers] as? UInt32 == modifiers
        }
    }
}

@MainActor
final class CaptureHotKey: ObservableObject {
    static let shared = CaptureHotKey()
    private static let storageKey = "captureShortcut"
    private static let signature: UInt32 = 0x4254524D // BTRM
    @Published private(set) var shortcut: CaptureShortcut
    @Published private(set) var available = false
    var beginCapture: (() -> Void)?
    var reselect: (() -> Void)?
    private var registration: EventHotKeyRef?
    private var serial: UInt32 = 0
    private var pressedID: UInt32?
    private var suspended = false
    private var handler: EventHandlerRef?

    private init() {
        shortcut = UserDefaults.standard.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(CaptureShortcut.self, from: $0) } ?? .standard
        var types = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout.size(ofValue: id), nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            return MainActor.assumeIsolated {
                let manager = CaptureHotKey.shared
                guard !manager.suspended, id.signature == CaptureHotKey.signature, id.id == manager.serial else { return OSStatus(eventNotHandledErr) }
                // One toggle per physical press, even if the key repeats. Start capture only
                // after the activation key is up so the tap cannot interpret it as an exit.
                if pressed { manager.pressedID = id.id; return noErr }
                guard manager.pressedID == id.id else { return noErr }
                manager.pressedID = nil
                if let reselect = manager.reselect { reselect() } else { manager.beginCapture?() }
                return noErr
            }
        }, types.count, &types, nil, &handler)
        if status == noErr { _ = install(shortcut) }
    }

    /// While remote, the input tap exclusively owns the exit shortcuts.
    func suspendForCapture() {
        suspended = true
        pressedID = nil
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }

    func resumeLocalShortcut() {
        guard suspended else { return }
        suspended = false
        available = false
        _ = install(shortcut)
    }

    func install(_ candidate: CaptureShortcut) -> Bool {
        guard !suspended else { return false }
        if available, shortcut.code == candidate.code, shortcut.modifiers == candidate.modifiers { return true }
        guard handler != nil, !candidate.reservedBySystem else { return false }
        var next: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: serial &+ 1)
        guard RegisterEventHotKey(candidate.code, candidate.modifiers, id, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &next) == noErr else { return false }
        if let registration { UnregisterEventHotKey(registration) }
        registration = next
        serial = id.id
        shortcut = candidate
        available = true
        UserDefaults.standard.set(try? JSONEncoder().encode(candidate), forKey: Self.storageKey)
        return true
    }

    func reset() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        available = false
        shortcut = .standard
        _ = install(.standard)
    }
}

/// While the field is active, intercept the chord before another registered hotkey consumes it.
/// Without capture permission the recorder still accepts ordinary in-window key events.
@MainActor
private final class RecordingTap {
    private var port: CFMachPort?
    private let record: (NSEvent) -> Void

    init?(record: @escaping (NSEvent) -> Void) {
        self.record = record
        guard AccessibilityPermission.isTrusted,
              let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: 1 << CGEventType.keyDown.rawValue, callback: { _, type, event, context in
                  guard type == .keyDown, let context, let input = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
                  let recorder = Unmanaged<RecordingTap>.fromOpaque(context).takeUnretainedValue()
                  let consumed = MainActor.assumeIsolated {
                      guard NSApp.isActive, NSApp.keyWindow != nil else { return false }
                      if !input.isARepeat { recorder.record(input) }
                      return true
                  }
                  return consumed ? nil : Unmanaged.passUnretained(event)
              }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let port { CFMachPortInvalidate(port) }
        port = nil
    }
}

struct CaptureShortcutRow: View {
    @ObservedObject private var hotKey = CaptureHotKey.shared
    @State private var monitor: Any?
    @State private var recordingTap: RecordingTap?
    @State private var symbolicMode: UnsafeMutableRawPointer?
    @State private var message: LocalizedStringKey?
    @State private var flash = false
    @State private var attempt = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Switch keyboard and mouse control")
                Spacer()
                Button { monitor == nil ? begin() : finish() } label: {
                    if monitor != nil { Text("Press shortcut…") } else { Text(verbatim: hotKey.shortcut.label) }
                }
                .focused($focused)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(flash ? Color.red : .clear, lineWidth: 2))
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            else if !hotKey.available { Text("Shortcut unavailable. Choose another combination.").font(.caption).foregroundStyle(.red) }
            else if monitor != nil { Text("Press Esc to cancel.").font(.caption).foregroundStyle(.secondary) }
        }
        .onDisappear { finish() }
        .onChange(of: focused) { if !$0 { finish() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in if monitor != nil { finish() } }
        .task(id: attempt) {
            guard attempt > 0 else { return }
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            flash = false
        }
    }

    private func begin() {
        focused = true
        message = nil
        symbolicMode = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabledExceptUniversalAccess))
        hotKey.reselect = { finish() }
        recordingTap = RecordingTap(record: record)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if !event.isARepeat { record(event) }
            }
            return nil
        }
    }

    private func finish() {
        guard let monitor else { return }
        recordingTap?.stop()
        recordingTap = nil
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        if let symbolicMode { PopSymbolicHotKeyMode(symbolicMode) }
        symbolicMode = nil
        hotKey.reselect = nil
        focused = false
        message = nil
        flash = false
    }

    private func record(_ event: NSEvent) {
        let mods = CaptureShortcut.mask(event.modifierFlags)
        if event.keyCode == kVK_Escape, mods == 0 { finish(); return }
        let chars = event.characters(byApplyingModifiers: []) ?? ""
        let isFunctionKey = chars.unicodeScalars.first.map { (0xF704...0xF726).contains($0.value) } ?? false
        guard mods & UInt32(controlKey | cmdKey | optionKey) != 0 || isFunctionKey else {
            reject("Include Control, Option, or Command, or use a function key."); return
        }
        let key: String
        if isFunctionKey, let scalar = chars.unicodeScalars.first { key = "F\(scalar.value - 0xF704 + 1)" }
        else if let name = [" ": "Space", "\r": "↩", "\t": "⇥", "\u{1b}": "⎋", "\u{7f}": "⌫", "\u{f700}": "↑", "\u{f701}": "↓", "\u{f702}": "←", "\u{f703}": "→"][chars] { key = name }
        else if chars.count == 1, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse }) { key = chars.uppercased() }
        else { reject("Choose a letter, number, or function key."); return }
        let candidate = CaptureShortcut(code: UInt32(event.keyCode), modifiers: mods, keyLabel: key)
        guard mods & UInt32(controlKey | optionKey) != UInt32(controlKey | optionKey),
              !menuConflict(NSApp.mainMenu, chars: chars, mods: mods), hotKey.install(candidate) else {
            reject("This shortcut conflicts with another action. Choose a different combination."); return
        }
        finish()
    }

    private func menuConflict(_ menu: NSMenu?, chars: String, mods: UInt32) -> Bool {
        menu?.items.contains { item in
            (!item.keyEquivalent.isEmpty && item.keyEquivalent.lowercased() == chars.lowercased() && CaptureShortcut.mask(item.keyEquivalentModifierMask) == mods) || menuConflict(item.submenu, chars: chars, mods: mods)
        } ?? false
    }

    private func reject(_ reason: LocalizedStringKey) {
        message = reason
        flash = true
        attempt += 1
    }
}
#endif
