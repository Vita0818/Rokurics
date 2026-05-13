//
//  RecordingUploadStatus.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Foundation

enum RecordingUploadStatus: String, Codable, Equatable {
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
            return "未上传"
        case .uploading:
            return "上传中"
        case .uploaded:
            return "已上传"
        case .failed:
            return "上传失败"
        }
    }
}
