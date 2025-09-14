import SwiftUI

struct SummaryView: View {
    let summary: Summary
    let sessionDuration: TimeInterval?
    let sessionTitle: String?
    let onSeekToTimestamp: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var di: ServiceContainer
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedSection: SummarySection = .overview
    @State private var isSharing = false
    @State private var expandedActionItems: Set<UUID> = []
    @State private var animateEntrance = false
    @State private var showingAllQuotes = false
    @State private var isGeneratingPDF = false
    @State private var generatedPDFURL: URL?
    @State private var showingPDFShare = false
    @State private var pdfError: String?
    @State private var showingPDFError = false
    @State private var showingCopySuccess = false
    @State private var showPaywall = false

    enum SummarySection: String, CaseIterable {
        case overview = "Overview"
        case keyPoints = "Key Points"
        case actionItems = "Action Items"
        case decisions = "Decisions"
        case quotes = "Quotes"
        case timeline = "Timeline"

        var icon: String {
            switch self {
            case .overview: return "doc.text"
            case .keyPoints: return "key"
            case .actionItems: return "checkmark.circle"
            case .decisions: return "arrow.triangle.branch"
            case .quotes: return "quote.bubble"
            case .timeline: return "timeline.selection"
            }
        }

        var color: Color {
            switch self {
            case .overview: return .blue
            case .keyPoints: return .green
            case .actionItems: return .orange
            case .decisions: return .purple
            case .quotes: return .pink
            case .timeline: return .indigo
            }
        }
    }

