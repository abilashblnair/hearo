import Foundation

final class ServiceContainer: ObservableObject {
    let audio: AudioRecordingService
    let transcription: TranscriptionService
    let summarization: SummarizationService
    let translation: TranslationService
    let pdf: PDFService
    let sessions: SessionRepository
    let tts: GoogleCloudTTSManager
    let adManager: AdManagerProtocol
    
    init(audio: AudioRecordingService,
         transcription: TranscriptionService,
         summarization: SummarizationService,
         translation: TranslationService,
         pdf: PDFService,
         sessions: SessionRepository,
         tts: GoogleCloudTTSManager,
         adManager: AdManagerProtocol) {
        self.audio = audio
        self.transcription = transcription
        self.summarization = summarization
        self.translation = translation
        self.pdf = pdf
        self.sessions = sessions
        self.tts = tts
        self.adManager = adManager
    }
    
    /// Factory method to create default services with proper configuration
    static func create() -> ServiceContainer {
        let gptService = GPTSummarizationServiceImpl(apiKey: Secrets.openAIKey)
        let adManager = GoogleAdManager()

        return ServiceContainer(
            audio: UnifiedAudioRecordingServiceImpl(),
            transcription: AssemblyAITranscriptionServiceImpl(),
            summarization: gptService,
            translation: gptService, // Same service implements both protocols
            pdf: PDFKitServiceImpl(),
            sessions: LocalSessionRepository(),
            tts: GoogleCloudTTSManager.shared,
            adManager: adManager
        )
    }
}
