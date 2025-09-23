import SwiftUI
import UniformTypeIdentifiers

struct ExportSuccessView: View {
    let result: StorageExportResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Success Icon and Title
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Export Successful!")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                // Export Statistics
                VStack(spacing: 12) {
                    ExportStatRow(
                        icon: "doc.text.fill",
                        title: "Recordings",
                        value: "\(result.recordingsCount)"
                    )
                    
                    ExportStatRow(
                        icon: "folder.fill",
                        title: "Folders",
                        value: "\(result.foldersCount)"
                    )
                    
                    ExportStatRow(
                        icon: "music.note",
                        title: "Audio Files",
                        value: "\(result.audioFilesCount)"
                    )
                    
                    ExportStatRow(
                        icon: "internaldrive.fill",
                        title: "Total Size",
                        value: result.formattedFileSize
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                
                // Export Information
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Details")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Your data has been exported as a ZIP archive containing:")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint(text: "metadata.json - All recording and folder information")
                        BulletPoint(text: "audio/ - All your audio files")
                        BulletPoint(text: "Organized by recording ID for easy restoration")
                    }
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    ShareLink(
                        item: result.exportURL,
                        preview: SharePreview(
                            "HearO Data Export",
                            image: Image(systemName: "folder.fill.badge.plus")
                        )
                    ) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Export File")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button("Save to Files") {
                        saveToFiles()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .navigationTitle("Export Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(nil, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveToFiles() {
        let documentPicker = UIDocumentPickerViewController(forExporting: [result.exportURL])
        documentPicker.modalPresentationStyle = .formSheet
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(documentPicker, animated: true)
        }
    }
}

struct ExportStatRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.blue)
                .fontWeight(.bold)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ExportSuccessView(
        result: StorageExportResult(
            exportURL: URL(fileURLWithPath: "/tmp/export.zip"),
            recordingsCount: 25,
            foldersCount: 4,
            audioFilesCount: 23,
            fileSize: 156789012
        )
    )
}

