//
//  MacUserProfile.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/20.
//

import Combine
import Foundation

struct MacUserProfile: Codable, Equatable {
    static let displayNameKey = "rokurics.mac.profile.displayName"
    static let handleKey = "rokurics.mac.profile.handle"
    static let defaultDisplayName = "用户"
    static let defaultHandle = "rokurics_user"

    var displayName: String
    var handle: String

    init(displayName: String = Self.defaultDisplayName, handle: String = Self.defaultHandle) {
        self.displayName = Self.normalized(displayName, fallback: Self.defaultDisplayName)
        self.handle = Self.normalizedHandle(handle)
    }

    var displayHandle: String {
        Self.displayHandle(handle)
    }

    var initial: String {
        displayName.first.map { String($0).uppercased() } ?? Self.defaultDisplayNamePrefix
    }

    static var defaultDisplayNamePrefix: String {
        defaultDisplayName.first.map { String($0).uppercased() } ?? "用"
    }

    static func normalized(_ value: String, fallback: String = defaultDisplayName) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func normalizedHandle(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return trimmed.isEmpty ? defaultHandle : trimmed
    }

    static func displayHandle(_ value: String) -> String {
        "@\(normalizedHandle(value))"
    }

    static func profileSummaryTexts(displayName: String, handle: String) -> [String] {
        [
            normalized(displayName),
            displayHandle(handle)
        ]
    }
}

@MainActor
final class MacUserProfileStore: ObservableObject {
    @Published private(set) var profile: MacUserProfile

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        profile = MacUserProfile(
            displayName: userDefaults.string(forKey: MacUserProfile.displayNameKey) ?? MacUserProfile.defaultDisplayName,
            handle: userDefaults.string(forKey: MacUserProfile.handleKey) ?? MacUserProfile.defaultHandle
        )
    }

    func update(displayName: String, handle: String) {
        profile = MacUserProfile(displayName: displayName, handle: handle)
        save()
    }

    private func save() {
        userDefaults.set(profile.displayName, forKey: MacUserProfile.displayNameKey)
        userDefaults.set(profile.handle, forKey: MacUserProfile.handleKey)
    }
}
