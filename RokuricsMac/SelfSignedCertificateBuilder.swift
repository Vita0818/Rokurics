//
//  SelfSignedCertificateBuilder.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Security

enum SelfSignedCertificateBuilderError: LocalizedError {
    case publicKeyExportFailed
    case signingFailed
    case invalidIPAddress(String)

    var errorDescription: String? {
        switch self {
        case .publicKeyExportFailed:
            return "Unable to export TLS public key."
        case .signingFailed:
            return "Unable to sign self-signed TLS certificate."
        case .invalidIPAddress(let address):
            return "Invalid IP address for certificate SAN: \(address)"
        }
    }
}

enum SelfSignedCertificateBuilder {
    static func makeCertificateDER(
        privateKey: SecKey,
        commonName: String,
        localIPAddress: String?
    ) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SelfSignedCertificateBuilderError.publicKeyExportFailed
        }

        var copyError: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &copyError) as Data? else {
            throw copyError?.takeRetainedValue() ?? SelfSignedCertificateBuilderError.publicKeyExportFailed
        }

        let now = Date()
        let notBefore = now.addingTimeInterval(-60 * 60)
        let notAfter = now.addingTimeInterval(365 * 24 * 60 * 60)
        let tbsCertificate = try makeTBSCertificate(
            publicKeyData: publicKeyData,
            commonName: commonName,
            notBefore: notBefore,
            notAfter: notAfter,
            localIPAddress: localIPAddress
        )

        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            tbsCertificate as CFData,
            &signingError
        ) as Data? else {
            throw signingError?.takeRetainedValue() ?? SelfSignedCertificateBuilderError.signingFailed
        }

        return DER.sequence([
            tbsCertificate,
            DER.ecdsaWithSHA256AlgorithmIdentifier(),
            DER.bitString(signature)
        ])
    }

    private static func makeTBSCertificate(
        publicKeyData: Data,
        commonName: String,
        notBefore: Date,
        notAfter: Date,
        localIPAddress: String?
    ) throws -> Data {
        var serialNumber = Data((0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        serialNumber[serialNumber.startIndex] &= 0x7f

        let name = DER.name(commonName: commonName)
        let subjectPublicKeyInfo = DER.sequence([
            DER.sequence([
                DER.oid([1, 2, 840, 10045, 2, 1]),
                DER.oid([1, 2, 840, 10045, 3, 1, 7])
            ]),
            DER.bitString(publicKeyData)
        ])

        return try DER.sequence([
            DER.explicit(tag: 0, DER.integer(2)),
            DER.integer(serialNumber),
            DER.ecdsaWithSHA256AlgorithmIdentifier(),
            name,
            DER.sequence([
                DER.utcTime(notBefore),
                DER.utcTime(notAfter)
            ]),
            name,
            subjectPublicKeyInfo,
            DER.explicit(tag: 3, makeExtensions(localIPAddress: localIPAddress))
        ])
    }

    private static func makeExtensions(localIPAddress: String?) throws -> Data {
        var subjectAlternativeNames: [Data] = [
            DER.contextSpecificPrimitive(tag: 2, Data("localhost".utf8)),
            DER.contextSpecificPrimitive(tag: 7, Data([127, 0, 0, 1]))
        ]

        if let localIPAddress, localIPAddress != "未知", let ipData = ipv4Data(localIPAddress) {
            subjectAlternativeNames.append(DER.contextSpecificPrimitive(tag: 7, ipData))
        }

        return DER.sequence([
            DER.extensionValue(oid: [2, 5, 29, 19], critical: true, value: DER.sequence([])),
            DER.extensionValue(oid: [2, 5, 29, 15], critical: true, value: DER.bitString(Data([0xa0]), unusedBits: 5)),
            DER.extensionValue(oid: [2, 5, 29, 37], critical: false, value: DER.sequence([
                DER.oid([1, 3, 6, 1, 5, 5, 7, 3, 1])
            ])),
            DER.extensionValue(oid: [2, 5, 29, 17], critical: false, value: DER.sequence(subjectAlternativeNames))
        ])
    }

    private static func ipv4Data(_ address: String) -> Data? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else {
            return nil
        }

        let bytes = parts.compactMap { UInt8($0) }
        guard bytes.count == 4 else {
            return nil
        }

        return Data(bytes)
    }
}

private enum DER {
    static func sequence(_ elements: [Data]) -> Data {
        tagged(0x30, elements.reduce(Data(), +))
    }

    static func set(_ elements: [Data]) -> Data {
        tagged(0x31, elements.reduce(Data(), +))
    }

    static func explicit(tag: UInt8, _ value: Data) -> Data {
        tagged(0xa0 + tag, value)
    }

    static func contextSpecificPrimitive(tag: UInt8, _ value: Data) -> Data {
        tagged(0x80 + tag, value)
    }

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var remaining = value

        repeat {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        } while remaining > 0

        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }

        return tagged(0x02, Data(bytes))
    }

    static func integer(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        if bytes.isEmpty {
            bytes = [0]
        }

        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }

        return tagged(0x02, Data(bytes))
    }

    static func boolean(_ value: Bool) -> Data {
        tagged(0x01, Data([value ? 0xff : 0x00]))
    }

    static func oid(_ components: [Int]) -> Data {
        guard components.count >= 2 else {
            return tagged(0x06, Data())
        }

        var bytes = [UInt8(components[0] * 40 + components[1])]
        for component in components.dropFirst(2) {
            bytes.append(contentsOf: base128(component))
        }

        return tagged(0x06, Data(bytes))
    }

    static func utf8String(_ value: String) -> Data {
        tagged(0x0c, Data(value.utf8))
    }

    static func bitString(_ value: Data, unusedBits: UInt8 = 0) -> Data {
        var bytes = Data([unusedBits])
        bytes.append(value)
        return tagged(0x03, bytes)
    }

    static func octetString(_ value: Data) -> Data {
        tagged(0x04, value)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    static func name(commonName: String) -> Data {
        sequence([
            set([
                sequence([
                    oid([2, 5, 4, 3]),
                    utf8String(commonName)
                ])
            ])
        ])
    }

    static func extensionValue(oid: [Int], critical: Bool, value: Data) -> Data {
        var elements = [DER.oid(oid)]
        if critical {
            elements.append(boolean(true))
        }
        elements.append(octetString(value))
        return sequence(elements)
    }

    static func ecdsaWithSHA256AlgorithmIdentifier() -> Data {
        sequence([
            oid([1, 2, 840, 10045, 4, 3, 2])
        ])
    }

    private static func tagged(_ tag: UInt8, _ value: Data) -> Data {
        var data = Data([tag])
        data.append(length(value.count))
        data.append(value)
        return data
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 {
            return Data([UInt8(count)])
        }

        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        }

        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func base128(_ value: Int) -> [UInt8] {
        var remaining = value
        var bytes = [UInt8(remaining & 0x7f)]
        remaining >>= 7

        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7f) | 0x80, at: 0)
            remaining >>= 7
        }

        return bytes
    }
}
