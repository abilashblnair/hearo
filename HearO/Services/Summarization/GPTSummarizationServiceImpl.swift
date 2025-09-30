import Foundation

final class GPTSummarizationServiceImpl: SummarizationService, TranslationService {
    private var apiKey: String { Secrets.openAIKey }
    private let model = "gpt-4.1"
    private let maxChunkDuration: TimeInterval = 8 * 60 // 8 minutes per chunk
    private let maxTranslationChunkDuration: TimeInterval = 2 * 60 // 2 minutes per chunk for translation
    private let maxTranslationChars = 3000 // Max characters per translation request
    private let chunkOverlap: TimeInterval = 15 // 15 seconds overlap
    private let maxRetries = 3
    
    // Custom URLSession with conservative timeout for smaller translation requests
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90 // 1.5 minutes
        configuration.timeoutIntervalForResource = 180 // 3 minutes
        return URLSession(configuration: configuration)
    }()
    
    init(apiKey: String) {}
    
    // MARK: - SummarizationService
    func summarize(segments: [TranscriptSegment], locale: String = "en-US", title: String? = nil, notes: String? = nil) async throws -> Summary {
        guard !segments.isEmpty else {
            return Summary(locale: locale)
        }
        
        let chunks = chunkSegments(segments, maxDuration: maxChunkDuration, overlap: chunkOverlap)
        
        if chunks.count == 1 {
            return try await summarizeChunkWithRetry(chunks[0], locale: locale, title: title, notes: notes)
        } else {
            let partials: [Summary] = try await withThrowingTaskGroup(of: Summary.self) { group in
                for chunk in chunks {
                    group.addTask {
                        try await self.summarizeChunkWithRetry(chunk, locale: locale, title: title, notes: notes)
                    }
                }
                
                var results: [Summary] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            var finalSummary = try await mergePartialSummaries(partials, locale: locale, title: title, notes: notes)
            finalSummary.locale = locale
            return finalSummary
        }
    }
    
    // MARK: - TranslationService
    func translate(segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        
        
        // Debug: Print first few segments to understand input
        for (_, _) in segments.prefix(3).enumerated() {
        }
        
        // Use character-based chunking for translation to ensure manageable request sizes
        let chunks = chunkSegmentsForTranslation(segments)
        var translatedSegments: [TranscriptSegment] = []
        
        
        // Debug chunking
        for (_, chunk) in chunks.enumerated() {
            let _ = chunk.reduce(0) { $0 + $1.text.count }
        }
        
        for (index, chunk) in chunks.enumerated() {
            
            let translated = try await translateChunkWithRetry(chunk, targetLanguage: targetLanguage)
            translatedSegments.append(contentsOf: translated)
            
            
            // Add small delay between chunks to avoid rate limiting
            if index < chunks.count - 1 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            }
        }
        
        return translatedSegments
    }
    
    // MARK: - Private Implementation
    private func summarizeChunk(_ segments: [TranscriptSegment], locale: String, title: String? = nil, notes: String? = nil) async throws -> Summary {
        let userPrompt = buildSummarizationPrompt(segments: segments, locale: locale, title: title, notes: notes)
        var summary: Summary = try await requestJSON(system: summarizationSystemPrompt, user: userPrompt)
        summary.locale = locale
        return summary
    }
    
    private func summarizeChunkWithRetry(_ segments: [TranscriptSegment], locale: String, title: String? = nil, notes: String? = nil) async throws -> Summary {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await summarizeChunk(segments, locale: locale, title: title, notes: notes)
            } catch {
                lastError = error
                
                // If it's a network cancellation, don't retry
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw error
                }
                
                // For other errors, retry with backoff
                if attempt < maxRetries {
                    let delay = Double(attempt) * 1.0 // 1s, 2s, 3s backoff
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? SummarizationError.apiError(408, "Summary generation failed after \(maxRetries) attempts")
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
        
        
        // Ensure we have the same number of segments in response as input
        guard response.segments.count == segments.count else {
            // Fallback: use minimum count to avoid crashes
            let minCount = min(segments.count, response.segments.count)
            let responseSegments = Array(response.segments.prefix(minCount))
            let inputSegments = Array(segments.prefix(minCount))
            
            return zip(inputSegments, responseSegments).map { original, translated in
                TranscriptSegment(
                    id: original.id,
                    speaker: translated.speaker ?? original.speaker,
                    text: translated.translatedText,
                    startTime: original.startTime,
                    endTime: original.endTime
                )
            }
        }
        
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
    
    private func translateChunkWithRetry(_ segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment] {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await translateChunk(segments, targetLanguage: targetLanguage)
            } catch {
                lastError = error
                
                // Check if it's a timeout error
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    if attempt < maxRetries {
                        let delay = Double(attempt) * 1.5 // Faster backoff: 1.5s, 3s, 4.5s
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    
                    // If all retries failed due to timeout, try ultra-small chunking as last resort
                    if attempt == maxRetries {
                        return try await translateWithUltraSmallChunks(segments, targetLanguage: targetLanguage)
                    }
                }
                
                // For non-timeout errors, fail immediately
                if !(error is URLError && (error as! URLError).code == .timedOut) {
                    throw error
                }
            }
        }
        
        throw lastError ?? SummarizationError.apiError(408, "Translation failed after \(maxRetries) attempts")
    }
    
    private func translateWithUltraSmallChunks(_ segments: [TranscriptSegment], targetLanguage: String) async throws -> [TranscriptSegment] {
        var translatedSegments: [TranscriptSegment] = []
        
        for (index, segment) in segments.enumerated() {
            
            do {
                let translated = try await translateChunk([segment], targetLanguage: targetLanguage)
                translatedSegments.append(contentsOf: translated)
                
                // Short delay between individual requests
                if index < segments.count - 1 {
                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
                }
            } catch {
                // Fallback: keep original text if translation fails
                translatedSegments.append(segment)
            }
        }
        
        return translatedSegments
    }
    
    private func mergePartialSummaries(_ partials: [Summary], locale: String, title: String? = nil, notes: String? = nil) async throws -> Summary {
        guard partials.count > 1 else {
            var defaultSummary = partials.first ?? Summary()
            defaultSummary.locale = locale
            return defaultSummary
        }
        
        var mergePrompt = """
        Merge multiple JSON summaries into one comprehensive summary.
        Deduplicate similar items and keep timestamp refs.
        Return a single Summary JSON object.
        
        """
        
        if let title = title {
            mergePrompt += "SESSION TITLE: \(title)\n\n"
        }
        
        if let notes = notes {
            mergePrompt += "USER NOTES: \(notes)\n\n"
        }
        
        mergePrompt += """
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
        
        let (data, response) = try await urlSession.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummarizationError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw SummarizationError.invalidResponse
        }
        
        do {
            
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            
            throw SummarizationError.decodingError("Failed to decode \(T.self): \(error.localizedDescription). Raw content: \(content)")
        }
    }
    
    private func buildSummarizationPrompt(segments: [TranscriptSegment], locale: String, title: String? = nil, notes: String? = nil) -> String {
        let segmentArray = segments.map { segment in
            [
                "start": segment.startTime.formattedHMS(),
                "end": segment.endTime.formattedHMS(),
                "speaker": segment.speaker ?? "",
                "text": segment.text
            ]
        }
        
        let jsonString = String(
            data: try! JSONSerialization.data(withJSONObject: segmentArray, options: .prettyPrinted),
            encoding: .utf8
        )!
        
        var prompt = """
        MEETING CONTEXT
        - Locale: \(locale)
        - Goal: Accurate summary with timestamped references
        
        """
        
        if let title = title {
            prompt += "SESSION TITLE: \(title)\n"
        }
        
        if let notes = notes {
            prompt += """
            USER NOTES (for context): \(notes)
            Use this context to provide more accurate summaries and identify what was important to the user.
            
            """
        }
        
        prompt += """
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
        
        """
        
        if notes != nil {
            prompt += "7) Consider the user notes when prioritizing important content\n"
        }
        
        prompt += "\nReturn valid JSON only."
        
        return prompt
    }
    
    private func buildTranslationPrompt(segments: [TranscriptSegment], targetLanguage: String) -> String {
        // Estimate prompt size to avoid overly large requests
        let _ = segments.reduce(0) { $0 + $1.text.count }
        
        let segmentArray = segments.map { segment in
            [
                "speaker": segment.speaker ?? "",
                "text": segment.text
            ]
        }
        
        let jsonString = String(
            data: try! JSONSerialization.data(withJSONObject: segmentArray, options: .prettyPrinted),
            encoding: .utf8
        )!
        
        return """
        Translate each segment to \(targetLanguage). You must return EXACTLY the same number of segments as provided.
        Maintain speaker attribution and preserve original text structure.
        
        CRITICAL: Return exactly \(segments.count) segments in the response array.
        
        Output JSON format (must match this structure exactly):
        {
          "segments": [
            {
              "originalText": "exact original text from input",
              "translatedText": "translated version",
              "speaker": "exact speaker name from input or null"
            }
          ]
        }
        
        INPUT TRANSCRIPT (\(segments.count) segments):
        \(jsonString)
        
        Remember: Return exactly \(segments.count) segments in your response.
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
    
    func chunkSegmentsForTranslation(_ segments: [TranscriptSegment]) -> [[TranscriptSegment]] {
        guard !segments.isEmpty else { return [] }
        
        var chunks: [[TranscriptSegment]] = []
        var currentChunk: [TranscriptSegment] = []
        var currentCharCount = 0
        
        for segment in segments {
            let segmentCharCount = segment.text.count
            
            // If adding this segment would exceed the limit and we have segments in current chunk
            if currentCharCount + segmentCharCount > maxTranslationChars && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentCharCount = 0
            }
            
            // If a single segment is too large, split it
            if segmentCharCount > maxTranslationChars {
                // First, add any existing chunk
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = []
                    currentCharCount = 0
                }
                
                // Split the large segment
                let splitSegments = splitLargeSegment(segment)
                for splitSegment in splitSegments {
                    chunks.append([splitSegment])
                }
            } else {
                currentChunk.append(segment)
                currentCharCount += segmentCharCount
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        for (_, chunk) in chunks.enumerated() {
            let _ = chunk.reduce(0) { $0 + $1.text.count }
        }
        
        return chunks
    }
    
    func splitLargeSegment(_ segment: TranscriptSegment) -> [TranscriptSegment] {
        let text = segment.text
        guard text.count > maxTranslationChars else { return [segment] }
        
        var segments: [TranscriptSegment] = []
        var currentPosition = 0
        
        while currentPosition < text.count {
            let remainingChars = text.count - currentPosition
            let chunkSize = min(maxTranslationChars, remainingChars)
            
            // Calculate end position
            var endPosition = currentPosition + chunkSize
            
            // If this isn't the last chunk, try to find a better break point
            if endPosition < text.count {
                let searchStart = max(currentPosition + chunkSize / 2, currentPosition)
                let searchEnd = min(endPosition + 100, text.count) // Look a bit ahead for better boundaries
                
                let searchStartIndex = text.index(text.startIndex, offsetBy: searchStart)
                let searchEndIndex = text.index(text.startIndex, offsetBy: searchEnd)
                let searchSubstring = text[searchStartIndex..<searchEndIndex]
                
                // Look for sentence end
                if let range = searchSubstring.range(of: "[.!?]", options: .regularExpression) {
                    let offset = text.distance(from: text.startIndex, to: range.upperBound)
                    endPosition = offset
                }
                // Look for word boundary
                else if let range = searchSubstring.range(of: " ") {
                    let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                    endPosition = offset
                }
            }
            
            // Extract text for this chunk
            let startIndex = text.index(text.startIndex, offsetBy: currentPosition)
            let endIndex = text.index(text.startIndex, offsetBy: min(endPosition, text.count))
            let chunkText = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !chunkText.isEmpty {
                segments.append(TranscriptSegment(
                    id: UUID(),
                    speaker: segment.speaker,
                    text: chunkText,
                    startTime: segment.startTime,
                    endTime: segment.endTime
                ))
            }
            
            // Ensure progress to avoid infinite loops
            if endPosition <= currentPosition && currentPosition < text.count {
                currentPosition += 1
            } else {
                currentPosition = endPosition
            }
        }
        
        return segments.isEmpty ? [segment] : segments
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
