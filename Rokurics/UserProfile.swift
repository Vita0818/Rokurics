//
//  UserProfile.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import Combine
import Foundation

struct UserProfile: Codable, Equatable {
    static let displayNameKey = "rokurics.ios.profile.displayName"
    static let handleKey = "rokurics.ios.profile.handle"
    static let avatarKey = "rokurics.ios.profile.avatar"
    static let defaultDisplayName = "用户"
    static let defaultHandle = "rokurics_user"
    static let defaultAvatar = "person.crop.circle.fill"

    var displayName: String
    var handle: String
    var avatar: String

    init(
        displayName: String = Self.defaultDisplayName,
        handle: String = Self.defaultHandle,
        avatar: String = Self.defaultAvatar
    ) {
        self.displayName = Self.normalized(displayName, fallback: Self.defaultDisplayName)
        self.handle = Self.normalizedHandle(handle)
        self.avatar = Self.normalized(avatar, fallback: Self.defaultAvatar)
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
}

@MainActor
final class UserProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        profile = UserProfile(
            displayName: userDefaults.string(forKey: UserProfile.displayNameKey) ?? UserProfile.defaultDisplayName,
            handle: userDefaults.string(forKey: UserProfile.handleKey) ?? UserProfile.defaultHandle,
            avatar: userDefaults.string(forKey: UserProfile.avatarKey) ?? UserProfile.defaultAvatar
        )
    }

    func update(displayName: String, handle: String, avatar: String) {
        profile = UserProfile(displayName: displayName, handle: handle, avatar: avatar)
        save()
    }

    private func save() {
        userDefaults.set(profile.displayName, forKey: UserProfile.displayNameKey)
        userDefaults.set(profile.handle, forKey: UserProfile.handleKey)
        userDefaults.set(profile.avatar, forKey: UserProfile.avatarKey)
    }
}
