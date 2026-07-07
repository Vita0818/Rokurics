//
//  RecordingUploadStatus.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Foundation

nonisolated enum RecordingUploadStatus: String, Codable, Equatable {
    case localOnly
    case uploading
    case uploaded
    case failed

    init(rawMetadataValue: String) {
        self = RecordingUploadStatus(rawValue: rawMetadataValue) ?? .localOnly
    }

    var displayText: String {
        switch self {
        case .localOnly:
            return RokuricsCopy.text("未上传", "Not uploaded")
        case .uploading:
            return RokuricsCopy.text("上传中", "Uploading")
        case .uploaded:
            return RokuricsCopy.text("已上传", "Uploaded")
        case .failed:
            return RokuricsCopy.text("上传失败", "Upload failed")
        }
    }
}
