//
//  NoteGenerationError.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

enum NoteGenerationError: LocalizedError, Equatable {
    case transcriptNotReady
    case transcriptDocumentMissing
    case transcriptReadFailed
    case transcriptDecodeFailed
    case noteStoreWriteFailed(String)
    case receiveJSONUpdateFailed(String)
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .transcriptNotReady:
            return "transcript_not_ready"
        case .transcriptDocumentMissing:
            return "未找到可用于生成笔记的转写文档"
        case .transcriptReadFailed:
            return "无法读取转写文档"
        case .transcriptDecodeFailed:
            return "无法解析结构化转写"
        case .noteStoreWriteFailed(let reason):
            return reason
        case .receiveJSONUpdateFailed(let reason):
            return reason
        case .unsupportedProvider(let providerName):
            return "\(providerName) 暂未支持"
        }
    }
}
