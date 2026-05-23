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

    private let fileManager: FileManager
    private let identityURL: URL
    private let certificateURL: URL
    private(set) var signingPrivateKey: P256.Signing.PrivateKey?
    private(set) var publicKeyFingerprint = "未生成"
    private(set) var certificateFingerprint = "未生成"
    private(set) var tlsPrivateKey: SecKey?
    private(set) var tlsCertificate: SecCertificate?
    private(set) var tlsIdentity: SecIdentity?
    private(set) var lastError: String?

    private let tlsKeyTag = MacAppStorageProfile.tlsPrivateKeyTag
    private let tlsPrivateKeyLabel = MacAppStorageProfile.tlsPrivateKeyLabel
    private let tlsCertificateLabel = MacAppStorageProfile.tlsCertificateLabel

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let securityDirectoryURL = Self.securityDirectoryURL(fileManager: fileManager)
        identityURL = securityDirectoryURL
            .appendingPathComponent("mac-identity.json", isDirectory: false)
        certificateURL = securityDirectoryURL
            .appendingPathComponent("tls-certificate.der", isDirectory: false)
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

        let certificate = try loadOrCreateTLSCertificate(privateKey: key)
        tlsCertificate = certificate

        try addCertificateToKeychain(certificate)

        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        guard status == errSecSuccess, let identity else {
            throw MacIdentityManagerError.identityCreationFailed(status)
        }

        tlsIdentity = identity
        print("[RokuricsIdentity] SecIdentity created")
    }

    private func loadOrCreateTLSPrivateKey() throws -> SecKey {
        if let key = try loadTLSPrivateKey() {
            print("[RokuricsIdentity] TLS key exists")
            return key
        }

        print("[RokuricsIdentity] TLS key missing")
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tlsKeyTag,
                kSecAttrLabel as String: tlsPrivateKeyLabel
            ]
        ]

        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw MacIdentityManagerError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        print("[RokuricsIdentity] key generated")
        return key
    }

    private func loadTLSPrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tlsKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw MacIdentityManagerError.keyLoadFailed(status)
        }

        return (item as! SecKey)
    }

    private func loadOrCreateTLSCertificate(privateKey: SecKey) throws -> SecCertificate {
        if fileManager.fileExists(atPath: certificateURL.path) {
            let certificateData = try Data(contentsOf: certificateURL)
            if let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) {
                certificateFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
                print("[RokuricsIdentity] certificate exists")
                print("[RokuricsIdentity] certificate fingerprint: \(certificateFingerprint)")
                return certificate
            }
        }

        let localIPAddress = MacLocalNetworkAddressProvider.preferredIPv4Address(logPrefix: "[RokuricsIdentity]")
        let certificateData = try SelfSignedCertificateBuilder.makeCertificateDER(
            privateKey: privateKey,
            commonName: "Rokurics Local Mac",
            localIPAddress: localIPAddress
        )

        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw MacIdentityManagerError.certificateCreationFailed
        }

        try certificateData.write(to: certificateURL, options: .atomic)
        certificateFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
        print("[RokuricsIdentity] certificate generated")
        print("[RokuricsIdentity] certificate fingerprint: \(certificateFingerprint)")
        return certificate
    }

    private func addCertificateToKeychain(_ certificate: SecCertificate) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: tlsCertificateLabel
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: tlsCertificateLabel
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw MacIdentityManagerError.identityCreationFailed(status)
        }
    }

    private static func fingerprint(for publicKey: P256.Signing.PublicKey) -> String {
        MacSecurityUtilities.sha256Hex(publicKey.x963Representation)
    }

    private static func securityDirectoryURL(fileManager: FileManager) -> URL {
        MacAppStorageProfile.securityDirectoryURL(fileManager: fileManager)
    }
}
