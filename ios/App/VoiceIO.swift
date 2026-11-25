import SwiftUI
import Speech
import AVFoundation

@MainActor
final class VoiceIO: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var recording = false
    @Published var transcript = ""
    @Published var speaking = false
    @Published var error: String? = nil

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    private func authorize() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { status in c.resume(returning: status == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        if !speechOK || !micOK {
            error = "Разреши микрофон и распознавание речи: Настройки → Помощник"
        }
        return speechOK && micOK
    }

    func toggleRecording() {
        if recording { stopRecording() } else { Task { await startRecording() } }
    }

    func startRecording() async {
        error = nil
        guard await authorize() else { return }
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание речи сейчас недоступно"
            return
        }
        stopSpeaking()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Микрофон недоступен"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            self.error = "Не удалось включить микрофон"
            return
        }
        recording = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if err != nil || final { self.stopRecording() }
            }
        }
    }

    func stopRecording() {
        guard recording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        recording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func speak(_ text: String) {
        var clean = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "[*#`_>|]", with: "", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: clean)
        u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
        speaking = true
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}
