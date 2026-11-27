import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Keeps imported originals inside the app (bit-identical copies, never transcoded).
enum MediaStore {
    static var mediaDirectory: URL {
        let dir = URL.documentsDirectory.appending(path: "Media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var exportDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newMediaURL(fileExtension ext: String) -> URL {
        let cleanExt = ext.isEmpty ? "mov" : ext.lowercased()
        return mediaDirectory.appending(path: "\(UUID().uuidString).\(cleanExt)")
    }

    static func copyIntoLibrary(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = newMediaURL(fileExtension: source.pathExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func newExportURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return exportDirectory.appending(path: "FrameCut-\(formatter.string(from: .now)).mov")
    }

    static func deleteEverything() {
        try? FileManager.default.removeItem(at: mediaDirectory)
        try? FileManager.default.removeItem(at: exportDirectory)
    }
}

/// Video from the Photos picker. Used with `preferredItemEncoding: .current`,
/// so iOS hands over the original file (HEVC/ProRes/HDR/Dolby Vision untouched).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = MediaStore.newMediaURL(fileExtension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
