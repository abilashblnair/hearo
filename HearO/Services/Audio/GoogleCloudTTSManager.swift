import Foundation
import AVFoundation

final class GoogleCloudTTSManager: NSObject, ObservableObject {
    static let shared = GoogleCloudTTSManager()
    
    private let cacheManager = CacheManager.shared
    private let apiKey = "AIzaSyAtTBjgOWlukPxzlc1t7e-sLebEyOPB-Nk" // Replace with your actual API key
    private let baseURL = "https://texttospeech.googleapis.com/v1/text:synthesize"
    
    @Published private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var isSpeaking = false
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }
    }
    
    // Speak with Language object
    func speak(text: String, language: Language, completion: ((Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }
        
        let languageCode = language.googleTTSLanguageCode ?? getDefaultLanguageCode(for: language)
        let voiceCode = language.googleTTSVoice ?? getDefaultVoice(for: language)
        
        
        speak(text: text, languageCode: languageCode, voice: voiceCode, completion: completion)
    }
    
    // Core speak method
    func speak(text: String, languageCode: String, voice: String, completion: ((Bool) -> Void)? = nil) {
        let cacheKey = "gtts_\(languageCode)_\(voice)_\(text.md5)"
        
        // Check cache first
        if let cachedURL = cacheManager.getCachedAudioURL(forKey: cacheKey) {
            DispatchQueue.main.async {
                self.playAudio(from: cachedURL)
                completion?(true)
            }
            return
        }
        
        // Synthesize new audio
        synthesizeAndPlay(text: text, languageCode: languageCode, voice: voice, cacheKey: cacheKey, completion: completion)
    }
    
    private func getDefaultLanguageCode(for language: Language) -> String {
        // Map language codes to Google TTS language codes
        switch language.languageCode {
        case "en":
            return language.countryCode == "US" ? "en-US" : "en-GB"
        case "es":
            return language.countryCode == "MX" ? "es-MX" : "es-ES"
        case "fr":
            return "fr-FR"
        case "de":
            return "de-DE"
        case "it":
            return "it-IT"
        case "pt":
            return language.countryCode == "BR" ? "pt-BR" : "pt-PT"
        case "zh":
            return language.countryCode == "CN" ? "cmn-CN" : "cmn-TW"
        case "ja":
            return "ja-JP"
        case "ko":
            return "ko-KR"
        case "ar":
            return "ar-XA"
        case "ru":
            return "ru-RU"
        case "hi":
            return "hi-IN"
        case "ta":
            return "ta-IN"
        case "te":
            return "te-IN"
        case "ml":
            return "ml-IN"
        case "kn":
            return "kn-IN"
        case "gu":
            return "gu-IN"
        case "bn":
            return "bn-IN"
        case "nl":
            return "nl-NL"
        case "sv":
            return "sv-SE"
        case "no", "nb":
            return "nb-NO"
        case "da":
            return "da-DK"
        default:
            return "en-US" // Fallback to English
        }
    }
    
    private func getDefaultVoice(for language: Language) -> String {
        // Map language codes to Google TTS voices (using only verified voices)
        switch language.languageCode {
        case "en":
            return language.countryCode == "US" ? "en-US-Studio-O" : "en-GB-Standard-A"
        case "es":
            if language.countryCode == "MX" {
                return "es-MX-Standard-A"
            } else if language.countryCode == "US" {
                return "es-US-Standard-A"
            } else {
                return "es-ES-Standard-A"
            }
        case "fr":
            return language.countryCode == "CA" ? "fr-CA-Standard-A" : "fr-FR-Standard-A"
        case "de":
            return "de-DE-Standard-A"
        case "it":
            return "it-IT-Standard-A"
        case "pt":
            return language.countryCode == "BR" ? "pt-BR-Standard-A" : "pt-PT-Standard-A"
        case "zh":
            return language.countryCode == "CN" ? "cmn-CN-Standard-A" : "cmn-TW-Standard-A"
        case "ja":
            return "ja-JP-Standard-A"
        case "ko":
            return "ko-KR-Standard-A"
        case "ar":
            return "ar-XA-Standard-A"
        case "ru":
            return "ru-RU-Standard-A"
        case "hi":
            return "hi-IN-Standard-A"
        case "nl":
            return "nl-NL-Standard-A"
        case "sv":
            return "sv-SE-Standard-A"
        case "no", "nb":
            return "nb-NO-Standard-A"
        case "da":
            return "da-DK-Standard-A"
        case "pl":
            return "pl-PL-Standard-A"
        case "cs":
            return "cs-CZ-Standard-A"
        case "tr":
            return "tr-TR-Standard-A"
        case "th":
            return "th-TH-Standard-A"
        case "vi":
            return "vi-VN-Standard-A"
        case "id":
            return "id-ID-Standard-A"
        case "ta":
            return "ta-IN-Standard-A"
        case "te":
            return "te-IN-Standard-A"
        case "ml":
            return "ml-IN-Standard-A"
        case "kn":
            return "kn-IN-Standard-A"
        case "gu":
            return "gu-IN-Standard-A"
        case "bn":
            return "bn-IN-Standard-A"
        case "fi":
            return "fi-FI-Standard-A"
        case "hu":
            return "hu-HU-Standard-A"
        case "sk":
            return "sk-SK-Standard-A"
        case "uk":
            return "uk-UA-Standard-A"
        default:
            return "en-US-Studio-O" // Fallback to English Studio voice
        }
    }
    
    private func synthesizeAndPlay(text: String, languageCode: String, voice: String, cacheKey: String, completion: ((Bool) -> Void)?) {
        guard let url = URL(string: baseURL + "?key=\(apiKey)") else {
            DispatchQueue.main.async {
                completion?(false)
            }
            return
        }
        
        let requestBody: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": languageCode,
                "name": voice
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": 1.0,
                "pitch": 0.0
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                completion?(false)
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
            
            if error != nil {
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let audioContent = json?["audioContent"] as? String,
                   let audioData = Data(base64Encoded: audioContent) {
                    
                    let tempURL = self.cacheManager.cacheAudio(data: audioData, forKey: cacheKey)
                    DispatchQueue.main.async {
                        self.playAudio(from: tempURL)
                        completion?(true)
                    }
                } else if let error = json?["error"] as? [String: Any],
                         let _ = error["message"] as? String {
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }.resume()
    }
    
    private func playAudio(from url: URL) {
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
    }
}

// MARK: - AVAudioPlayerDelegate
extension GoogleCloudTTSManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
                if error != nil {
        }
    }
}

// MARK: - String MD5 Extension
extension String {
    var md5: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { bytes -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto
