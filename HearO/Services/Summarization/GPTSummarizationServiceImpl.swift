import Foundation

final class GPTSummarizationServiceImpl: SummarizationService, TranslationService {
    private let apiKey: String
    private let model = "gpt-4o-mini"
    private let maxChunkDuration: TimeInterval = 8 * 60 // 8 minutes per chunk
    private let chunkOverlap: TimeInterval = 15 // 15 seconds overlap
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - SummarizationService
    func summarize(segments: [TranscriptSegment], locale: String = "en-US") async throws -> Summary {
        guard !segments.isEmpty else {
            return Summary(locale: locale)
        }
        
        let chunks = chunkSegments(segments, maxDuration: maxChunkDuration, overlap: chunkOverlap)
        
        if chunks.count == 1 {
            return try await summarizeChunk(chunks[0], locale: locale)
        } else {
            let partials: [Summary] = try await withThrowingTaskGroup(of: Summary.self) { group in
                for chunk in chunks {
                    group.addTask {
                        try await self.summarizeChunk(chunk, locale: locale)
                    }
                }
                
                var results: [Summary] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            var finalSummary = try await mergePartialSummaries(partials, locale: locale)
            finalSummary.locale = locale
            return finalSummary
        }
    }
    
    // MARK: - TranslationService
    func translate(segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        
        let chunks = chunkSegments(segments, maxDuration: maxChunkDuration * 2)
        var translatedSegments: [TranscriptSegment] = []
        
        for chunk in chunks {
            let translated = try await translateChunk(chunk, targetLanguage: targetLanguage)
            translatedSegments.append(contentsOf: translated)
        }
        
        return translatedSegments
    }
    
    // MARK: - Private Implementation
    private func summarizeChunk(_ segments: [TranscriptSegment], locale: String) async throws -> Summary {
        let userPrompt = buildSummarizationPrompt(segments: segments, locale: locale)
        var summary: Summary = try await requestJSON(system: summarizationSystemPrompt, user: userPrompt)
        summary.locale = locale
        return summary
    }
    
    private func translateChunk(_ segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment] {
        let userPrompt = buildTranslationPrompt(segments: segments, targetLanguage: targetLanguage)
        
        struct TranslationResponse: Codable {
            let segments: [TranslatedSegment]
            
            struct TranslatedSegment: Codable {
                let originalText: String
                let translatedText: String
                let speaker: String?
            }
        }
        
        let response: TranslationResponse = try await requestJSON(
            system: translationSystemPrompt,
            user: userPrompt
        )
        
        return zip(segments, response.segments).map { original, translated in
            TranscriptSegment(
                id: original.id,
                speaker: translated.speaker ?? original.speaker,
                text: translated.translatedText,
                startTime: original.startTime,
                endTime: original.endTime
            )
        }
    }
    
    private func mergePartialSummaries(_ partials: [Summary], locale: String) async throws -> Summary {
        guard partials.count > 1 else {
            var defaultSummary = partials.first ?? Summary()
            defaultSummary.locale = locale
            return defaultSummary
        }
        
        let mergePrompt = """
        Merge multiple JSON summaries into one comprehensive summary.
        Deduplicate similar items and keep timestamp refs.
        Return a single Summary JSON object.
        
        PARTIAL SUMMARIES:
        \(String(data: try JSONEncoder().encode(partials), encoding: .utf8) ?? "")
        """
        
        var mergedSummary: Summary = try await requestJSON(system: summarizationSystemPrompt, user: mergePrompt)
        mergedSummary.locale = locale
        return mergedSummary
    }
    
    private func requestJSON<T: Decodable>(system: String, user: String) async throws -> T {
        // Validate API key
        guard !apiKey.isEmpty else {
            throw SummarizationError.apiError(401, "OpenAI API key is missing. Please check your configuration.")
        }
        
        print("🔑 Using OpenAI API key: \(String(apiKey.prefix(10)))...")
        print("🤖 Model: \(model)")
        
        let request = OpenAIRequest(
            model: model,
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            response_format: ["type": "json_object"],
            temperature: 0.1
        )
        
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.invalidResponse
        }
        
        print("📡 API Response Status: \(httpResponse.statusCode)")
        print("📊 Response Data Size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ API Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw SummarizationError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummarizationError.invalidResponse
        }
        
        do {
            // Add detailed logging for debugging
            print("📝 OpenAI Response Content:")
            print(content)
            print("🔍 Attempting to decode as \(T.self)")
            
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            print("❌ JSON Decoding Error:")
            print("Error: \(error)")
            print("Raw content: \(content)")
            print("JSON Data: \(String(data: jsonData, encoding: .utf8) ?? "nil")")
            
            throw SummarizationError.decodingError("Failed to decode \(T.self): \(error.localizedDescription). Raw content: \(content)")
        }
    }
    
