import AVFAudio
import Observation
import Speech

@MainActor @Observable final class VoiceCapture {
    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var transcript = ""
    private(set) var errorText: String?
    private(set) var completionCount = 0

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var completionFallback: Task<Void, Never>?
    private var sessionID = UUID()
    private(set) var isFinishing = false

    func start() async {
        guard !isRecording && !isPreparing && !isFinishing else { return }
        let startedSession = UUID()
        sessionID = startedSession
        isPreparing = true
        defer { if sessionID == startedSession { isPreparing = false } }
        errorText = nil
        transcript = ""

        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == startedSession else { return }
        guard authorization == .authorized else {
            errorText = "Allow Speech Recognition for \(AppBrand.name) in Settings to dictate a task."
            return
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard sessionID == startedSession else { return }
        guard microphoneAllowed else {
            errorText = "Allow Microphone access for \(AppBrand.name) in Settings to dictate a task."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            errorText = "Speech recognition isn't available for this language right now. You can still type your request."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            errorText = "On-device speech recognition isn't available for this language. You can use keyboard dictation or type instead."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            self.engine = engine
            self.request = request
            engine.prepare()
            try engine.start()
            guard sessionID == startedSession else { cancel(); return }
            self.recognizer = recognizer
            isRecording = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == startedSession else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if let error, self.isRecording {
                        self.errorText = error.localizedDescription
                        self.cancel()
                    } else if error != nil && self.isFinishing {
                        self.complete()
                    } else if result?.isFinal == true {
                        if self.isRecording {
                            self.isFinishing = true
                            self.stopCapture()
                        }
                        self.complete()
                    }
                }
            }
        } catch {
            cancel()
            errorText = "Couldn't start the microphone: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRecording else { return }
        stopCapture()
        isFinishing = true
        recognitionTask?.finish()
        completionFallback?.cancel()
        completionFallback = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            complete()
        }
    }

    private func stopCapture() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        engine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func complete() {
        guard isFinishing || isRecording else { return }
        if isRecording { stopCapture() }
        isFinishing = false
        completionFallback?.cancel()
        completionFallback = nil
        recognitionTask = nil
        request = nil
        recognizer = nil
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completionCount += 1
        }
    }

    func cancel() {
        sessionID = UUID()
        completionFallback?.cancel()
        completionFallback = nil
        if isRecording || engine != nil { stopCapture() }
        isPreparing = false
        isFinishing = false
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
    }
}
