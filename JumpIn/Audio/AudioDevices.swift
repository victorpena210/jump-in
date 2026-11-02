import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let route: AudioRoute
    var id: String { uid }
}

enum AudioDevices {
    static func all() -> [AudioDevice] {
        ids(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
            .compactMap(device)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func device(_ id: AudioDeviceID) -> AudioDevice? {
        guard uint(id, kAudioDevicePropertyDeviceIsAlive) == 1,
              let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
        let name = string(id, kAudioObjectPropertyName) ?? "Audio device"
        let inputCount = channels(id, scope: kAudioDevicePropertyScopeInput)
        let outputCount = channels(id, scope: kAudioDevicePropertyScopeOutput)
        let transport = uint(id, kAudioDevicePropertyTransportType) ?? 0
        let source = uint(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
        let terminals = ids(object: id, selector: kAudioDevicePropertyStreams,
                            scope: kAudioDevicePropertyScopeOutput).map {
            uint($0, kAudioStreamPropertyTerminalType) ?? kAudioStreamTerminalTypeUnknown
        }
        // Some built-in drivers report the active jack via data source, others via terminal.
        let headphones = terminals.contains(kAudioStreamTerminalTypeHeadphones)
            || source == fourCC("hdpn") || source == fourCC("hdph")
        let unsupported = [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                           kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeHDMI,
                           kAudioDeviceTransportTypeDisplayPort].contains(transport)
        let allowed = outputCount > 0 && AudioSafety.allowsOutput(
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn,
            isHeadphoneTerminal: headphones, isExplicitlyUnsupported: unsupported)
        let rate = sampleRate(id)
        let signature = "\(transport):\(source ?? 0):\(terminals):\(outputCount):\(rate)"
        return AudioDevice(deviceID: id, uid: uid, name: name, inputChannels: inputCount,
                           outputChannels: outputCount,
                           route: AudioRoute(deviceID: id, uid: uid, signature: signature,
                                             allowsPrivatePlayback: allowed))
    }

    static func defaultInputUID() -> String? {
        guard let id = uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
        else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioFailure.system(operation, status) }
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var result: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }

    private static func sampleRate(_ id: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result)
        return result
    }

    private static func ids(object: AudioObjectID, selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [UInt32] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        let status = result.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
        return status == noErr ? result : []
    }

    private static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

/// HAL listeners are removed with the exact same block and queue used to register them.
final class AudioHardwareObserver {
    private struct Registration {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var registrations: [Registration] = []

    init(devices: [AudioDevice], changed: @escaping () -> Void) {
        observe(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, changed: changed)
        observe(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, changed: changed)
        for device in devices {
            observe(device.deviceID, kAudioDevicePropertyDeviceIsAlive, changed: changed)
            observe(device.deviceID, kAudioDevicePropertyNominalSampleRate, changed: changed)
            observe(device.deviceID, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput, changed: changed)
            observe(device.deviceID, kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput, changed: changed)
        }
    }

    private func observe(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         changed: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
            registrations.append(Registration(object: id, address: address, block: block))
        }
    }

    deinit {
        for var item in registrations {
            AudioObjectRemovePropertyListenerBlock(item.object, &item.address, .main, item.block)
        }
    }
}
