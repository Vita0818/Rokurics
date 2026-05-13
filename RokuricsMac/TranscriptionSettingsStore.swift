//
//  TranscriptionSettingsStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Combine
import Foundation

enum TranscriptionConfigurationValidationStatus: String, Codable, Equatable {
    case notConfigured
    case valid
    case executableNotFound
    case executableIsDirectory
    case executableNotExecutable
    case modelNotFound
    case modelIsDirectory
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
            return "文件不可执行"
        case .modelNotFound:
            return "模型文件不存在"
        case .modelIsDirectory:
            return "模型路径是文件夹"
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

    private let defaults: UserDefaults
    private let key = "Rokurics.TranscriptionSettings.v1"

    init(defaults: UserDefaults = .standard) {
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

    func persist() {
        save()
    }

    private func save() {
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
}