    var body: some View {
        NavigationStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad centered layout
                GeometryReader { geometry in
                    HStack {
                        Spacer()
                        
                        VStack {
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 20) {
                                        headerView
                                            .opacity(animateEntrance ? 1 : 0)
                                            .offset(y: animateEntrance ? 0 : -20)
                                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: animateEntrance)

                                        sectionPicker
                                            .opacity(animateEntrance ? 1 : 0)
                                            .offset(y: animateEntrance ? 0 : -10)
                                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateEntrance)

                                        contentView
                                            .opacity(animateEntrance ? 1 : 0)
                                            .offset(y: animateEntrance ? 0 : 10)
                                            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3), value: animateEntrance)
                                    }
                                    .padding(UIDevice.current.userInterfaceIdiom == .pad ? 32 : 16)
                                }
                                .onChange(of: selectedSection) { _, newSection in
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        proxy.scrollTo(newSection.rawValue, anchor: .top)
                                    }
                                }
                            }
                            
                            // Action Buttons for iPad
                            VStack(spacing: 16) {
                                // Copy Success Toast
                                if showingCopySuccess {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Summary copied to clipboard!")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color(.systemBackground))
                                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                    )
                                    .transition(.scale.combined(with: .opacity))
                                }
                                
                                // Action Buttons
                                HStack(spacing: 16) {
                                    // Copy Summary Button
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        Task {
                                            await copySummaryToClipboard()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.on.doc.fill")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            Text("Copy Summary")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 56)
                                        .padding(.vertical, 16)
                                        .padding(.horizontal, 24)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.green)
                                        )
                                    }
                                    
                                    // Export PDF Button
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        
                                        // Check premium access for export
                                        let exportCheck = di.featureManager.canExport()
                                        if !exportCheck.allowed {
                                            showPaywall = true
                                            return
                                        }
                                        
                                        Task {
                                            await generatePDF()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: isGeneratingPDF ? "doc.badge.gearshape" : "doc.fill")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.white)
                                            
                                            Text(isGeneratingPDF ? "Generating..." : "Export PDF")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 56)
                                        .padding(.vertical, 16)
                                        .padding(.horizontal, 24)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(isGeneratingPDF ? Color.orange : Color.blue)
                                        )
                                    }
                                    .disabled(isGeneratingPDF)
                                }
                                .frame(maxWidth: 600) // Limit button width on iPad
                                .padding(.bottom, 32)
                            }
                        }
                        .frame(maxWidth: min(geometry.size.width * 0.8, 1000))
                        
                        Spacer()
                    }
                }
            } else {
                // iPhone layout
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 20) {
                            headerView
                                .opacity(animateEntrance ? 1 : 0)
                                .offset(y: animateEntrance ? 0 : -20)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: animateEntrance)

                            sectionPicker
                                .opacity(animateEntrance ? 1 : 0)
                                .offset(y: animateEntrance ? 0 : -10)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateEntrance)

                            contentView
                                .opacity(animateEntrance ? 1 : 0)
                                .offset(y: animateEntrance ? 0 : 10)
                                .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3), value: animateEntrance)
                        }
                        .padding(16)
                    }
                    .onChange(of: selectedSection) { _, newSection in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            proxy.scrollTo(newSection.rawValue, anchor: .top)
                        }
                    }
                }
                
                // Action Buttons - Static at bottom
                VStack(spacing: 16) {
                    // Copy Success Toast
                    if showingCopySuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Summary copied to clipboard!")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        // Copy Summary Button
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task {
                                await copySummaryToClipboard()
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text("Copy Summary")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green)
                            )
                        }
                        
                        // Export PDF Button
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            
                            // Check premium access for export
                            let exportCheck = di.featureManager.canExport()
                            if !exportCheck.allowed {
                                showPaywall = true
                                return
                            }
                            
                            Task {
                                await generatePDF()
                            }
                        }) {
                            HStack {
                                Image(systemName: isGeneratingPDF ? "doc.badge.gearshape" : "doc.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text(isGeneratingPDF ? "Generating..." : "Export PDF")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isGeneratingPDF ? Color.orange : Color.blue)
                            )
                        }
                        .disabled(isGeneratingPDF)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("AI Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: summary.sharingText,
                    preview: SharePreview("Meeting Summary", image: Image(systemName: "doc.text"))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                }
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        .paywall(isPresented: $showPaywall, placementId: AppConfigManager.shared.adaptyPlacementID)
        .fullScreenCover(isPresented: $subscriptionManager.showSubscriptionSuccessView) {
            SubscriptionSuccessView()
                .environmentObject(subscriptionManager)
        }
        .onAppear {
            withAnimation {
                animateEntrance = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .sheet(isPresented: $showingPDFShare) {
            if let pdfURL = generatedPDFURL {
                ActivityViewController(activityItems: [pdfURL])
            }
        }
        .alert("PDF Export Error", isPresented: $showingPDFError) {
            Button("OK") {
                pdfError = nil
            }
        } message: {
            Text(pdfError ?? "Failed to generate PDF")
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            // Summary stats
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad layout - more space, bigger stats
                HStack(spacing: 24) {
                    // Duration if available
                    if let duration = sessionDuration, duration > 0 {
                        StatCard(
                            title: "Duration",
                            value: formatDuration(duration),
                            icon: "clock",
                            color: .indigo
                        )
                    }
                    
                    StatCard(
                        title: "Total Items",
                        value: "\(summary.totalItems)",
                        icon: "list.bullet.rectangle",
                        color: .blue
                    )

                    if !summary.actionItems.isEmpty {
                        StatCard(
                            title: "Action Items",
                            value: "\(summary.pendingActionItems.count)/\(summary.actionItems.count)",
                            icon: "checkmark.circle",
                            color: .orange
                        )
                    }

                    if !summary.urgentActionItems.isEmpty {
                        StatCard(
                            title: "Urgent",
                            value: "\(summary.urgentActionItems.count)",
                            icon: "exclamationmark.triangle",
                            color: .red
                        )
                    }
                }
            } else {
                // iPhone layout - compact
                HStack(spacing: 20) {
                    // Duration if available
                    if let duration = sessionDuration, duration > 0 {
                        StatCard(
                            title: "Duration",
                            value: formatDuration(duration),
                            icon: "clock",
                            color: .indigo
                        )
                    }
                    
                    StatCard(
                        title: "Total Items",
                        value: "\(summary.totalItems)",
                        icon: "list.bullet.rectangle",
                        color: .blue
                    )

                    if !summary.actionItems.isEmpty {
                        StatCard(
                            title: "Action Items",
                            value: "\(summary.pendingActionItems.count)/\(summary.actionItems.count)",
                            icon: "checkmark.circle",
                            color: .orange
                        )
                    }

                    if !summary.urgentActionItems.isEmpty {
                        StatCard(
                            title: "Urgent",
                            value: "\(summary.urgentActionItems.count)",
                            icon: "exclamationmark.triangle",
                            color: .red
                        )
                    }
                }
            }

            // Generated timestamp
            Text("Generated \(RelativeDateTimeFormatter().localizedString(for: summary.generatedAt, relativeTo: Date()))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableSections, id: \.self) { section in
                    SectionTab(
                        section: section,
                        isSelected: selectedSection == section,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedSection = section
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private var availableSections: [SummarySection] {
        SummarySection.allCases.filter { section in
            switch section {
            case .overview: return !summary.overview.isEmpty
            case .keyPoints: return !summary.keyPoints.isEmpty
            case .actionItems: return !summary.actionItems.isEmpty
            case .decisions: return !summary.decisions.isEmpty
            case .quotes: return !summary.quotes.isEmpty
            case .timeline: return !summary.timeline.isEmpty
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 24) {
            switch selectedSection {
            case .overview:
                if !summary.overview.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Overview", icon: "doc.text", color: .blue) {
                        Text(summary.overview)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(nil)
                    }
                }

            case .keyPoints:
                if !summary.keyPoints.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Key Points", icon: "key", color: .green) {
                        ForEach(Array(summary.keyPoints.enumerated()), id: \.element.id) { index, point in
                            KeyPointRow(point: point, index: index, onSeek: onSeekToTimestamp)
                        }
                    }
                }

            case .actionItems:
                if !summary.actionItems.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Action Items", icon: "checkmark.circle", color: .orange) {
                        ForEach(summary.actionItems) { item in
                            ActionItemRow(
                                item: item,
                                isExpanded: expandedActionItems.contains(item.id),
                                onToggleExpansion: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        if expandedActionItems.contains(item.id) {
                                            expandedActionItems.remove(item.id)
                                        } else {
                                            expandedActionItems.insert(item.id)
                                        }
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onSeek: onSeekToTimestamp
                            )
                        }
                    }
                }

            case .decisions:
                if !summary.decisions.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Decisions", icon: "arrow.triangle.branch", color: .purple) {
                        ForEach(summary.decisions) { decision in
                            DecisionRow(decision: decision, onSeek: onSeekToTimestamp)
                        }
                    }
                }

            case .quotes:
                if !summary.quotes.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Notable Quotes", icon: "quote.bubble", color: .pink) {
                        let displayQuotes = showingAllQuotes ? summary.quotes : Array(summary.quotes.prefix(3))

                        ForEach(displayQuotes) { quote in
                            QuoteRow(quote: quote, onSeek: onSeekToTimestamp)
                        }

                        if summary.quotes.count > 3 {
                            Button(showingAllQuotes ? "Show Less" : "Show All (\(summary.quotes.count))") {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showingAllQuotes.toggle()
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                        }
                    }
                }

            case .timeline:
                if !summary.timeline.isEmpty {
                    SectionView(id: selectedSection.rawValue, title: "Timeline", icon: "timeline.selection", color: .indigo) {
                        ForEach(summary.timeline) { entry in
                            TimelineRow(entry: entry, onSeek: onSeekToTimestamp)
                        }
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration <= 0 {
            return "Unknown"
        }
        
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - PDF Generation
    
    private func generatingPDFPostAllProcess() {
        do {
            let pdfTitle = sessionTitle ?? "AI Summary - \(Date().formatted(date: .abbreviated, time: .shortened))"
            let pdfURL = try di.pdf.buildPDF(from: summary, sessionDuration: sessionDuration, sessionTitle: pdfTitle)
            
            generatedPDFURL = pdfURL
            showingPDFShare = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            pdfError = error.localizedDescription
            showingPDFError = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        
        isGeneratingPDF = false
    }
    
    @MainActor
    private func generatePDF() async {
        isGeneratingPDF = true

        // Show ads only for free users
        if di.featureManager.shouldShowAds() && di.adManager.isAdReady, let rootVC = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
            di.adManager.presentInterstitial(from: rootVC) { _ in
                generatingPDFPostAllProcess()
            }
        } else {
            generatingPDFPostAllProcess()
        }

    }
    
    // MARK: - Copy Summary
    
    private func generateSummaryText() -> String {
        var text = ""
        
        // Title
        let title = sessionTitle ?? "Meeting Summary"
        text += "\(title)\n\n"
        
        // Metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        text += "Generated: \(dateFormatter.string(from: summary.generatedAt))\n"
        
        if let duration = sessionDuration, duration > 0 {
            text += "Duration: \(formatDuration(duration))\n"
        }
        text += "\n"
        
        // Overview
        if !summary.overview.isEmpty {
            text += "📋 Overview\n"
            text += "\(summary.overview)\n\n"
        }
        
        // Key Points
        if !summary.keyPoints.isEmpty {
            text += "🔑 Key Points\n"
            for point in summary.keyPoints {
                text += "• \(point.text)\n"
            }
            text += "\n"
        }
        
        // Action Items
        if !summary.actionItems.isEmpty {
            text += "✅ Action Items\n"
            for item in summary.actionItems {
                text += "• \(item.text)"
                
                var details: [String] = []
                if let owner = item.owner {
                    details.append("@\(owner)")
                }
                if let dueDate = item.dueDateFormatted {
                    details.append("Due: \(dueDate)")
                }
                if let priority = item.priority {
                    details.append("Priority: \(priority.rawValue.capitalized)")
                }
                
                if !details.isEmpty {
                    text += " (\(details.joined(separator: ", ")))"
                }
                
                text += "\n"
            }
            text += "\n"
        }
        
        // Decisions
        if !summary.decisions.isEmpty {
            text += "🎯 Decisions\n"
            for decision in summary.decisions {
                text += "• \(decision.text)"
                if let impact = decision.impact {
                    text += " (Impact: \(impact.rawValue.capitalized))"
                }
                text += "\n"
            }
            text += "\n"
        }
        
        // Notable Quotes
        if !summary.quotes.isEmpty {
            text += "💬 Notable Quotes\n"
            for quote in summary.quotes {
                text += "\"\(quote.text)\""
                if let speaker = quote.speaker {
                    text += " — \(speaker)"
                }
                if let context = quote.context {
                    text += " (\(context))"
                }
                text += "\n\n"
            }
        }
        
        // Timeline
        if !summary.timeline.isEmpty {
            text += "⏱️ Timeline\n"
            for entry in summary.timeline {
                text += "• \(entry.text)"
                if let importance = entry.importance {
                    text += " (\(importance.rawValue.capitalized) importance)"
                }
                text += "\n"
            }
        }
        
        return text
    }
    
    private func copySummaryPostAllProcess() {
        let summaryText = generateSummaryText()
        UIPasteboard.general.string = summaryText
        
        showingCopySuccess = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Hide the success message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopySuccess = false
        }
    }
    
    @MainActor
    private func copySummaryToClipboard() async {
        // Show ads only for free users
        if di.featureManager.shouldShowAds() && di.adManager.isAdReady, let rootVC = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController {
            di.adManager.presentInterstitial(from: rootVC) { _ in
                copySummaryPostAllProcess()
            }
        } else {
            copySummaryPostAllProcess()
        }
    }
    
    // MARK: - Ad Integration methods moved to AdIntegrationExtension.swift
}

