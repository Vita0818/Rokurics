//
//  SecurityScopedFileAccess.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation
import Security

struct SecurityScopedFileReference: Equatable {
    let path: String
    let bookmarkData: Data?

    var expandedPath: String {
        (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    var hasBookmark: Bool {
        guard let bookmarkData else {
            return false
        }

        return !bookmarkData.isEmpty
    }
}

struct SecurityScopedExecutableReference: Equatable {
    let executablePath: String
    let fileBookmarkData: Data?
    let parentDirectoryPath: String?
    let parentDirectoryBookmarkData: Data?

    var expandedExecutablePath: String {
        (executablePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    var expandedParentDirectoryPath: String {
        ((parentDirectoryPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    var hasFileBookmark: Bool {
        fileBookmarkData?.isEmpty == false
    }

    var hasParentDirectoryBookmark: Bool {
        parentDirectoryBookmarkData?.isEmpty == false
    }

    var fileReference: SecurityScopedFileReference {
        SecurityScopedFileReference(path: expandedExecutablePath, bookmarkData: fileBookmarkData)
    }

    var parentDirectoryReference: SecurityScopedFileReference {
        SecurityScopedFileReference(path: expandedParentDirectoryPath, bookmarkData: parentDirectoryBookmarkData)
    }
}

struct SecurityScopedBookmarkResolution {
    let url: URL
    let isStale: Bool
}

enum SecurityScopedExecutableAuthorizationSource: String, Equatable {
    case bundledHelper
    case fileBookmark
    case parentDirectoryBookmark
}

final class SecurityScopedExecutableAccess {
    let executableURL: URL
    let scopeURL: URL
    let didStartAccessing: Bool
    let authorizationSource: SecurityScopedExecutableAuthorizationSource

    private let scopedAccess: SecurityScopedResourceAccess

    init(
        executableURL: URL,
        scopeURL: URL,
        didStartAccessing: Bool,
        authorizationSource: SecurityScopedExecutableAuthorizationSource,
        scopedAccess: SecurityScopedResourceAccess
    ) {
        self.executableURL = executableURL
        self.scopeURL = scopeURL
        self.didStartAccessing = didStartAccessing
        self.authorizationSource = authorizationSource
        self.scopedAccess = scopedAccess
    }

    func stop() {
        scopedAccess.stop()
    }

    deinit {
        stop()
    }
}

struct SecurityScopedBookmarkCreationFailureDiagnostic: LocalizedError, Equatable {
    let role: String
    let selectedPath: String
    let standardizedPath: String
    let symlinkResolvedPath: String
    let attemptedPath: String
    let bookmarkOptions: String
    let didStartAccessing: Bool
    let nsErrorDomain: String
    let nsErrorCode: Int
    let localizedDescription: String
    let failureReason: String?
    let recoverySuggestion: String?

    var errorDescription: String? {
        userMessage
    }

    var userMessage: String {
        let pieces = [
            "无法创建 sandbox 授权",
            "domain=\(nsErrorDomain)",
            "code=\(nsErrorCode)",
            localizedDescription
        ]
        return Self.limited(pieces.joined(separator: "；"), maxCharacters: 240)
    }

    var debugLogMessage: String {
        var fields = [
            "role=\(role)",
            "selectedPath=\(selectedPath)",
            "standardizedPath=\(standardizedPath)",
            "symlinkResolvedPath=\(symlinkResolvedPath)",
            "attemptedPath=\(attemptedPath)",
            "bookmarkOptions=\(bookmarkOptions)",
            "didStartAccessing=\(didStartAccessing)",
            "nsErrorDomain=\(nsErrorDomain)",
            "nsErrorCode=\(nsErrorCode)",
            "localizedDescription=\(localizedDescription)"
        ]

        if let failureReason, !failureReason.isEmpty {
            fields.append("failureReason=\(failureReason)")
        }

        if let recoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append("recoverySuggestion=\(recoverySuggestion)")
        }

        return "[Rokurics][SecurityScopedFileAccess] bookmarkData creation failed: "
            + fields.joined(separator: ", ")
    }

    init(
        role: String,
        selectedURL: URL,
        attemptedURL: URL,
        bookmarkOptions: URL.BookmarkCreationOptions,
        didStartAccessing: Bool,
        error: Error
    ) {
        let nsError = error as NSError
        self.role = role
        self.selectedPath = selectedURL.path
        self.standardizedPath = selectedURL.standardizedFileURL.path
        self.symlinkResolvedPath = selectedURL.resolvingSymlinksInPath().path
        self.attemptedPath = attemptedURL.path
        self.bookmarkOptions = SecurityScopedFileAccess.bookmarkOptionsDescription(bookmarkOptions)
        self.didStartAccessing = didStartAccessing
        self.nsErrorDomain = nsError.domain
        self.nsErrorCode = nsError.code
        self.localizedDescription = nsError.localizedDescription
        self.failureReason = nsError.localizedFailureReason
        self.recoverySuggestion = nsError.localizedRecoverySuggestion
    }

    private static func limited(_ string: String, maxCharacters: Int) -> String {
        guard string.count > maxCharacters else {
            return string
        }

        return String(string.prefix(maxCharacters)) + "..."
    }
}

enum ExecutableParentDirectoryAuthorization {
    static func isDirectParentDirectory(_ directoryPath: String, ofExecutableAtPath executablePath: String) -> Bool {
        let directoryURL = URL(fileURLWithPath: expanded(directoryPath), isDirectory: true)
        let executableURL = URL(fileURLWithPath: expanded(executablePath), isDirectory: false)
        let expectedDirectoryURL = executableURL.deletingLastPathComponent()

        return equivalent(directoryURL, expectedDirectoryURL)
    }

    static func isAllowedParentDirectoryPath(_ directoryPath: String) -> Bool {
        let path = URL(fileURLWithPath: expanded(directoryPath), isDirectory: true)
            .standardizedFileURL
            .path

        let blocked = [
            "/",
            "/Users",
            "/opt",
            "/opt/homebrew",
            "/usr",
            "/usr/local",
            "/var",
            "/private"
        ]

        return !blocked.contains(path)
    }

    static func equivalent(_ first: URL, _ second: URL) -> Bool {
        let firstStandardized = first.standardizedFileURL.path
        let secondStandardized = second.standardizedFileURL.path
        if firstStandardized == secondStandardized {
            return true
        }

        return first.resolvingSymlinksInPath().standardizedFileURL.path
            == second.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func expanded(_ path: String) -> String {
        (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }
}

struct SecurityScopedFileAccessEnvironment {
    let hasEntitlement: (String) -> Bool
    let resolveBookmark: (Data) throws -> SecurityScopedBookmarkResolution
    let startAccessing: (URL) -> Bool
    let stopAccessing: (URL) -> Void

    static let live = SecurityScopedFileAccessEnvironment(
        hasEntitlement: { name in
            guard let task = SecTaskCreateFromSelf(nil),
                  let value = SecTaskCopyValueForEntitlement(
                    task,
                    name as CFString,
                    nil
                  ) else {
                return false
            }

            return (value as? Bool) == true
        },
        resolveBookmark: { bookmarkData in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return SecurityScopedBookmarkResolution(url: url, isStale: isStale)
        },
        startAccessing: { url in
            url.startAccessingSecurityScopedResource()
        },
        stopAccessing: { url in
            url.stopAccessingSecurityScopedResource()
        }
    )
}

struct ExecutableValidationErrors {
    let pathMissing: TranscriptionError
    let notFound: TranscriptionError
    let isDirectory: TranscriptionError
    let notExecutable: TranscriptionError
    let sandboxAccessDenied: TranscriptionError
    let executableEntitlementMissing: TranscriptionError
    let bookmarkEntitlementMissing: TranscriptionError
}

struct ReadableFileValidationErrors {
    let pathMissing: TranscriptionError
    let notFound: TranscriptionError
    let isDirectory: TranscriptionError
    let sandboxAccessDenied: TranscriptionError
    let bookmarkEntitlementMissing: TranscriptionError
}

struct ReadableDirectoryValidationErrors {
    let pathMissing: TranscriptionError
    let notFound: TranscriptionError
    let isFile: TranscriptionError
    let sandboxAccessDenied: TranscriptionError
    let bookmarkEntitlementMissing: TranscriptionError
}

final class SecurityScopedResourceAccess {
    let url: URL
    let didStartAccessing: Bool

    private let stopAccessing: (URL) -> Void
    private var isStopped = false

    init(url: URL, didStartAccessing: Bool, stopAccessing: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.url = url
        self.didStartAccessing = didStartAccessing
        self.stopAccessing = stopAccessing
    }

    func stop() {
        guard didStartAccessing, !isStopped else {
            return
        }

        stopAccessing(url)
        isStopped = true
    }

    deinit {
        stop()
    }
}

enum SecurityScopedFileAccess {
    static let appScopeBookmarkEntitlementName = "com.apple.security.files.bookmarks.app-scope"
    static let appSandboxEntitlementName = "com.apple.security.app-sandbox"
    static let userSelectedExecutableEntitlementName = "com.apple.security.files.user-selected.executable"
    static let userSelectedReadOnlyEntitlementName = "com.apple.security.files.user-selected.read-only"
    static let userSelectedReadWriteEntitlementName = "com.apple.security.files.user-selected.read-write"

    enum BookmarkMode: Equatable {
        case executable
        case directoryReadOnly
        case modelReadOnly

        var creationOptions: URL.BookmarkCreationOptions {
            creationOptionAttempts[0]
        }

        var creationOptionAttempts: [URL.BookmarkCreationOptions] {
            switch self {
            case .executable:
                return [
                    [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    [.withSecurityScope]
                ]
            case .directoryReadOnly:
                return [[.withSecurityScope, .securityScopeAllowOnlyReadAccess]]
            case .modelReadOnly:
                return [[.withSecurityScope, .securityScopeAllowOnlyReadAccess]]
            }
        }

        var diagnosticName: String {
            switch self {
            case .executable:
                return "executable"
            case .directoryReadOnly:
                return "directoryReadOnly"
            case .modelReadOnly:
                return "modelReadOnly"
            }
        }
    }

    static func bookmarkData(for url: URL, mode: BookmarkMode, role: String? = nil) throws -> Data {
        if isSandboxedAppMissingAppScopeBookmarkEntitlement(environment: .live) {
            throw TranscriptionError.bookmarkEntitlementMissing
        }

        let selectedURL = url
        var lastDiagnostic: SecurityScopedBookmarkCreationFailureDiagnostic?
        for candidateURL in bookmarkCandidateURLs(for: url) {
            for options in mode.creationOptionAttempts {
                do {
                    return try makeBookmarkData(for: candidateURL, options: options)
                } catch {
                    let diagnostic = SecurityScopedBookmarkCreationFailureDiagnostic(
                        role: role ?? mode.diagnosticName,
                        selectedURL: selectedURL,
                        attemptedURL: candidateURL,
                        bookmarkOptions: options,
                        didStartAccessing: false,
                        error: error
                    )
                    debugLogBookmarkCreationFailure(diagnostic)
                    lastDiagnostic = diagnostic
                }

                let didStartAccessing = candidateURL.startAccessingSecurityScopedResource()
                guard didStartAccessing else {
                    continue
                }

                do {
                    defer {
                        candidateURL.stopAccessingSecurityScopedResource()
                    }

                    return try makeBookmarkData(for: candidateURL, options: options)
                } catch {
                    let diagnostic = SecurityScopedBookmarkCreationFailureDiagnostic(
                        role: role ?? mode.diagnosticName,
                        selectedURL: selectedURL,
                        attemptedURL: candidateURL,
                        bookmarkOptions: options,
                        didStartAccessing: true,
                        error: error
                    )
                    debugLogBookmarkCreationFailure(diagnostic)
                    lastDiagnostic = diagnostic
                }
            }
        }

        if let lastDiagnostic {
            throw lastDiagnostic
        }

        throw CocoaError(.fileNoSuchFile)
    }

    static func validateExecutable(
        reference: SecurityScopedFileReference,
        errors: ExecutableValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws {
        try validatePathIsConfigured(reference, missingError: errors.pathMissing)
        debugLogAccessCheck(reference: reference, context: "validateExecutable", environment: environment)

        guard reference.hasBookmark else {
            try validateExecutableFileAttributes(
                url: URL(fileURLWithPath: reference.expandedPath),
                errors: errors,
                fileManager: fileManager
            )
            throw bookmarkMissingError(for: errors.sandboxAccessDenied)
        }

        if isSandboxedAppMissingAppScopeBookmarkEntitlement(environment: environment) {
            throw errors.bookmarkEntitlementMissing
        }

        if !hasUserSelectedExecutableEntitlement(environment: environment) {
            throw errors.executableEntitlementMissing
        }

        let access = try startAccessing(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            environment: environment
        )
        defer { access.stop() }

        try validateExecutableFileAttributes(url: access.url, errors: errors, fileManager: fileManager)
    }

    static func validateExecutable(
        reference: SecurityScopedExecutableReference,
        errors: ExecutableValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws {
        let access = try startAccessingExecutable(
            reference: reference,
            errors: errors,
            fileManager: fileManager,
            environment: environment
        )
        access.stop()
    }

    static func validateReadableFile(
        reference: SecurityScopedFileReference,
        errors: ReadableFileValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws {
        try validatePathIsConfigured(reference, missingError: errors.pathMissing)
        debugLogAccessCheck(reference: reference, context: "validateReadableFile", environment: environment)

        guard reference.hasBookmark else {
            try validateReadableFileAttributes(
                url: URL(fileURLWithPath: reference.expandedPath),
                errors: errors,
                fileManager: fileManager
            )
            throw bookmarkMissingError(for: errors.sandboxAccessDenied)
        }

        if isSandboxedAppMissingAppScopeBookmarkEntitlement(environment: environment) {
            throw errors.bookmarkEntitlementMissing
        }

        let access = try startAccessing(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            environment: environment
        )
        defer { access.stop() }

        try validateReadableFileAttributes(url: access.url, errors: errors, fileManager: fileManager)
    }

    static func validateReadableDirectory(
        reference: SecurityScopedFileReference,
        errors: ReadableDirectoryValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws {
        try validatePathIsConfigured(reference, missingError: errors.pathMissing)
        debugLogAccessCheck(reference: reference, context: "validateReadableDirectory", environment: environment)

        guard reference.hasBookmark else {
            try validateReadableDirectoryAttributes(
                url: URL(fileURLWithPath: reference.expandedPath, isDirectory: true),
                errors: errors,
                fileManager: fileManager
            )
            throw bookmarkMissingError(for: errors.sandboxAccessDenied)
        }

        if isSandboxedAppMissingAppScopeBookmarkEntitlement(environment: environment) {
            throw errors.bookmarkEntitlementMissing
        }

        let access = try startAccessing(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            environment: environment
        )
        defer { access.stop() }

        try validateReadableDirectoryAttributes(url: access.url, errors: errors, fileManager: fileManager)
    }

    static func startAccessingExecutable(
        reference: SecurityScopedFileReference,
        errors: ExecutableValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws -> SecurityScopedResourceAccess {
        try validateExecutable(reference: reference, errors: errors, fileManager: fileManager, environment: environment)
        return try startAccessing(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            environment: environment
        )
    }

    static func startAccessingExecutable(
        reference: SecurityScopedExecutableReference,
        errors: ExecutableValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws -> SecurityScopedExecutableAccess {
        try validatePathIsConfigured(
            SecurityScopedFileReference(path: reference.expandedExecutablePath, bookmarkData: nil),
            missingError: errors.pathMissing
        )
        debugLogExecutableAccessCheck(reference: reference, context: "startAccessingExecutable", environment: environment)

        if reference.hasFileBookmark {
            let access = try startAccessingExecutable(
                reference: reference.fileReference,
                errors: errors,
                fileManager: fileManager,
                environment: environment
            )
            return SecurityScopedExecutableAccess(
                executableURL: access.url,
                scopeURL: access.url,
                didStartAccessing: access.didStartAccessing,
                authorizationSource: .fileBookmark,
                scopedAccess: access
            )
        }

        guard reference.hasParentDirectoryBookmark else {
            try validateExecutableFileAttributes(
                url: URL(fileURLWithPath: reference.expandedExecutablePath),
                errors: errors,
                fileManager: fileManager
            )
            throw bookmarkMissingError(for: errors.sandboxAccessDenied)
        }

        if isSandboxedAppMissingAppScopeBookmarkEntitlement(environment: environment) {
            throw errors.bookmarkEntitlementMissing
        }

        let parentAccess = try startAccessingDirectory(
            reference: reference.parentDirectoryReference,
            accessDeniedError: errors.sandboxAccessDenied,
            fileManager: fileManager,
            environment: environment
        )
        do {
            let executableURL = URL(fileURLWithPath: reference.expandedExecutablePath, isDirectory: false)
                .standardizedFileURL

            guard ExecutableParentDirectoryAuthorization.isAllowedParentDirectoryPath(parentAccess.url.path),
                  ExecutableParentDirectoryAuthorization.isDirectParentDirectory(
                    parentAccess.url.path,
                    ofExecutableAtPath: executableURL.path
                  ) else {
                parentAccess.stop()
                throw errors.sandboxAccessDenied
            }

            try validateExecutableFileAttributes(url: executableURL, errors: errors, fileManager: fileManager)

            return SecurityScopedExecutableAccess(
                executableURL: executableURL,
                scopeURL: parentAccess.url,
                didStartAccessing: parentAccess.didStartAccessing,
                authorizationSource: .parentDirectoryBookmark,
                scopedAccess: parentAccess
            )
        } catch {
            parentAccess.stop()
            throw error
        }
    }

    static func startAccessingReadableFile(
        reference: SecurityScopedFileReference,
        errors: ReadableFileValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws -> SecurityScopedResourceAccess {
        try validateReadableFile(reference: reference, errors: errors, fileManager: fileManager, environment: environment)
        return try startAccessing(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            environment: environment
        )
    }

    static func startAccessingReadableDirectory(
        reference: SecurityScopedFileReference,
        errors: ReadableDirectoryValidationErrors,
        fileManager: FileManager = .default,
        environment: SecurityScopedFileAccessEnvironment = .live
    ) throws -> SecurityScopedResourceAccess {
        try validateReadableDirectory(
            reference: reference,
            errors: errors,
            fileManager: fileManager,
            environment: environment
        )
        return try startAccessingDirectory(
            reference: reference,
            accessDeniedError: errors.sandboxAccessDenied,
            fileManager: fileManager,
            environment: environment
        )
    }

    static func hasUserSelectedExecutableEntitlement() -> Bool {
        hasUserSelectedExecutableEntitlement(environment: .live)
    }

    static func hasAppScopeBookmarkEntitlement() -> Bool {
        hasAppScopeBookmarkEntitlement(environment: .live)
    }

    static func hasAppSandboxEntitlement() -> Bool {
        hasAppSandboxEntitlement(environment: .live)
    }

    private static func startAccessing(
        reference: SecurityScopedFileReference,
        accessDeniedError: TranscriptionError,
        environment: SecurityScopedFileAccessEnvironment
    ) throws -> SecurityScopedResourceAccess {
        let url = try resolvedURL(
            reference: reference,
            accessDeniedError: accessDeniedError,
            environment: environment
        )
        let didStartAccessing = environment.startAccessing(url)
        debugLogStartAccessing(reference: reference, didStartAccessing: didStartAccessing)
        guard didStartAccessing else {
            throw accessDeniedError
        }

        return SecurityScopedResourceAccess(
            url: url,
            didStartAccessing: didStartAccessing,
            stopAccessing: environment.stopAccessing
        )
    }

    private static func startAccessingDirectory(
        reference: SecurityScopedFileReference,
        accessDeniedError: TranscriptionError,
        fileManager: FileManager,
        environment: SecurityScopedFileAccessEnvironment
    ) throws -> SecurityScopedResourceAccess {
        try validatePathIsConfigured(reference, missingError: accessDeniedError)
        let url = try resolvedURL(
            reference: reference,
            accessDeniedError: accessDeniedError,
            environment: environment
        )
        let didStartAccessing = environment.startAccessing(url)
        debugLogStartAccessing(reference: reference, didStartAccessing: didStartAccessing)
        guard didStartAccessing else {
            throw accessDeniedError
        }

        let access = SecurityScopedResourceAccess(
            url: url,
            didStartAccessing: didStartAccessing,
            stopAccessing: environment.stopAccessing
        )

        do {
            try validateReadableDirectoryAttributes(url: url, accessDeniedError: accessDeniedError, fileManager: fileManager)
            return access
        } catch {
            access.stop()
            throw error
        }
    }

    private static func resolvedURL(
        reference: SecurityScopedFileReference,
        accessDeniedError: TranscriptionError,
        environment: SecurityScopedFileAccessEnvironment
    ) throws -> URL {
        guard let bookmarkData = reference.bookmarkData, !bookmarkData.isEmpty else {
            return URL(fileURLWithPath: reference.expandedPath)
        }

        do {
            let resolution = try environment.resolveBookmark(bookmarkData)
            debugLogBookmarkResolution(reference: reference, isStale: resolution.isStale)

            guard !resolution.isStale else {
                throw bookmarkStaleError(for: accessDeniedError)
            }

            return resolution.url
        } catch let error as TranscriptionError {
            throw error
        } catch {
            debugLogBookmarkRestoreFailure(reference: reference, error: error)
            throw bookmarkRestoreFailedError(for: accessDeniedError)
        }
    }

    private static func makeBookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func bookmarkCandidateURLs(for url: URL) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []
        for candidate in [
            url,
            url.standardizedFileURL,
            URL(fileURLWithPath: url.path),
            url.resolvingSymlinksInPath()
        ] {
            let key = candidate.path
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            candidates.append(candidate)
        }

        return candidates
    }

    static func bookmarkOptionsDescription(_ options: URL.BookmarkCreationOptions) -> String {
        var values: [String] = []
        if options.contains(.withSecurityScope) {
            values.append("withSecurityScope")
        }

        if options.contains(.securityScopeAllowOnlyReadAccess) {
            values.append("securityScopeAllowOnlyReadAccess")
        }

        return values.isEmpty ? "none" : values.joined(separator: "+")
    }

    private static func validatePathIsConfigured(
        _ reference: SecurityScopedFileReference,
        missingError: TranscriptionError
    ) throws {
        guard !reference.expandedPath.isEmpty else {
            throw missingError
        }
    }

    private static func validateExecutableFileAttributes(
        url: URL,
        errors: ExecutableValidationErrors,
        fileManager: FileManager
    ) throws {
        try validateReadableFileAttributes(
            url: url,
            errors: ReadableFileValidationErrors(
                pathMissing: errors.pathMissing,
                notFound: errors.notFound,
                isDirectory: errors.isDirectory,
                sandboxAccessDenied: errors.sandboxAccessDenied,
                bookmarkEntitlementMissing: errors.bookmarkEntitlementMissing
            ),
            fileManager: fileManager
        )

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw errors.sandboxAccessDenied
        }

        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o111 != 0 else {
            throw errors.notExecutable
        }
    }

    private static func validateReadableFileAttributes(
        url: URL,
        errors: ReadableFileValidationErrors,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw errors.notFound
        }

        guard !isDirectory.boolValue else {
            throw errors.isDirectory
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw errors.sandboxAccessDenied
        }
    }

    private static func validateReadableDirectoryAttributes(
        url: URL,
        errors: ReadableDirectoryValidationErrors,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw errors.notFound
        }

        guard isDirectory.boolValue else {
            throw errors.isFile
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw errors.sandboxAccessDenied
        }
    }

    private static func validateReadableDirectoryAttributes(
        url: URL,
        accessDeniedError: TranscriptionError,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw accessDeniedError
        }

        guard isDirectory.boolValue else {
            throw accessDeniedError
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw accessDeniedError
        }
    }

    private static func hasUserSelectedExecutableEntitlement(environment: SecurityScopedFileAccessEnvironment) -> Bool {
        environment.hasEntitlement(userSelectedExecutableEntitlementName)
    }

    private static func hasAppScopeBookmarkEntitlement(environment: SecurityScopedFileAccessEnvironment) -> Bool {
        environment.hasEntitlement(appScopeBookmarkEntitlementName)
    }

    private static func hasAppSandboxEntitlement(environment: SecurityScopedFileAccessEnvironment) -> Bool {
        environment.hasEntitlement(appSandboxEntitlementName)
    }

    private static func isSandboxedAppMissingAppScopeBookmarkEntitlement(
        environment: SecurityScopedFileAccessEnvironment
    ) -> Bool {
        hasAppSandboxEntitlement(environment: environment) && !hasAppScopeBookmarkEntitlement(environment: environment)
    }

    private static func bookmarkMissingError(for accessDeniedError: TranscriptionError) -> TranscriptionError {
        switch accessDeniedError {
        case .executableSandboxAccessDenied:
            return .executableBookmarkMissing
        case .modelSandboxAccessDenied:
            return .modelBookmarkMissing
        case .ffmpegSandboxAccessDenied:
            return .ffmpegBookmarkMissing
        case .whisperCppRootDirectorySandboxAccessDenied:
            return .whisperCppRootDirectoryBookmarkMissing
        default:
            return accessDeniedError
        }
    }

    private static func bookmarkRestoreFailedError(for accessDeniedError: TranscriptionError) -> TranscriptionError {
        switch accessDeniedError {
        case .executableSandboxAccessDenied:
            return .executableBookmarkRestoreFailed
        case .modelSandboxAccessDenied:
            return .modelBookmarkRestoreFailed
        case .ffmpegSandboxAccessDenied:
            return .ffmpegBookmarkRestoreFailed
        case .whisperCppRootDirectorySandboxAccessDenied:
            return .whisperCppRootDirectoryBookmarkRestoreFailed
        default:
            return accessDeniedError
        }
    }

    private static func bookmarkStaleError(for accessDeniedError: TranscriptionError) -> TranscriptionError {
        switch accessDeniedError {
        case .executableSandboxAccessDenied:
            return .executableBookmarkStale
        case .modelSandboxAccessDenied:
            return .modelBookmarkStale
        case .ffmpegSandboxAccessDenied:
            return .ffmpegBookmarkStale
        case .whisperCppRootDirectorySandboxAccessDenied:
            return .whisperCppRootDirectoryBookmarkStale
        default:
            return accessDeniedError
        }
    }

    private static func debugLogAccessCheck(
        reference: SecurityScopedFileReference,
        context: String,
        environment: SecurityScopedFileAccessEnvironment
    ) {
        #if DEBUG
        print(
            "[Rokurics][SecurityScopedFileAccess] \(context): " +
            "hasBookmark=\(reference.hasBookmark), " +
            "bookmarkBytes=\(reference.bookmarkData?.count ?? 0), " +
            "appSandboxEntitlement=\(hasAppSandboxEntitlement(environment: environment)), " +
            "appScopeBookmarkEntitlement=\(hasAppScopeBookmarkEntitlement(environment: environment)), " +
            "userSelectedExecutableEntitlement=\(hasUserSelectedExecutableEntitlement(environment: environment))"
        )
        #endif
    }

    private static func debugLogExecutableAccessCheck(
        reference: SecurityScopedExecutableReference,
        context: String,
        environment: SecurityScopedFileAccessEnvironment
    ) {
        #if DEBUG
        print(
            "[Rokurics][SecurityScopedFileAccess] \(context): " +
            "fileBookmark=\(reference.hasFileBookmark), " +
            "fileBookmarkBytes=\(reference.fileBookmarkData?.count ?? 0), " +
            "parentDirectoryBookmark=\(reference.hasParentDirectoryBookmark), " +
            "parentDirectoryBookmarkBytes=\(reference.parentDirectoryBookmarkData?.count ?? 0), " +
            "appSandboxEntitlement=\(hasAppSandboxEntitlement(environment: environment)), " +
            "appScopeBookmarkEntitlement=\(hasAppScopeBookmarkEntitlement(environment: environment)), " +
            "userSelectedExecutableEntitlement=\(hasUserSelectedExecutableEntitlement(environment: environment))"
        )
        #endif
    }

    private static func debugLogBookmarkResolution(reference: SecurityScopedFileReference, isStale: Bool) {
        #if DEBUG
        print(
            "[Rokurics][SecurityScopedFileAccess] resolveBookmark: " +
            "hasBookmark=\(reference.hasBookmark), " +
            "bookmarkBytes=\(reference.bookmarkData?.count ?? 0), " +
            "isStale=\(isStale)"
        )
        #endif
    }

    private static func debugLogBookmarkCreationFailure(_ diagnostic: SecurityScopedBookmarkCreationFailureDiagnostic) {
        #if DEBUG
        print(diagnostic.debugLogMessage)
        #endif
    }

    private static func debugLogBookmarkRestoreFailure(reference: SecurityScopedFileReference, error: Error) {
        #if DEBUG
        print(
            "[Rokurics][SecurityScopedFileAccess] resolveBookmark failed: " +
            "hasBookmark=\(reference.hasBookmark), " +
            "bookmarkBytes=\(reference.bookmarkData?.count ?? 0), " +
            "error=\(error.localizedDescription)"
        )
        #endif
    }

    private static func debugLogStartAccessing(reference: SecurityScopedFileReference, didStartAccessing: Bool) {
        #if DEBUG
        print(
            "[Rokurics][SecurityScopedFileAccess] startAccessing: " +
            "hasBookmark=\(reference.hasBookmark), " +
            "bookmarkBytes=\(reference.bookmarkData?.count ?? 0), " +
            "didStartAccessing=\(didStartAccessing)"
        )
        #endif
    }
}