    private func buildSummarizationPrompt(segments: [TranscriptSegment], locale: String) -> String {
        let segmentArray = segments.map { segment in
            [
                "start": segment.startTime.formattedHMS(),
                "end": segment.endTime.formattedHMS(),
                "speaker": segment.speaker ?? "Unknown",
                "text": segment.text
            ]
        }
        
        let jsonString = String(
            data: try! JSONSerialization.data(withJSONObject: segmentArray, options: .prettyPrinted),
            encoding: .utf8
        )!
        
        return """
        MEETING CONTEXT
        - Locale: \(locale)
        - Goal: Accurate summary with timestamped references
        
        OUTPUT SCHEMA:
        \(summarySchemaJSON)
        
        TRANSCRIPT SEGMENTS:
        \(jsonString)
        
        TASKS:
        1) Extract key points with timestamp refs
        2) Find action items with owners/dates if explicit
        3) Identify decisions and context
        4) Select notable quotes
        5) Create timeline if applicable
        6) Write 2-3 sentence overview
        
        Return valid JSON only.
        """
    }
    
    private func buildTranslationPrompt(segments: [TranscriptSegment], targetLanguage: String) -> String {
        let segmentArray = segments.map { segment in
            [
                "speaker": segment.speaker ?? "Unknown",
                "text": segment.text
            ]
        }
        
        let jsonString = String(
            data: try! JSONSerialization.data(withJSONObject: segmentArray, options: .prettyPrinted),
            encoding: .utf8
        )!
        
        return """
        Translate to \(targetLanguage). Maintain speaker attribution.
        
        Output JSON:
        {
          "segments": [
            {
              "originalText": "...",
              "translatedText": "...",
              "speaker": "..."
            }
          ]
        }
        
        TRANSCRIPT:
        \(jsonString)
        """
    }
    
    private var summarizationSystemPrompt: String {
        """
        You are a meeting summarizer. Use ONLY the provided transcript.
        
        RULES:
        - Ground facts in transcript; avoid assumptions
        - Attach timestamp refs to all extracted items
        - Use ISO dates (YYYY-MM-DD) only if explicit
        - Use exact speaker names; null if uncertain
        - Output strict JSON matching schema
        
        Focus on accuracy for actionable follow-ups.
        """
    }
    
    private var translationSystemPrompt: String {
        """
        Professional translator. Preserve:
        - Speaker attribution
        - Technical terms
        - Conversational tone
        - Meeting context
        
        Output valid JSON only.
        """
    }
    
    private var summarySchemaJSON: String {
        """
        {
          "overview": "string",
          "keyPoints": [{"text": "string", "refs": [{"start": "HH:MM:SS", "end": "HH:MM:SS"}]}],
          "actionItems": [{"text": "string", "owner": "string|null", "dueDateISO8601": "YYYY-MM-DD|null", "priority": "low|medium|high|urgent|null", "status": "pending", "refs": [{"start": "HH:MM:SS", "end": "HH:MM:SS"}]}],
          "decisions": [{"text": "string", "impact": "low|medium|high|null", "refs": [{"start": "HH:MM:SS", "end": "HH:MM:SS"}]}],
          "quotes": [{"speaker": "string|null", "text": "string", "context": "string|null", "refs": [{"start": "HH:MM:SS", "end": "HH:MM:SS"}]}],
          "timeline": [{"at": "HH:MM:SS", "text": "string", "importance": "low|medium|high|null"}]
        }
        """
    }
}

// MARK: - Chunking Logic
private extension GPTSummarizationServiceImpl {
    func chunkSegments(_ segments: [TranscriptSegment], maxDuration: TimeInterval, overlap: TimeInterval = 0) -> [[TranscriptSegment]] {
        guard !segments.isEmpty else { return [] }
        
        var chunks: [[TranscriptSegment]] = []
        var currentChunk: [TranscriptSegment] = []
        var chunkStartTime = segments.first!.startTime
        
        for segment in segments {
            if segment.endTime - chunkStartTime > maxDuration && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                
                let overlapStartTime = max(chunkStartTime, segment.startTime - overlap)
                currentChunk = currentChunk.filter { $0.startTime >= overlapStartTime }
                chunkStartTime = currentChunk.first?.startTime ?? segment.startTime
            }
            
            currentChunk.append(segment)
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
}

// MARK: - OpenAI API Models
private struct OpenAIRequest: Codable {
    let model: String
    let messages: [[String: String]]
    let response_format: [String: String]
    let temperature: Double
}

private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Error Types
enum SummarizationError: LocalizedError {
    case invalidResponse
    case apiError(Int, String)
    case decodingError(String)
    case emptyTranscript
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from summarization service"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .emptyTranscript:
            return "Cannot summarize empty transcript"
        }
    }
}
