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
    case executableBookmarkMissing
    case executableBookmarkRestoreFailed
    case executableBookmarkStale
    case executableSandboxAccessDenied
    case executableEntitlementMissing
    case bookmarkEntitlementMissing
    case modelPathMissing
    case modelNotFound
    case modelIsDirectory
    case modelBookmarkMissing
    case modelBookmarkRestoreFailed
    case modelBookmarkStale
    case modelSandboxAccessDenied
    case whisperCppRootDirectoryPathMissing
    case whisperCppRootDirectoryNotFound
    case whisperCppRootDirectoryIsFile
    case whisperCppRootDirectoryBookmarkMissing
    case whisperCppRootDirectoryBookmarkRestoreFailed
    case whisperCppRootDirectoryBookmarkStale
    case whisperCppRootDirectorySandboxAccessDenied
    case whisperCppRootDirectoryInvalid(String)
    case whisperCppRootDirectoryAccessFailed(String)
    case ffmpegPathMissing
    case ffmpegNotFound
    case ffmpegIsDirectory
    case ffmpegNotExecutable
    case ffmpegBookmarkMissing
    case ffmpegBookmarkRestoreFailed
    case ffmpegBookmarkStale
    case ffmpegSandboxAccessDenied
    case ffmpegEntitlementMissing
    case audioFileMissing
    case outputDirectoryUnavailable
    case outputDirectoryNotWritable
    case audioConversionLaunchFailed(String)
    case audioConversionTimedOut
    case audioConversionFailed(exitCode: Int32, message: String)
    case convertedAudioMissing(String)
    case nativeAudioReaderFailed(stage: String, message: String)
    case nativeAudioConverterFailed(stage: String, message: String)
    case nativeWAVWritingFailed(stage: String, message: String)
    case nativeAudioConversionFailed(stage: String, message: String)
    case nativeOutputWAVMissing(String)
    case nativeOutputWAVEmpty(String)
    case processLaunchFailed(String)
    case processTimedOut
    case processFailed(exitCode: Int32, message: String)
    case outputMissing(String)
    case outputEmpty(String)
    case outputDecodeFailed(String)
    case transcriptStoreWriteFailed(String)
    case receiveJSONUpdateFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "转写引擎未配置"
        case .unsupportedProvider(let provider):
            return "\(provider) 暂未支持"
        case .executablePathMissing:
            return "尚未选择文件，请通过“选择文件”授权。"
        case .executableNotFound:
            return "whisper.cpp 可执行文件不存在"
        case .executableIsDirectory:
            return "whisper.cpp 可执行文件路径指向了文件夹"
        case .executableNotExecutable:
            return "whisper.cpp 可执行文件没有 POSIX 可执行权限"
        case .executableBookmarkMissing:
            return "路径已填写，但尚未获得 sandbox 授权。请点击右侧“选择文件”重新选择，不要手动输入路径。"
        case .executableBookmarkRestoreFailed:
            return "已保存的 sandbox 授权无法恢复，请重新选择文件。"
        case .executableBookmarkStale:
            return "已保存的 sandbox 授权已过期，请重新选择文件。"
        case .executableSandboxAccessDenied:
            return "已保存的 sandbox 授权无法启用，请点击“重置授权”后重新选择文件，并确认运行的是最新构建。"
        case .executableEntitlementMissing:
            return "RokuricsMac 缺少 user-selected executable entitlement，无法执行外部 whisper.cpp"
        case .bookmarkEntitlementMissing:
            return "当前 App 缺少 app-scope bookmark entitlement。"
        case .modelPathMissing:
            return "尚未选择文件，请通过“选择文件”授权。"
        case .modelNotFound:
            return "模型文件不存在"
        case .modelIsDirectory:
            return "模型路径指向了文件夹"
        case .modelBookmarkMissing:
            return "路径已填写，但尚未获得 sandbox 授权。请点击右侧“选择文件”重新选择，不要手动输入路径。"
        case .modelBookmarkRestoreFailed:
            return "已保存的 sandbox 授权无法恢复，请重新选择文件。"
        case .modelBookmarkStale:
            return "已保存的 sandbox 授权已过期，请重新选择文件。"
        case .modelSandboxAccessDenied:
            return "已保存的 sandbox 授权无法启用，请点击“重置授权”后重新选择文件，并确认运行的是最新构建。"
        case .whisperCppRootDirectoryPathMissing:
            return "请在设置页授权 whisper.cpp 根目录，以允许 whisper-cli 访问 @rpath 动态库依赖。"
        case .whisperCppRootDirectoryNotFound:
            return "whisper.cpp 根目录不存在"
        case .whisperCppRootDirectoryIsFile:
            return "whisper.cpp 根目录路径指向了文件，请选择文件夹"
        case .whisperCppRootDirectoryBookmarkMissing:
            return "路径已填写，但尚未获得 whisper.cpp 根目录 sandbox 授权。请点击“选择目录”重新选择。"
        case .whisperCppRootDirectoryBookmarkRestoreFailed:
            return "已保存的 whisper.cpp 根目录 sandbox 授权无法恢复，请重新选择目录。"
        case .whisperCppRootDirectoryBookmarkStale:
            return "已保存的 whisper.cpp 根目录 sandbox 授权已过期，请重新选择目录。"
        case .whisperCppRootDirectorySandboxAccessDenied:
            return "已保存的 whisper.cpp 根目录 sandbox 授权无法启用，请重新选择目录。"
        case .whisperCppRootDirectoryInvalid(let message):
            return message.isEmpty ? "whisper.cpp 根目录结构不完整" : message
        case .whisperCppRootDirectoryAccessFailed(let message):
            return message.isEmpty ? "whisper.cpp 根目录授权失败" : message
        case .ffmpegPathMissing:
            return "当前 whisper.cpp 不能直接读取 m4a，请配置 ffmpeg 用于转换为 wav。"
        case .ffmpegNotFound:
            return "ffmpeg 可执行文件不存在"
        case .ffmpegIsDirectory:
            return "ffmpeg 路径指向了文件夹"
        case .ffmpegNotExecutable:
            return "ffmpeg 文件没有 POSIX 可执行权限"
        case .ffmpegBookmarkMissing:
            return "缺少 ffmpeg sandbox 授权，请在设置页重新选择 ffmpeg。"
        case .ffmpegBookmarkRestoreFailed:
            return "已保存的 sandbox 授权无法恢复，请重新选择文件。"
        case .ffmpegBookmarkStale:
            return "已保存的 sandbox 授权已过期，请重新选择文件。"
        case .ffmpegSandboxAccessDenied:
            return "已保存的 sandbox 授权无法启用，请点击“重置授权”后重新选择文件，并确认运行的是最新构建。"
        case .ffmpegEntitlementMissing:
            return "RokuricsMac 缺少 user-selected executable entitlement，无法执行外部 ffmpeg"
        case .audioFileMissing:
            return "音频文件不存在"
        case .outputDirectoryUnavailable:
            return "转写输出目录不可用"
        case .outputDirectoryNotWritable:
            return "转写输出目录不可写"
        case .audioConversionLaunchFailed(let message):
            if message.isEmpty {
                return "ffmpeg 启动失败"
            }
            return message.hasPrefix("ffmpeg 启动失败") ? message : "ffmpeg 启动失败：\(message)"
        case .audioConversionTimedOut:
            return "ffmpeg 转码超时"
        case .audioConversionFailed(_, let message):
            return message.isEmpty ? "ffmpeg 转码失败" : message
        case .convertedAudioMissing(let message):
            return message.isEmpty ? "ffmpeg 转码完成后没有生成 wav 文件" : message
        case let .nativeAudioReaderFailed(stage, message):
            return Self.nativeAudioConversionMessage(
                stage: stage,
                message: message,
                fallback: "native audio reader failed"
            )
        case let .nativeAudioConverterFailed(stage, message):
            return Self.nativeAudioConversionMessage(
                stage: stage,
                message: message,
                fallback: "native audio converter failed"
            )
        case let .nativeWAVWritingFailed(stage, message):
            return Self.nativeAudioConversionMessage(
                stage: stage,
                message: message,
                fallback: "native wav writing failed"
            )
        case let .nativeAudioConversionFailed(stage, message):
            return Self.nativeAudioConversionMessage(
                stage: stage,
                message: message,
                fallback: "native audio conversion failed"
            )
        case .nativeOutputWAVMissing(let message):
            return message.isEmpty ? "native audio conversion failed: output wav missing" : message
        case .nativeOutputWAVEmpty(let message):
            return message.isEmpty ? "native audio conversion failed: output wav empty" : message
        case .processLaunchFailed(let message):
            if message.isEmpty {
                return "whisper.cpp 启动失败"
            }
            return message.hasPrefix("whisper") ? message : "whisper.cpp 启动失败：\(message)"
        case .processTimedOut:
            return "whisper.cpp 执行超时"
        case .processFailed(_, let message):
            return message.isEmpty ? "whisper.cpp 执行失败" : message
        case .outputMissing(let message):
            return message.isEmpty ? "没有生成转写文本" : message
        case .outputEmpty(let message):
            return message.isEmpty ? "转写文本为空" : message
        case .outputDecodeFailed(let message):
            return message.isEmpty ? "转写文本读取失败" : message
        case .transcriptStoreWriteFailed(let message):
            return message.isEmpty ? "transcript.json / transcript.md 写入失败" : message
        case .receiveJSONUpdateFailed(let message):
            return message.isEmpty ? "receive.json 写回失败" : message
        case .cancelled:
            return "转写已取消"
        }
    }

    private static func nativeAudioConversionMessage(
        stage: String,
        message: String,
        fallback: String
    ) -> String {
        let normalizedStage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStage.isEmpty || !normalizedMessage.isEmpty else {
            return fallback
        }

        return [
            "native audio conversion failed:",
            normalizedStage.isEmpty ? nil : "stage=\(normalizedStage)",
            normalizedMessage.isEmpty ? nil : "message=\(normalizedMessage)"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