// MARK: - Activity View Controller for PDF Sharing
// (Using shared ActivityViewController from RecordListView.swift)

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

struct SectionTab: View {
    let section: SummaryView.SummarySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))

                Text(section.rawValue)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : section.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? section.color : section.color.opacity(0.15))
            )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct SectionView<Content: View>: View {
    let id: String
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .id(id)
    }
}

struct KeyPointRow: View {
    let point: Summary.Point
    let index: Int
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.green.gradient)
                .frame(width: 8, height: 8)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(point.text)
                    .font(.body)
                    .foregroundColor(.primary)

                if let refs = point.refs, !refs.validRefs.isEmpty {
                    TimestampChips(refs: refs, onSeek: onSeek)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ActionItemRow: View {
    let item: Summary.ActionItem
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggleExpansion) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(statusColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 12) {
                            if let owner = item.owner {
                                Label(owner, systemImage: "person.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let date = item.dueDateFormatted {
                                Label(date, systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let priority = item.priority {
                                PriorityBadge(priority: priority)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded, let refs = item.refs, !refs.validRefs.isEmpty {
                TimestampChips(refs: refs, onSeek: onSeek)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case .pending: return "circle"
        case .inProgress: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .pending: return .orange
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}

struct PriorityBadge: View {
    let priority: Summary.ActionItem.Priority

    var body: some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(priorityColor)
            )
    }

    private var priorityColor: Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .urgent: return .purple
        }
    }
}

struct DecisionRow: View {
    let decision: Summary.Decision
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.purple)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(decision.text)
                    .font(.body)
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    if let impact = decision.impact {
                        ImpactBadge(impact: impact)
                    }

                    if let refs = decision.refs, !refs.validRefs.isEmpty {
                        TimestampChips(refs: refs, onSeek: onSeek)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ImpactBadge: View {
    let impact: Summary.Decision.Impact

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "impact")
                .font(.caption2)

            Text(impact.rawValue.capitalized)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(.secondary)
    }
}

struct QuoteRow: View {
    let quote: Summary.Quote
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.pink)

                VStack(alignment: .leading, spacing: 8) {
                    Text(quote.text)
                        .font(.body.italic())
                        .foregroundColor(.primary)

                    if let speaker = quote.speaker {
                        Text("— \(speaker)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }

                    if let context = quote.context {
                        Text(context)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if let refs = quote.refs, !refs.validRefs.isEmpty {
                TimestampChips(refs: refs, onSeek: onSeek)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TimelineRow: View {
    let entry: Summary.TimelineEntry
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Button(action: {
            if let timeInterval = entry.at.timeInterval {
                onSeek(timeInterval)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(importanceColor)
                        .frame(width: 10, height: 10)

                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                .frame(height: 50)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.at)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)

                    Text(entry.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var importanceColor: Color {
        guard let importance = entry.importance else { return .indigo }
        switch importance {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct TimestampChips: View {
    let refs: [Summary.Ref]
    let onSeek: (TimeInterval) -> Void
    
    var body: some View {
        let validTimestamps = refs.validRefs
        if !validTimestamps.isEmpty {
            HStack(spacing: 8) {
                ForEach(validTimestamps) { ref in
                    Button(action: {
                        if let startTime = ref.startTimeInterval {
                            onSeek(startTime)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))

                            Text(ref.formattedRange)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.gradient)
                        )
                    }
                    .scaleEffect(1.0)
                    .onTapGesture {
                        // Add button press animation
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

private extension Array where Element == Summary.Ref {
    var validRefs: [Summary.Ref] {
        self.filter { ref in
            // Filter out refs with invalid timestamps (00:00:00 - 00:00:00)
            return !(ref.start == "00:00:00" && ref.end == "00:00:00") && 
                   ref.startTimeInterval != nil && ref.endTimeInterval != nil &&
                   (ref.startTimeInterval! >= 0) && (ref.endTimeInterval! >= 0)
        }
    }
}

private extension String {
    var timeInterval: TimeInterval? {
        let components = self.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        let hours = components[0]
        let minutes = components[1]
        let seconds = components[2]
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}

func generateHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let impactFeedback = UIImpactFeedbackGenerator(style: style)
    impactFeedback.prepare()
    impactFeedback.impactOccurred()
}

// MARK: - Preview

#Preview {
    let sampleSummary = Summary(
        overview: "This was a productive team meeting where we discussed project milestones, made key decisions about the upcoming release, and assigned action items for the next sprint.",
        keyPoints: [
            Summary.Point(text: "Q4 targets are on track with current velocity", refs: [Summary.Ref(start: "00:05:12", end: "00:06:30")]),
            Summary.Point(text: "New feature rollout scheduled for next month", refs: [Summary.Ref(start: "00:15:45", end: "00:17:10")])
        ],
        actionItems: [
            Summary.ActionItem(text: "Complete user testing for new dashboard", owner: "Sarah", dueDateISO8601: "2025-08-25", priority: .high, refs: [Summary.Ref(start: "00:12:30", end: "00:13:45")]),
            Summary.ActionItem(text: "Review and approve marketing materials", owner: "Mike", dueDateISO8601: "2025-08-20", priority: .medium, refs: [Summary.Ref(start: "00:20:15", end: "00:21:30")])
        ],
        decisions: [
            Summary.Decision(text: "Move forward with React Native for mobile app", impact: .high, refs: [Summary.Ref(start: "00:25:10", end: "00:26:45")])
        ],
        quotes: [
            Summary.Quote(speaker: "John", text: "We need to prioritize user experience over feature completeness", context: "During mobile app discussion", refs: [Summary.Ref(start: "00:18:20", end: "00:18:35")])
        ],
        timeline: [
            Summary.TimelineEntry(at: "00:05:00", text: "Meeting started - introductions", importance: .medium),
            Summary.TimelineEntry(at: "00:15:30", text: "Feature discussion began", importance: .high)
        ]
    )

    SummaryView(summary: sampleSummary, sessionDuration: 1800, sessionTitle: "Sample Recording") { timestamp in
    }
}
