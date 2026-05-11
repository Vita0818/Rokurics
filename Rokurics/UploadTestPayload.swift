//
//  UploadTestPayload.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Foundation

struct UploadTestPayload: Codable {
    let type: String
    let createdAt: String
    let message: String
    let device: String

    static func makeTestPayload(createdAt: Date = Date()) -> UploadTestPayload {
        UploadTestPayload(
            type: "rokurics-upload-test",
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            message: "Hello from iPhone",
            device: "iPhone"
        )
    }

    static func makeSecureTestPayload(createdAt: Date = Date()) -> UploadTestPayload {
        UploadTestPayload(
            type: "rokurics-secure-upload-test",
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            message: "Hello securely from iPhone",
            device: "iPhone"
        )
    }
}
