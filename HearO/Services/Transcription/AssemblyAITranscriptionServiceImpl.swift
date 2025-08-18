import Foundation

struct AAIUploadResponse: Decodable { let upload_url: String }
struct AAITranscriptCreateResponse: Decodable { let id: String }
struct AAITranscriptPollResponse: Decodable {
    let id: String
    let status: String
    let text: String?
    let error: String?
}

final class AssemblyAITranscriptionServiceImpl: TranscriptionService {
    private let baseURL = URL(string: "https://api.assemblyai.com/v2")!
    private var apiKey: String { Secrets.assemblyAIKey }
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(audioURL: URL, languageCode: String) async throws -> [TranscriptSegment] {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AssemblyAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing AssemblyAI API key. Add ASSEMBLYAI_API_KEY to Info.plist or set via UserDefaults."])
        }

        // 1) Upload local file
        let uploadURL = try await uploadLocalFile(audioURL)

        // 2) Create transcript job
        let transcriptID = try await createTranscript(audioURL: uploadURL)

        // 3) Poll for completion
        let final = try await pollTranscript(id: transcriptID)

        let text = final.text ?? ""
        // Return a single segment for MVP
        return [TranscriptSegment(id: UUID(), speaker: nil, text: text, startTime: 0, endTime: 0)]
    }

    // MARK: - Private helpers
    private func uploadLocalFile(_ fileURL: URL) async throws -> String {
        let uploadEndpoint = baseURL.appendingPathComponent("upload")
        var req = URLRequest(url: uploadEndpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "authorization")
        // Stream file to avoid loading entire file into memory
        let (fileData, _) = try await URLSession.shared.readFileData(url: fileURL)
        let (data, response) = try await session.upload(for: req, from: fileData)
        try Self.ensureOK(response)
        let decoded = try JSONDecoder().decode(AAIUploadResponse.self, from: data)
        return decoded.upload_url
    }

    private func createTranscript(audioURL: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("transcript"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "audio_url": audioURL,
            "speech_model": "universal",
            "language_code": "en"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, response) = try await session.data(for: req)
        try Self.ensureOK(response)
        let decoded = try JSONDecoder().decode(AAITranscriptCreateResponse.self, from: data)
        return decoded.id
    }

    private func pollTranscript(id: String) async throws -> AAITranscriptPollResponse {
        let pollURL = baseURL.appendingPathComponent("transcript/\(id)")
        var attempts = 0
        while attempts < 600 { // up to ~20 minutes at 2s
            var req = URLRequest(url: pollURL)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "authorization")
            let (data, response) = try await session.data(for: req)
            try Self.ensureOK(response)
            let decoded = try JSONDecoder().decode(AAITranscriptPollResponse.self, from: data)
            switch decoded.status.lowercased() {
            case "completed":
                return decoded
            case "error":
                throw NSError(domain: "AssemblyAI", code: -2, userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "Unknown error"])
            default:
                try await Task.sleep(nanoseconds: 2_000_000_000)
                attempts += 1
            }
        }
        throw NSError(domain: "AssemblyAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Polling timeout"])        
    }

    private static func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AssemblyAI", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
        }
    }
}

private extension URLSession {
    func readFileData(url: URL) async throws -> (Data, URLResponse) {
        // For simplicity, read into memory. For large files, consider streaming.
        let data = try Data(contentsOf: url)
        return (data, URLResponse())
    }
}
