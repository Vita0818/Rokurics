//
//  TranscriptionSettingsStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Combine
import Foundation

protocol TranscriptionSettingsDefaults {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: TranscriptionSettingsDefaults {}

enum TranscriptionConfigurationValidationStatus: String, Codable, Equatable {
    case notConfigured
    case valid
    case executableNotFound
    case executableIsDirectory
    case executableNotExecutable
    case executableAccessDenied
    case executableEntitlementMissing
    case bookmarkEntitlementMissing
    case modelNotFound
    case modelIsDirectory
    case modelAccessDenied
    case whisperCppRootDirectoryNotFound
    case whisperCppRootDirectoryIsFile
    case whisperCppRootDirectoryAccessDenied
    case whisperCppRootDirectoryInvalid
    case ffmpegNotFound
    case ffmpegIsDirectory
    case ffmpegNotExecutable
    case ffmpegAccessDenied
    case ffmpegEntitlementMissing
    case outputDirectoryNotWritable
    case checkFailed

    var displayText: String {
        switch self {
        case .notConfigured:
            return "未配置"
        case .valid:
            return "配置有效"
        case .executableNotFound:
            return "可执行文件不存在"
        case .executableIsDirectory:
            return "可执行文件路径是文件夹"
        case .executableNotExecutable:
            return "缺少执行权限"
        case .executableAccessDenied:
            return "未授权"
        case .executableEntitlementMissing:
            return "缺少执行授权"
        case .bookmarkEntitlementMissing:
            return "缺少书签授权"
        case .modelNotFound:
            return "模型文件不存在"
        case .modelIsDirectory:
            return "模型路径是文件夹"
        case .modelAccessDenied:
            return "模型未授权"
        case .whisperCppRootDirectoryNotFound:
            return "根目录不存在"
        case .whisperCppRootDirectoryIsFile:
            return "根目录不是文件夹"
        case .whisperCppRootDirectoryAccessDenied:
            return "根目录未授权"
        case .whisperCppRootDirectoryInvalid:
            return "根目录不完整"
        case .ffmpegNotFound:
            return "ffmpeg 不存在"
        case .ffmpegIsDirectory:
            return "ffmpeg 路径是文件夹"
        case .ffmpegNotExecutable:
            return "ffmpeg 缺少执行权限"
        case .ffmpegAccessDenied:
            return "ffmpeg 未授权"
        case .ffmpegEntitlementMissing:
            return "缺少执行授权"
        case .outputDirectoryNotWritable:
            return "输出目录不可写"
        case .checkFailed:
            return "检查失败"
        }
    }
}

final class TranscriptionSettingsStore: ObservableObject {
    static let shared = TranscriptionSettingsStore()

    @Published var selectedProviderKind: TranscriptionProviderKind {
        didSet { save() }
    }

    @Published var whisperConfiguration: WhisperCppTranscriptionConfiguration {
        didSet { save() }
    }

    @Published private(set) var lastValidationStatus: TranscriptionConfigurationValidationStatus {
        didSet { save() }
    }

    @Published private(set) var lastValidationMessage: String {
        didSet { save() }
    }

    private let defaults: any TranscriptionSettingsDefaults
    private let key = "Rokurics.TranscriptionSettings.v1"

    init(defaults: any TranscriptionSettingsDefaults = UserDefaults.standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: key),
           let settings = try? Self.decoder.decode(PersistedSettings.self, from: data) {
            selectedProviderKind = settings.selectedProviderKind
            whisperConfiguration = settings.whisperConfiguration
            lastValidationStatus = settings.lastValidationStatus
            lastValidationMessage = settings.lastValidationMessage
        } else {
            selectedProviderKind = .mock
            whisperConfiguration = .default
            lastValidationStatus = .notConfigured
            lastValidationMessage = "Mock Transcription 无需外部配置"
        }
    }

    var selectedProviderDisplayName: String {
        selectedProviderKind.displayName
    }

    var currentLanguage: String {
        selectedProviderKind == .whisperCpp ? whisperConfiguration.normalizedLanguage : "auto"
    }

    func updateValidation(status: TranscriptionConfigurationValidationStatus, message: String) {
        lastValidationStatus = status
        lastValidationMessage = message
    }

    func updateWhisperConfiguration(_ update: (inout WhisperCppTranscriptionConfiguration) -> Void) {
        var configuration = whisperConfiguration
        update(&configuration)
        whisperConfiguration = configuration
    }

    func resetWhisperCppAuthorizations() {
        updateWhisperConfiguration { configuration in
            var draft = WhisperCppSettingsDraft(configuration: configuration)
            draft.resetAuthorizations()
            configuration = draft.configuration
        }
        updateValidation(
            status: .notConfigured,
            message: "已清除旧 sandbox 授权和路径，请重新选择 whisper.cpp、模型、根目录和 ffmpeg。"
        )
    }

    func persist() {
        debugLogBookmarkCounts("persist.requested", configuration: whisperConfiguration)
        save()
    }

    func reloadedWhisperConfiguration() -> WhisperCppTranscriptionConfiguration? {
        guard let data = defaults.data(forKey: key),
              let settings = try? Self.decoder.decode(PersistedSettings.self, from: data) else {
            return nil
        }

        return settings.whisperConfiguration
    }

    private func save() {
        debugLogBookmarkCounts("save.beforeEncode", configuration: whisperConfiguration)

        let settings = PersistedSettings(
            selectedProviderKind: selectedProviderKind,
            whisperConfiguration: whisperConfiguration,
            lastValidationStatus: lastValidationStatus,
            lastValidationMessage: lastValidationMessage
        )

        guard let data = try? Self.encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
        debugLogReloadedBookmarkCounts()
    }

    private struct PersistedSettings: Codable {
        let selectedProviderKind: TranscriptionProviderKind
        let whisperConfiguration: WhisperCppTranscriptionConfiguration
        let lastValidationStatus: TranscriptionConfigurationValidationStatus
        let lastValidationMessage: String
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private func debugLogReloadedBookmarkCounts() {
        #if DEBUG
        guard let configuration = reloadedWhisperConfiguration() else {
            print("[Rokurics][TranscriptionSettingsStore] save.afterReload: decodeFailed")
            return
        }

        debugLogBookmarkCounts("save.afterReload", configuration: configuration)
        #endif
    }

    private func debugLogBookmarkCounts(_ context: String, configuration: WhisperCppTranscriptionConfiguration) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionSettingsStore] \(context): " +
            "executableBookmarkBytes=\(configuration.executableBookmarkData?.count ?? 0), " +
            "executableParentDirectoryBookmarkBytes=\(configuration.executableParentDirectoryBookmarkData?.count ?? 0), " +
            "whisperCppRootDirectoryBookmarkBytes=\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0), " +
            "modelBookmarkBytes=\(configuration.modelBookmarkData?.count ?? 0), " +
            "ffmpegBookmarkBytes=\(configuration.ffmpegExecutableBookmarkData?.count ?? 0), " +
            "ffmpegParentDirectoryBookmarkBytes=\(configuration.ffmpegExecutableParentDirectoryBookmarkData?.count ?? 0)"
        )
        #endif
    }
}
