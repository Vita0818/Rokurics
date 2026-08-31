import Foundation

// Legacy decode-only records retained so existing receive.json files remain
// readable after the old whisper/chunking runtime is removed.

enum ProcessingMode: String, Codable, Equatable {
    case single
    case chunked
}

enum ProcessingChunkStatus: String, Codable, Equatable {
    case pending
    case processing
    case generated
    case failed
}

struct AudioChunkDescriptor: Codable, Equatable, Identifiable {
    var id: String { "chunk_\(String(format: "%03d", index))" }
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { max(0, endTime - startTime) }
}

struct RecordingTranscriptionChunkRecord: Codable, Equatable {
    var index: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var status: ProcessingChunkStatus
    var transcriptRelativePath: String?
    var transcriptMarkdownRelativePath: String?
    var error: String?

    init(
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        status: ProcessingChunkStatus = .pending,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        error: String? = nil
    ) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.transcriptRelativePath = transcriptRelativePath
        self.transcriptMarkdownRelativePath = transcriptMarkdownRelativePath
        self.error = error
    }

    init(
        descriptor: AudioChunkDescriptor,
        status: ProcessingChunkStatus = .pending,
        error: String? = nil
    ) {
        self.init(
            index: descriptor.index,
            startTime: descriptor.startTime,
            endTime: descriptor.endTime,
            status: status,
            error: error
        )
    }
}

struct RecordingNoteSectionRecord: Codable, Equatable {
    var index: Int
    var sourceStart: Int
    var sourceEnd: Int
    var status: ProcessingChunkStatus
    var sectionNoteRelativePath: String?
    var error: String?

    init(
        index: Int,
        sourceStart: Int,
        sourceEnd: Int,
        status: ProcessingChunkStatus = .pending,
        sectionNoteRelativePath: String? = nil,
        error: String? = nil
    ) {
        self.index = index
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.status = status
        self.sectionNoteRelativePath = sectionNoteRelativePath
        self.error = error
    }
}
