//
//  MacUploadClient.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Foundation

struct MacUploadResult {
    let fileName: String
    let message: String
}

enum MacUploadError: LocalizedError {
    case insecureHTTPDisabled
    case missingHost
    case invalidURL
    case invalidResponse
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .insecureHTTPDisabled:
            return "裸 HTTP 上传已禁用，请使用安全 HTTPS 配对链路。"
        case .missingHost:
            return "请输入 Mac 的局域网 IP。"
        case .invalidURL:
            return "Mac 地址或端口无效。"
        case .invalidResponse:
            return "Mac 返回了无法识别的响应。"
        case .serverRejected(let message):
            return message
        }
    }
}

struct MacUploadClient {
    private static let insecureHTTPDebugOverride = false

    private struct UploadResponse: Decodable {
        let ok: Bool
        let message: String?
        let fileName: String?
        let error: String?
    }

    func uploadTestFile(host rawHost: String, port: Int) async throws -> MacUploadResult {
        guard Self.insecureHTTPDebugOverride else {
            print("[RokuricsSecurity] insecure HTTP upload blocked")
            throw MacUploadError.insecureHTTPDisabled
        }

        let host = normalizedHost(rawHost)
        guard !host.isEmpty else {
            throw MacUploadError.missingHost
        }

        guard port > 0, port <= 65_535 else {
            throw MacUploadError.invalidURL
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/upload-test"

        guard let url = components.url else {
            throw MacUploadError.invalidURL
        }

        let createdAt = Date()
        let payload = UploadTestPayload.makeTestPayload(createdAt: createdAt)
        let payloadData = try JSONEncoder().encode(payload)
        let fileName = Self.fileName(for: createdAt)

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(fileName, forHTTPHeaderField: "X-Rokurics-Filename")
        request.setValue("iPhone", forHTTPHeaderField: "X-Rokurics-Device")
        request.setValue("test", forHTTPHeaderField: "X-Rokurics-Upload-Type")

        print("[RokuricsUpload] target URL: \(url.absoluteString)")
        print("[RokuricsUpload] payload size: \(payloadData.count)")
        print("[RokuricsUpload] request headers: \(request.allHTTPHeaderFields ?? [:])")

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: payloadData)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MacUploadError.invalidResponse
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[RokuricsUpload] response status code: \(httpResponse.statusCode)")
            print("[RokuricsUpload] response body: \(responseBody)")

            let decodedResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
            guard httpResponse.statusCode == 200, decodedResponse.ok else {
                throw MacUploadError.serverRejected(decodedResponse.error ?? "上传失败。")
            }

            return MacUploadResult(
                fileName: decodedResponse.fileName ?? fileName,
                message: decodedResponse.message ?? "received"
            )
        } catch {
            print("[RokuricsUpload] errors: \(error)")
            throw error
        }
    }

    private func normalizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if let components = URLComponents(string: trimmed), let componentHost = components.host {
            return componentHost
        }

        return trimmed
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .split(separator: "/")
            .first
            .flatMap { $0.split(separator: ":").first }
            .map(String.init) ?? ""
    }

    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "rokurics_test_\(formatter.string(from: date)).json"
    }
}
