//
//  MacIdentityManager.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import CryptoKit
import Foundation
import Network
import Security

struct MacIdentityStatus {
    let hasSigningIdentity: Bool
    let hasTLSIdentity: Bool
    let publicKeyFingerprint: String
    let certificateFingerprint: String
    let displayFingerprint: String
    let fingerprintType: String
    let identityPath: String
    let tlsBlocker: String?
}

enum MacIdentityManagerError: LocalizedError {
    case keyGenerationFailed(String)
    case keyLoadFailed(OSStatus)
    case certificateCreationFailed
    case identityCreationFailed(OSStatus)
    case localIdentityUnavailable

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let message):
            return "TLS key generation failed: \(message)"
        case .keyLoadFailed(let status):
            return "TLS key load failed: \(status)"
        case .certificateCreationFailed:
            return "TLS certificate creation failed."
        case .identityCreationFailed(let status):
            return "SecIdentity creation failed: \(status)"
        case .localIdentityUnavailable:
            return "Network TLS local identity is unavailable."
        }
    }
}

final class MacIdentityManager {
    private struct StoredIdentity: Codable {
        let privateKeyBase64: String
        let createdAt: Date
    }

    private struct StoredTLSPrivateKey: Codable {
        let privateKeyBase64: String
        let createdAt: Date
    }

    private let fileManager: FileManager
    private let identityURL: URL
    private let tlsPrivateKeyURL: URL
    private let certificateURL: URL
    private(set) var signingPrivateKey: P256.Signing.PrivateKey?
    private(set) var publicKeyFingerprint = "未生成"
    private(set) var certificateFingerprint = "未生成"
    private(set) var tlsPrivateKey: SecKey?
    private(set) var tlsCertificate: SecCertificate?
    private(set) var tlsIdentity: SecIdentity?
    private(set) var lastError: String?

    init(
        fileManager: FileManager = .default,
        securityDirectoryURL: URL? = nil,
        tlsKeyTagNamespace: String? = nil
    ) {
        self.fileManager = fileManager
        let resolvedSecurityDirectoryURL = securityDirectoryURL ?? Self.securityDirectoryURL(fileManager: fileManager)
        identityURL = resolvedSecurityDirectoryURL
            .appendingPathComponent("mac-identity.json", isDirectory: false)
        tlsPrivateKeyURL = resolvedSecurityDirectoryURL
            .appendingPathComponent("tls-private-key.json", isDirectory: false)
        certificateURL = resolvedSecurityDirectoryURL
            .appendingPathComponent("tls-certificate.der", isDirectory: false)
        _ = tlsKeyTagNamespace
    }

    var status: MacIdentityStatus {
        MacIdentityStatus(
            hasSigningIdentity: signingPrivateKey != nil,
            hasTLSIdentity: tlsIdentity != nil,
            publicKeyFingerprint: publicKeyFingerprint,
            certificateFingerprint: certificateFingerprint,
            displayFingerprint: tlsIdentity == nil ? publicKeyFingerprint : certificateFingerprint,
            fingerprintType: tlsIdentity == nil ? "public-key-sha256" : "certificate-sha256",
            identityPath: identityURL.path,
            tlsBlocker: tlsIdentity == nil ? (lastError ?? "TLS identity unavailable.") : nil
        )
    }

    func loadOrCreateIdentity() {
        print("[RokuricsIdentity] identity loading begin")

        do {
            try fileManager.createDirectory(
                at: identityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: identityURL.path) {
                print("[RokuricsIdentity] signing identity exists")
                try loadIdentity()
            } else {
                print("[RokuricsIdentity] signing identity missing")
                try createIdentity()
            }

            try loadOrCreateTLSIdentity()

            print("[RokuricsSecurity] HTTPS identity loaded: signing=\(signingPrivateKey != nil), tls=\(tlsIdentity != nil)")
            print("[RokuricsIdentity] certificate fingerprint: \(certificateFingerprint)")
        } catch {
            lastError = "Mac identity failed: \(error.localizedDescription)"
            print("[RokuricsIdentity] errors: \(lastError ?? "unknown identity error")")
        }
    }

