import SwiftUI

struct ClearDataConfirmationView: View {
    @Binding var confirmationText: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let storageStats: StorageStats?
    
    @State private var isTypingCorrect = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Warning Icon
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("⚠️ Final Confirmation")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                // Data to be deleted summary
                VStack(spacing: 16) {
                    Text("You are about to permanently delete:")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let stats = storageStats {
                        VStack(alignment: .leading, spacing: 8) {
                            DataSummaryRow(icon: "doc.text.fill", text: "\(stats.totalRecordings) recordings")
                            DataSummaryRow(icon: "folder.fill", text: "\(stats.totalFolders - 1) custom folders")
                            DataSummaryRow(icon: "text.bubble.fill", text: "All transcripts & summaries")
                            DataSummaryRow(icon: "music.note", text: "\(stats.formattedFileSize) of audio data")
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemRed).opacity(0.1))
                                .stroke(Color(.systemRed), lineWidth: 1)
                        )
                    } else {
                        Text("• All recordings and audio files\n• All transcripts and summaries\n• All custom folders\n• All user data")
                            .multilineTextAlignment(.leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemRed).opacity(0.1))
                            )
                    }
                }
                
                // Warning text
                VStack(spacing: 8) {
                    Text("This action cannot be undone!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    
                    Text("To confirm this destructive action, please type 'DELETE' in the field below:")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Confirmation text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type 'DELETE' to confirm:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("DELETE", text: $confirmationText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onReceive(confirmationText.publisher.last()) { _ in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTypingCorrect = confirmationText.uppercased() == "DELETE"
                            }
                        }
                    
                    // Real-time feedback
                    HStack {
                        if confirmationText.isEmpty {
                            Text("Enter 'DELETE' to enable confirmation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if isTypingCorrect {
                            Label("Ready to delete", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label("Must type exactly 'DELETE'", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Data")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isTypingCorrect ? Color.red : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isTypingCorrect)
                    .scaleEffect(isTypingCorrect ? 1.0 : 0.95)
                    .animation(.easeInOut(duration: 0.2), value: isTypingCorrect)
                    
                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .navigationTitle("Clear All Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct DataSummaryRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 20)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    ClearDataConfirmationView(
        confirmationText: .constant(""),
        onConfirm: {},
        onCancel: {},
        storageStats: StorageStats(
            totalRecordings: 25,
            totalFolders: 4,
            emptyFolders: 1,
            totalDuration: 3600,
            totalAudioFileSize: 156789012
        )
    )
}

