//
//  SecureMacConnectionSettings.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Combine

struct SecureMacConnectionSnapshot {
    let macHost: String
    let macPort: Int
    let macFingerprint: String
    let macName: String
    let macModel: String
    let deviceID: String
    let sharedSecretBase64URL: String
    let pairedAt: String

    var isPaired: Bool {
        !macHost.isEmpty
            && macPort > 0
            && !macFingerprint.isEmpty
            && !deviceID.isEmpty
            && !sharedSecretBase64URL.isEmpty
    }
}

enum SecureMacConnectionSettings {
    static let macHostKey = "rokurics.secure.macHost"
    static let macPortKey = "rokurics.secure.macPort"
    static let macPortTextKey = "rokurics.secure.macPortText"
    static let macFingerprintKey = "rokurics.secure.macFingerprint"
    static let macNameKey = "rokurics.secure.macName"
    static let macModelKey = "rokurics.secure.macModel"
    static let legacyMacDisplayNameKey = "rokurics.secure.macDisplayName"
    static let legacyMacDeviceModelKey = "rokurics.secure.macDeviceModel"
    static let deviceIDKey = "rokurics.secure.deviceID"
    static let sharedSecretKey = "rokurics.secure.sharedSecret"
    static let pairedAtKey = "rokurics.secure.pairedAt"
    static let keychainService = "com.Vita0818.Rokurics.secure-mac"
    static let defaultPort = 8787

    static func clearPrototypeSharedSecretFromDefaults(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: sharedSecretKey)
    }
}

struct RokuricsPairingInfo {
    let host: String
    let portText: String
    let pairingCode: String
    let fingerprint: String
}

enum RokuricsPairingInfoParser {
    static func parse(_ text: String) -> RokuricsPairingInfo? {
        var host = ""
        var portText = ""
        var code = ""
        var fingerprint = ""
        var isReadingFingerprint = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                if isReadingFingerprint {
                    fingerprint += SecureUploadUtilities.normalizedCertificateFingerprint(line)
                }
                continue
            }

            let key = parts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "host", "mac", "ip", "address":
                host = value
                isReadingFingerprint = false
            case "port":
                portText = String(value.filter(\.isNumber).prefix(5))
                isReadingFingerprint = false
            case "code", "pairing code", "pairingcode":
                code = String(value.filter(\.isNumber).prefix(6))
                isReadingFingerprint = false
            case "fingerprint", "certificate fingerprint", "cert fingerprint":
                fingerprint += SecureUploadUtilities.normalizedCertificateFingerprint(value)
                fingerprint = String(fingerprint.prefix(64))
                isReadingFingerprint = fingerprint.count < 64
            default:
                if isReadingFingerprint {
                    fingerprint += SecureUploadUtilities.normalizedCertificateFingerprint(line)
                    fingerprint = String(fingerprint.prefix(64))
                    isReadingFingerprint = fingerprint.count < 64
                }
                continue
            }
        }

        fingerprint = String(fingerprint.prefix(64))

        guard !host.isEmpty, !portText.isEmpty, code.count == 6, fingerprint.count == 64 else {
            return nil
        }

        return RokuricsPairingInfo(
            host: host,
            portText: portText,
            pairingCode: code,
            fingerprint: fingerprint
        )
    }
}

private struct SecureMacConnectionStoreState: Equatable {
    var macHost = ""
    var macPortText = "\(SecureMacConnectionSettings.defaultPort)"
    var macFingerprint = ""
    var macName = ""
    var macModel = ""
    var deviceID = ""
    var sharedSecret = ""
    var pairedAt = ""
    var storageError: String?
}

@MainActor
final class SecureMacConnectionStore: ObservableObject {
    var macHost: String {
        get { state.macHost }
        set {
            updateConnectionFields { nextState in
                nextState.macHost = newValue
            }
        }
    }

    var macPortText: String {
        get { state.macPortText }
        set {
            updateConnectionFields { nextState in
                nextState.macPortText = Self.sanitizedPortText(newValue)
            }
        }
    }

    var macFingerprint: String {
        get { state.macFingerprint }
        set {
            updateConnectionFields { nextState in
                nextState.macFingerprint = SecureUploadUtilities.normalizedCertificateFingerprint(newValue)
            }
        }
    }

