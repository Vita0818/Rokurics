//
//  LLMServiceConfig.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

final class LLMServiceConfig: ObservableObject {
    @Published private(set) var provider = "未配置"
    @Published private(set) var endpoint = "http://localhost:1234/v1"

    // Future: configure LM Studio, Ollama, or an OpenAI-compatible local API.
}