    func tlsOptions() -> NWProtocolTLS.Options? {
        guard let tlsIdentity, let localIdentity = sec_identity_create(tlsIdentity) else {
            print("[RokuricsHTTPS] TLS identity unavailable; secure server start is blocked")
            return nil
        }

        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, localIdentity)
        return options
    }

    private func loadIdentity() throws {
        let data = try Data(contentsOf: identityURL)
        let storedIdentity = try JSONDecoder().decode(StoredIdentity.self, from: data)
        guard let keyData = Data(base64URLEncoded: storedIdentity.privateKeyBase64) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: keyData)
        signingPrivateKey = privateKey
        publicKeyFingerprint = Self.fingerprint(for: privateKey.publicKey)
    }

    private func createIdentity() throws {
        let privateKey = P256.Signing.PrivateKey()
        let storedIdentity = StoredIdentity(
            privateKeyBase64: privateKey.rawRepresentation.base64URLEncodedString(),
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storedIdentity)
        try data.write(to: identityURL, options: .atomic)

        signingPrivateKey = privateKey
        publicKeyFingerprint = Self.fingerprint(for: privateKey.publicKey)
        print("[RokuricsSecurity] created local Mac signing identity at: \(identityURL.path)")
    }

    private func loadOrCreateTLSIdentity() throws {
        let key = try loadOrCreateTLSPrivateKey()
        tlsPrivateKey = key

        if let existingCertificate = try loadTLSCertificateFromDisk(),
           certificate(existingCertificate, matches: key) {
            tlsCertificate = existingCertificate
            tlsIdentity = try makeTLSIdentity(certificate: existingCertificate, privateKey: key)
            print("[RokuricsIdentity] SecIdentity loaded from app-local TLS identity")
            return
        } else if fileManager.fileExists(atPath: certificateURL.path) {
            print("[RokuricsIdentity] stored certificate is not linked to current app TLS key; regenerating certificate")
        }

        let certificate = try makeTLSCertificate(privateKey: key)
        tlsCertificate = certificate

        try writeTLSCertificate(certificate)
        tlsIdentity = try makeTLSIdentity(certificate: certificate, privateKey: key)
        print("[RokuricsIdentity] SecIdentity created from app-local TLS identity")
    }

    private func loadOrCreateTLSPrivateKey() throws -> SecKey {
        if let key = try loadTLSPrivateKey() {
            print("[RokuricsIdentity] TLS key exists in app storage")
            return key
        }

        print("[RokuricsIdentity] TLS key missing in app storage")
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256
        ]

        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw MacIdentityManagerError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        try writeTLSPrivateKey(key)
        print("[RokuricsIdentity] TLS key generated in app storage")
        return key
    }

    private func loadTLSPrivateKey() throws -> SecKey? {
        guard fileManager.fileExists(atPath: tlsPrivateKeyURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: tlsPrivateKeyURL)
        let storedPrivateKey = try JSONDecoder().decode(StoredTLSPrivateKey.self, from: data)
        guard let keyData = Data(base64URLEncoded: storedPrivateKey.privateKeyBase64) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw MacIdentityManagerError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        return key
    }

    private func writeTLSPrivateKey(_ key: SecKey) throws {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw MacIdentityManagerError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "external representation unavailable")
        }

        let storedPrivateKey = StoredTLSPrivateKey(
            privateKeyBase64: keyData.base64URLEncodedString(),
            createdAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storedPrivateKey)
        try fileManager.createDirectory(at: tlsPrivateKeyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: tlsPrivateKeyURL, options: .atomic)
    }

    private func loadTLSCertificateFromDisk() throws -> SecCertificate? {
        if fileManager.fileExists(atPath: certificateURL.path) {
            let certificateData = try Data(contentsOf: certificateURL)
            if let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) {
                certificateFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
                print("[RokuricsIdentity] certificate exists")
                print("[RokuricsIdentity] certificate fingerprint: \(certificateFingerprint)")
                return certificate
            }
        }

        return nil
    }

    private func makeTLSCertificate(privateKey: SecKey) throws -> SecCertificate {
        let localIPAddress = MacLocalNetworkAddressProvider.preferredIPv4Address(logPrefix: "[RokuricsIdentity]")
        let certificateData = try SelfSignedCertificateBuilder.makeCertificateDER(
            privateKey: privateKey,
            commonName: "Rokurics Local Mac",
            localIPAddress: localIPAddress
        )

        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw MacIdentityManagerError.certificateCreationFailed
        }

        certificateFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
        print("[RokuricsIdentity] certificate generated")
        print("[RokuricsIdentity] certificate fingerprint: \(certificateFingerprint)")
        return certificate
    }

    private func writeTLSCertificate(_ certificate: SecCertificate) throws {
        let certificateData = SecCertificateCopyData(certificate) as Data
        try certificateData.write(to: certificateURL, options: .atomic)
        certificateFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
    }

    private func makeTLSIdentity(certificate: SecCertificate, privateKey: SecKey) throws -> SecIdentity {
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw MacIdentityManagerError.localIdentityUnavailable
        }
        return identity
    }

    private func certificate(_ certificate: SecCertificate, matches privateKey: SecKey) -> Bool {
        guard let certificatePublicKey = SecCertificateCopyKey(certificate),
              let privatePublicKey = SecKeyCopyPublicKey(privateKey),
              let certificatePublicKeyFingerprint = publicKeyFingerprint(for: certificatePublicKey),
              let privatePublicKeyFingerprint = publicKeyFingerprint(for: privatePublicKey) else {
            return false
        }

        return MacSecurityUtilities.constantTimeEquals(certificatePublicKeyFingerprint, privatePublicKeyFingerprint)
    }

    private func publicKeyFingerprint(for key: SecKey) -> String? {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            return nil
        }

        return MacSecurityUtilities.sha256Hex(keyData)
    }

    private static func fingerprint(for publicKey: P256.Signing.PublicKey) -> String {
        MacSecurityUtilities.sha256Hex(publicKey.x963Representation)
    }

    private static func securityDirectoryURL(fileManager: FileManager) -> URL {
        MacAppStorageProfile.securityDirectoryURL(fileManager: fileManager)
    }
}