    var macName: String { state.macName }
    var macModel: String { state.macModel }
    var deviceID: String { state.deviceID }
    var sharedSecret: String { state.sharedSecret }
    var pairedAt: String { state.pairedAt }
    var storageError: String? { state.storageError }

    private let userDefaults: UserDefaults
    private let keychainStore: KeychainStore
    private var state = SecureMacConnectionStoreState()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.keychainStore = KeychainStore()
        refreshFromStorage()
    }

    var macPort: Int {
        Int(state.macPortText) ?? 0
    }

    var normalizedFingerprint: String {
        SecureUploadUtilities.normalizedCertificateFingerprint(state.macFingerprint)
    }

    var snapshot: SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: normalizedHost(state.macHost),
            macPort: macPort,
            macFingerprint: normalizedFingerprint,
            macName: state.macName,
            macModel: state.macModel,
            deviceID: state.deviceID,
            sharedSecretBase64URL: state.sharedSecret,
            pairedAt: state.pairedAt
        )
    }

    var isPaired: Bool {
        snapshot.isPaired
    }

    func refreshFromStorage() {
        let storedHost = userDefaults.string(forKey: SecureMacConnectionSettings.macHostKey) ?? ""
        let storedPortText = loadPortText()
        let storedMacName = userDefaults.string(forKey: SecureMacConnectionSettings.macNameKey)
            ?? userDefaults.string(forKey: SecureMacConnectionSettings.legacyMacDisplayNameKey)
            ?? ""
        let storedMacModel = userDefaults.string(forKey: SecureMacConnectionSettings.macModelKey)
            ?? userDefaults.string(forKey: SecureMacConnectionSettings.legacyMacDeviceModelKey)
            ?? ""
        let storedPairedAt = userDefaults.string(forKey: SecureMacConnectionSettings.pairedAtKey) ?? ""
        let defaultsFingerprint = userDefaults.string(forKey: SecureMacConnectionSettings.macFingerprintKey) ?? ""
        var loadedDeviceID = ""
        var loadedSharedSecret = ""
        var loadedFingerprint = defaultsFingerprint
        var loadedStorageError: String?

        do {
            loadedDeviceID = try keychainStore.load(account: SecureMacConnectionSettings.deviceIDKey) ?? ""
            loadedSharedSecret = try keychainStore.load(account: SecureMacConnectionSettings.sharedSecretKey) ?? ""
            let keychainFingerprint = try keychainStore.load(account: SecureMacConnectionSettings.macFingerprintKey) ?? ""
            loadedFingerprint = keychainFingerprint.isEmpty ? defaultsFingerprint : keychainFingerprint
        } catch {
            loadedStorageError = error.localizedDescription
        }

        applyState(SecureMacConnectionStoreState(
            macHost: normalizedHost(storedHost),
            macPortText: Self.sanitizedPortText(storedPortText),
            macFingerprint: SecureUploadUtilities.normalizedCertificateFingerprint(loadedFingerprint),
            macName: storedMacName,
            macModel: storedMacModel,
            deviceID: loadedDeviceID,
            sharedSecret: loadedSharedSecret,
            pairedAt: storedPairedAt,
            storageError: loadedStorageError
        ))
        SecureMacConnectionSettings.clearPrototypeSharedSecretFromDefaults(userDefaults: userDefaults)
    }

    func savePairing(
        result: SecurePairingResult,
        host: String,
        portText: String,
        fingerprint: String
    ) throws {
        let normalizedFingerprint = SecureUploadUtilities.normalizedCertificateFingerprint(fingerprint)

        do {
            try keychainStore.save(result.deviceID, account: SecureMacConnectionSettings.deviceIDKey)
            try keychainStore.save(result.sharedSecretBase64URL, account: SecureMacConnectionSettings.sharedSecretKey)
            try keychainStore.save(normalizedFingerprint, account: SecureMacConnectionSettings.macFingerprintKey)
        } catch {
            try? keychainStore.delete(account: SecureMacConnectionSettings.deviceIDKey)
            try? keychainStore.delete(account: SecureMacConnectionSettings.sharedSecretKey)
            try? keychainStore.delete(account: SecureMacConnectionSettings.macFingerprintKey)
            var errorState = state
            errorState.storageError = error.localizedDescription
            applyState(errorState)
            throw error
        }

        applyState(SecureMacConnectionStoreState(
            macHost: normalizedHost(host),
            macPortText: Self.sanitizedPortText(portText),
            macFingerprint: normalizedFingerprint,
            macName: result.macName,
            macModel: result.macModel,
            deviceID: result.deviceID,
            sharedSecret: result.sharedSecretBase64URL,
            pairedAt: result.pairedAt,
            storageError: nil
        ))
        persistConnectionFields()
        SecureMacConnectionSettings.clearPrototypeSharedSecretFromDefaults(userDefaults: userDefaults)
    }

    func clearPairing() throws {
        let pairingAccounts = [
            SecureMacConnectionSettings.deviceIDKey,
            SecureMacConnectionSettings.sharedSecretKey,
            SecureMacConnectionSettings.macFingerprintKey
        ]
        var firstError: Error?

        for account in pairingAccounts {
            do {
                try keychainStore.delete(account: account)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        [
            SecureMacConnectionSettings.macHostKey,
            SecureMacConnectionSettings.macPortKey,
            SecureMacConnectionSettings.macPortTextKey,
            SecureMacConnectionSettings.macFingerprintKey,
            SecureMacConnectionSettings.macNameKey,
            SecureMacConnectionSettings.macModelKey,
            SecureMacConnectionSettings.legacyMacDisplayNameKey,
            SecureMacConnectionSettings.legacyMacDeviceModelKey,
            SecureMacConnectionSettings.pairedAtKey
        ].forEach(userDefaults.removeObject)

        applyState(SecureMacConnectionStoreState(storageError: firstError?.localizedDescription))
        SecureMacConnectionSettings.clearPrototypeSharedSecretFromDefaults(userDefaults: userDefaults)

        if let firstError {
            throw firstError
        }
    }

    func applyPairingInfo(_ pairingInfo: RokuricsPairingInfo) {
        updateConnectionFields { nextState in
            nextState.macHost = normalizedHost(pairingInfo.host)
            nextState.macPortText = Self.sanitizedPortText(pairingInfo.portText)
            nextState.macFingerprint = pairingInfo.fingerprint
        }
    }

    static func sanitizedPortText(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(5))
    }

    private func updateConnectionFields(_ update: (inout SecureMacConnectionStoreState) -> Void) {
        var nextState = state
        update(&nextState)
        applyState(nextState)
        persistConnectionFields()
    }

    private func applyState(_ nextState: SecureMacConnectionStoreState) {
        guard nextState != state else {
            return
        }

        objectWillChange.send()
        state = nextState
    }

    private func persistConnectionFields() {
        userDefaults.set(normalizedHost(state.macHost), forKey: SecureMacConnectionSettings.macHostKey)
        userDefaults.set(Self.sanitizedPortText(state.macPortText), forKey: SecureMacConnectionSettings.macPortTextKey)
        if let port = Int(Self.sanitizedPortText(state.macPortText)) {
            userDefaults.set(port, forKey: SecureMacConnectionSettings.macPortKey)
        }
        userDefaults.set(normalizedFingerprint, forKey: SecureMacConnectionSettings.macFingerprintKey)
        userDefaults.set(state.macName, forKey: SecureMacConnectionSettings.macNameKey)
        userDefaults.set(state.macModel, forKey: SecureMacConnectionSettings.macModelKey)
        userDefaults.set(state.pairedAt, forKey: SecureMacConnectionSettings.pairedAtKey)
    }

    private func loadPortText() -> String {
        if let storedText = userDefaults.string(forKey: SecureMacConnectionSettings.macPortTextKey),
           !storedText.isEmpty {
            return Self.sanitizedPortText(storedText)
        }

        if let storedString = userDefaults.object(forKey: SecureMacConnectionSettings.macPortKey) as? String,
           !storedString.isEmpty {
            return Self.sanitizedPortText(storedString)
        }

        if userDefaults.object(forKey: SecureMacConnectionSettings.macPortKey) != nil {
            let storedInt = userDefaults.integer(forKey: SecureMacConnectionSettings.macPortKey)
            if storedInt > 0 {
                return "\(storedInt)"
            }
        }

        return "\(SecureMacConnectionSettings.defaultPort)"
    }

    private func normalizedHost(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .flatMap { $0.split(separator: ":").first }
            .map(String.init) ?? ""
    }
}
