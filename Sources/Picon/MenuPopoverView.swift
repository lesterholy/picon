import SwiftUI
import PiconCore

struct MenuPopoverView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(model.lastMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Divider()

            batchSection

            Divider()

            imageSection(title: "Pending", emptyText: "Copy a screenshot or image file. It will appear here before upload.") {
                ForEach(model.pending) { entry in
                    ImageRow(entry: entry, remove: {
                        model.removePending(id: entry.id)
                    }) {
                        model.uploadPending(id: entry.id)
                    }
                }
            }

            Divider()

            imageSection(title: "Uploaded", emptyText: "Uploaded images will stay here for quick Markdown copying.") {
                ForEach(model.uploaded) { entry in
                    ImageRow(entry: entry, remove: nil) {
                        model.copyMarkdown(id: entry.id)
                    }
                }
            }

            Divider()

            HStack {
                Button("Upload Folder...") {
                    model.chooseFolderForBatchUpload()
                }
                Button("Reveal Upload Folder") {
                    model.revealUploadDirectory()
                }
                Spacer()
                Button("Quit") {
                    quit()
                }
            }
        }
        .padding(14)
        .frame(width: 430, height: 620, alignment: .topLeading)
    }

    @ViewBuilder
    private var batchSection: some View {
        if let batch = model.batch {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch")
                            .font(.headline)
                        Text("\(batch.profileName) - \(batch.uploadedCount)/\(batch.totalCount) uploaded, \(batch.failedCount) failed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(batch.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(batch.failedCount > 0 ? .red : .secondary)
                }

                ProgressView(value: batch.totalCount == 0 ? 0 : Double(batch.uploadedCount + batch.failedCount), total: Double(max(batch.totalCount, 1)))

                HStack {
                    Button(batch.status == .ready ? "Start Upload" : "Upload Remaining") {
                        model.startBatchUpload()
                    }
                    .disabled(batch.status == .uploading || batch.pendingCount == 0)

                    Button("Retry Failed") {
                        model.retryFailedBatchItems()
                    }
                    .disabled(batch.failedCount == 0 || batch.status == .uploading)

                    Button("Copy All Markdown") {
                        model.copyBatchMarkdown()
                    }
                    .disabled(batch.uploadedCount == 0)

                    Spacer()

                    Button("Clear") {
                        model.clearBatch()
                    }
                    .disabled(batch.status == .uploading)
                }
                .font(.caption)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .imageScale(.large)
            Text("Picon")
                .font(.headline)
            Spacer()
            Button {
                model.scanPasteboardNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh clipboard status")
            Button("Settings") {
                openSettings()
            }
        }
    }

    private func imageSection<Content: View>(
        title: String,
        emptyText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                let isEmpty = title == "Pending" ? model.pending.isEmpty : model.uploaded.isEmpty
                if isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 8) {
                        content()
                    }
                }
            }
            .frame(height: title == "Pending" ? 155 : 180)
        }
    }

}

private struct ImageRow: View {
    let entry: ImageEntry
    let remove: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: entry.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 58, height: 58)
                    .clipped()
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.record.originalFileName ?? "clipboard image")
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(entry.record.objectKey)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                }

                Spacer()

                if let remove {
                    Button {
                        remove()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(entry.record.status == .uploading)
    }

    private var statusText: String {
        switch entry.record.status {
        case .pending:
            if let url = entry.record.publicURL {
                return MarkdownFormatter.image(url: url)
            }
            return "Pending"
        case .uploading:
            return "Uploading"
        case .uploaded:
            return entry.record.markdown ?? "Uploaded"
        case .failed:
            return entry.record.errorMessage ?? "Upload failed"
        }
    }

    private var statusColor: Color {
        switch entry.record.status {
        case .failed:
            return .red
        case .uploaded:
            return .green
        default:
            return .secondary
        }
    }
}
