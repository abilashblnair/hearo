import SwiftUI

struct SaveRecordingPopupView: View {
    let duration: TimeInterval
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void
    
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isNotesExpanded: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool
    
    private var defaultTitle: String {
        "Session " + Date.now.formatted(date: .abbreviated, time: .shortened)
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Main popup card
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    // Success icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                    }
                    
                    Text("Recording Saved!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Duration: \(timeString(from: duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                // Form section
                VStack(spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Title")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("(will use default)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TextField("Enter recording title", text: $title)
                            .focused($isTitleFocused)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .submitLabel(.next)
                            .onSubmit {
                                isNotesFocused = true
                            }
                    }
                    
                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Notes")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("(Optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isNotesExpanded.toggle()
                                    if isNotesExpanded {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isNotesFocused = true
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                    Text(isNotesExpanded ? "Collapse" : "Add notes")
                                        .font(.caption)
                                }
                                .foregroundColor(.accentColor)
                            }
                        }
                        
                        if isNotesExpanded {
                            VStack(alignment: .leading, spacing: 4) {
                                TextEditor(text: $notes)
                                    .focused($isNotesFocused)
                                    .frame(minHeight: 80, maxHeight: 120)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                
                                Text("Add context, key topics, or important points about this recording")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .transition(.opacity)
                            }
                        } else if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))\(notes.count > 50 ? "..." : "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    
                    Button("Save") {
                        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title
                        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(finalTitle, finalNotes)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isNotesExpanded)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    SaveRecordingPopupView(
        duration: 125.5,
        onSave: { title, notes in
            print("Save: \(title), Notes: \(notes ?? "none")")
        },
        onCancel: {
            print("Cancel")
        }
    )
}
