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
            return RokuricsCopy.text("未配置", "Not set")
        case .valid:
            return RokuricsCopy.text("配置有效", "Valid")
        case .executableNotFound:
            return RokuricsCopy.text("可执行文件不存在", "Executable missing")
        case .executableIsDirectory:
            return RokuricsCopy.text("可执行文件路径是文件夹", "Executable is a folder")
        case .executableNotExecutable:
            return RokuricsCopy.text("缺少执行权限", "Not executable")
        case .executableAccessDenied:
            return RokuricsCopy.text("未授权", "No access")
        case .executableEntitlementMissing:
            return RokuricsCopy.text("缺少执行授权", "Missing entitlement")
        case .bookmarkEntitlementMissing:
            return RokuricsCopy.text("缺少书签授权", "Missing bookmark entitlement")
        case .modelNotFound:
            return RokuricsCopy.text("模型文件不存在", "Model missing")
        case .modelIsDirectory:
            return RokuricsCopy.text("模型路径是文件夹", "Model is a folder")
        case .modelAccessDenied:
            return RokuricsCopy.text("模型未授权", "Model access denied")
        case .whisperCppRootDirectoryNotFound:
            return RokuricsCopy.text("根目录不存在", "Root missing")
        case .whisperCppRootDirectoryIsFile:
            return RokuricsCopy.text("根目录不是文件夹", "Root is not a folder")
        case .whisperCppRootDirectoryAccessDenied:
            return RokuricsCopy.text("根目录未授权", "Root access denied")
        case .whisperCppRootDirectoryInvalid:
            return RokuricsCopy.text("根目录不完整", "Root incomplete")
        case .ffmpegNotFound:
            return RokuricsCopy.text("ffmpeg 不存在", "ffmpeg missing")
        case .ffmpegIsDirectory:
            return RokuricsCopy.text("ffmpeg 路径是文件夹", "ffmpeg is a folder")
        case .ffmpegNotExecutable:
            return RokuricsCopy.text("ffmpeg 缺少执行权限", "ffmpeg not executable")
        case .ffmpegAccessDenied:
            return RokuricsCopy.text("ffmpeg 未授权", "ffmpeg access denied")
        case .ffmpegEntitlementMissing:
            return RokuricsCopy.text("缺少执行授权", "Missing entitlement")
        case .outputDirectoryNotWritable:
            return RokuricsCopy.text("输出目录不可写", "Output not writable")
        case .checkFailed:
            return RokuricsCopy.text("检查失败", "Check failed")
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
            lastValidationMessage = RokuricsCopy.text("Mock Transcription 无需外部配置", "Mock Transcription needs no setup")
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
            message: RokuricsCopy.text(
                "已清除旧 sandbox 授权和路径，请重新选择 whisper.cpp、模型、根目录和 ffmpeg。",
                "Cleared old sandbox access and paths. Rechoose whisper.cpp, model, root, and ffmpeg."
            )
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
