import AVFAudio

/// The watch's own microphone permission. The microphone itself is `SensorSet.microphone`.
enum MicrophonePermission {
    static var state: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .notAsked
        case .granted: .granted
        default: .denied
        }
    }

    static func request() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}
