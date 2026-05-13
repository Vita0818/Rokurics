//
//  TranscriptionError.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

enum TranscriptionError: LocalizedError {
    case providerNotConfigured
    case unsupportedProvider(String)
    case executablePathMissing
    case executableNotFound
    case executableIsDirectory
    case executableNotExecutable
    case modelPathMissing
    case modelNotFound
    case modelIsDirectory
    case audioFileMissing
    case outputDirectoryUnavailable
    case outputDirectoryNotWritable
    case processLaunchFailed(String)
    case processTimedOut
    case processFailed(exitCode: Int32, message: String)
    case outputMissing
    case outputDecodeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "转写引擎未配置"
        case .unsupportedProvider(let provider):
            return "\(provider) 暂未支持"
        case .executablePathMissing:
            return "whisper.cpp 可执行文件路径未配置"
        case .executableNotFound:
            return "可执行文件不存在"
        case .executableIsDirectory:
            return "可执行文件路径指向了文件夹"
        case .executableNotExecutable:
            return "文件不可执行"
        case .modelPathMissing:
            return "模型文件路径未配置"
        case .modelNotFound:
            return "模型文件不存在"
        case .modelIsDirectory:
            return "模型路径指向了文件夹"
        case .audioFileMissing:
            return "音频文件不存在"
        case .outputDirectoryUnavailable:
            return "转写输出目录不可用"
        case .outputDirectoryNotWritable:
            return "转写输出目录不可写"
        case .processLaunchFailed:
            return "whisper.cpp 启动失败"
        case .processTimedOut:
            return "whisper.cpp 执行超时"
        case .processFailed(_, let message):
            return message.isEmpty ? "whisper.cpp 执行失败" : message
        case .outputMissing:
            return "没有生成转写文本"
        case .outputDecodeFailed:
            return "转写文本读取失败"
        case .cancelled:
            return "转写已取消"
        }
    }
}

