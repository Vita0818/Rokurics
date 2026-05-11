//
//  MacSecurityUtilities.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import CryptoKit
import Foundation

enum MacSecurityUtilities {
    static func randomBase64URLToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        bytes.indices.forEach { index in
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }

        return Data(bytes).base64URLEncodedString()
    }

    static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }

    static func hmacSHA256Base64URL(message: String, secretBase64URL: String) -> String? {
        guard let secretData = Data(base64URLEncoded: secretBase64URL) else {
            return nil
        }

        let key = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64URLEncodedString()
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else {
            return false
        }

        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }

        return difference == 0
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }

        self.init(base64Encoded: base64)
    }
}

extension String {
    var groupedSecurityFingerprint: String {
        uppercased()
            .chunked(into: 4)
            .joined(separator: " ")
    }

    var shortSecurityFingerprint: String {
        String(prefix(12)).uppercased()
    }

    private func chunked(into size: Int) -> [String] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [String] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let nextIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<nextIndex]))
            currentIndex = nextIndex
        }

        return chunks
    }
}
