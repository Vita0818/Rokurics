//
//  WhisperCppFileVisibilityDiagnostics.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/16.
//

import Darwin
import Foundation

struct WhisperCppFileVisibilityDiagnosticResult: Equatable {
    let rootDirectoryAccessStarted: Bool
    let executableAccessStarted: Bool
    let modelAccessStarted: Bool
    let rootDirectoryAccessError: String?
    let executableAccessError: String?
    let modelAccessError: String?
    let pathResults: [WhisperCppFileVisibilityPathResult]

    func pathResult(label: String) -> WhisperCppFileVisibilityPathResult? {
        pathResults.first { $0.label == label }
    }

    var keyConclusion: String {
        let executable = pathResult(label: "build/bin/whisper-cli")
            ?? pathResult(label: "configured executable")
        let dylibDirectoryLabels = [
            "build/src",
            "build/ggml/src",
            "build/ggml/src/ggml-blas",
            "build/ggml/src/ggml-metal"
        ]
        let dylibDirectoriesVisible = dylibDirectoryLabels
            .compactMap { pathResult(label: $0) }
            .allSatisfy { $0.fileExists && $0.isDirectory && $0.isReadable }
        let dylibFilesVisible = dylibDirectoryLabels
            .compactMap { pathResult(label: $0) }
            .contains { !$0.dylibRelatedEntries.isEmpty }

        return [
            "文件可见性：whisper-cli exists=\(executable?.fileExists ?? false)",
            "executable=\(executable?.isExecutable ?? false)",
            "xok=\(executable?.posixExecuteAccessResult ?? "unavailable")",
            "dylibDirsVisible=\(dylibDirectoriesVisible)",
            "dylibFilesVisible=\(dylibFilesVisible)"
        ].joined(separator: " ")
    }

    var userSummary: String {
        var lines: [String] = [
            "文件可见性诊断：rootAccessStarted=\(rootDirectoryAccessStarted) executableAccessStarted=\(executableAccessStarted) modelAccessStarted=\(modelAccessStarted)"
        ]

        if let rootDirectoryAccessError {
            lines.append("rootAccessError=\(rootDirectoryAccessError)")
        }
        if let executableAccessError {
            lines.append("executableAccessError=\(executableAccessError)")
        }
        if let modelAccessError {
            lines.append("modelAccessError=\(modelAccessError)")
        }

        for label in [
            "root",
            "build",
            "build/bin",
            "build/bin/whisper-cli",
            "build/src",
            "build/ggml/src",
            "build/ggml/src/ggml-blas",
            "build/ggml/src/ggml-metal",
            "models",
            "models/ggml-small.bin"
        ] {
            guard let result = pathResult(label: label) else {
                continue
            }

            lines.append(result.summaryLine)
        }

        return lines.joined(separator: "\n")
    }

    var debugLogMessage: String {
        var lines: [String] = [
            "[Rokurics][WhisperCppFileVisibilityDiagnostics] " +
            "rootDirectoryAccessStarted=\(rootDirectoryAccessStarted); " +
            "executableAccessStarted=\(executableAccessStarted); " +
            "modelAccessStarted=\(modelAccessStarted)"
        ]

        if let rootDirectoryAccessError {
            lines.append("rootDirectoryAccessError=\(rootDirectoryAccessError)")
        }
        if let executableAccessError {
            lines.append("executableAccessError=\(executableAccessError)")
        }
        if let modelAccessError {
            lines.append("modelAccessError=\(modelAccessError)")
        }

        lines.append(contentsOf: pathResults.map(\.debugLogLine))
        return lines.joined(separator: "\n")
    }
}

struct WhisperCppFileVisibilityPathResult: Equatable {
    let label: String
    let path: String
    let standardizedPath: String
    let resolvingSymlinksPath: String
    let lastPathComponent: String
    let fileExists: Bool
    let isDirectory: Bool
    let isReadable: Bool
    let isExecutable: Bool
    let checkResourceIsReachable: Bool
    let checkResourceIsReachableError: String
    let posixReadAccessResult: String
    let posixReadAccessErrno: String
    let posixReadAccessErrnoDescription: String
    let posixExecuteAccessResult: String
    let posixExecuteAccessErrno: String
    let posixExecuteAccessErrnoDescription: String
    let posixStatResult: String
    let posixStatErrno: String
    let posixStatErrnoDescription: String
    let posixStatMode: String
    let posixStatUID: String
    let posixStatGID: String
    let posixStatSize: String
    let directoryEntries: [String]
    let directoryEntryCount: Int?
    let directoryEntriesTruncated: Bool
    let directoryListingError: String?
    let dylibRelatedEntries: [String]

    var summaryLine: String {
        if isDirectory {
            return [
                "\(label):",
                "exists=\(fileExists)",
                "readable=\(isReadable)",
                "isDir=\(isDirectory)",
                "entries=\(directoryEntriesSummary)",
                dylibRelatedEntries.isEmpty ? nil : "dylib=\(dylibEntriesSummary)"
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }

        return [
            "\(label):",
            "exists=\(fileExists)",
            "reachable=\(checkResourceIsReachable)",
            "readable=\(isReadable)",
            "executable=\(isExecutable)",
            "rok=\(posixReadAccessResult)",
            "xok=\(posixExecuteAccessResult)",
            "statMode=\(posixStatMode)",
            "size=\(posixStatSize)"
        ].joined(separator: " ")
    }

    var debugLogLine: String {
        [
            "label=\(label)",
            "path=\(path)",
            "standardizedPath=\(standardizedPath)",
            "resolvingSymlinksPath=\(resolvingSymlinksPath)",
            "lastPathComponent=\(lastPathComponent)",
            "fileExists=\(fileExists)",
            "isDirectory=\(isDirectory)",
            "isReadable=\(isReadable)",
            "isExecutable=\(isExecutable)",
            "checkResourceIsReachable=\(checkResourceIsReachable)",
            "checkResourceIsReachableError=\(checkResourceIsReachableError)",
            "posixAccessROKResult=\(posixReadAccessResult)",
            "posixAccessROKErrno=\(posixReadAccessErrno)",
            "posixAccessROKErrnoDescription=\(posixReadAccessErrnoDescription)",
            "posixAccessXOKResult=\(posixExecuteAccessResult)",
            "posixAccessXOKErrno=\(posixExecuteAccessErrno)",
            "posixAccessXOKErrnoDescription=\(posixExecuteAccessErrnoDescription)",
            "posixStatResult=\(posixStatResult)",
            "posixStatErrno=\(posixStatErrno)",
            "posixStatErrnoDescription=\(posixStatErrnoDescription)",
            "posixStatMode=\(posixStatMode)",
            "posixStatUID=\(posixStatUID)",
            "posixStatGID=\(posixStatGID)",
            "posixStatSize=\(posixStatSize)",
            "directoryEntryCount=\(directoryEntryCount.map { "\($0)" } ?? "nil")",
            "directoryEntriesTruncated=\(directoryEntriesTruncated)",
            "directoryEntries=\(directoryEntriesSummary)",
            "directoryListingError=\(directoryListingError ?? "none")",
            "dylibRelatedEntries=\(dylibEntriesSummary)"
        ].joined(separator: "; ")
    }

    private var directoryEntriesSummary: String {
        if let directoryListingError {
            return "error(\(directoryListingError))"
        }

        guard !directoryEntries.isEmpty else {
            return fileExists && isDirectory ? "empty" : "notDirectory"
        }

        let suffix = directoryEntriesTruncated
            ? ", ... truncated(total=\(directoryEntryCount ?? directoryEntries.count))"
            : ""
        return directoryEntries.joined(separator: ", ") + suffix
    }

    private var dylibEntriesSummary: String {
        guard !dylibRelatedEntries.isEmpty else {
            return "none"
        }

        return dylibRelatedEntries.joined(separator: ", ")
    }
}

struct WhisperCppFileVisibilityDiagnostics {
    var configuration: WhisperCppTranscriptionConfiguration
    var fileManager: FileManager = .default
    var securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live
    var maxDirectoryEntries = 30

    func run() -> WhisperCppFileVisibilityDiagnosticResult {
        let rootAccessOutcome = startRootAccess()
        let executableAccessOutcome = startExecutableAccess()
        let modelAccessOutcome = startModelAccess()

        defer { rootAccessOutcome.access?.stop() }
        defer { executableAccessOutcome.access?.stop() }
        defer { modelAccessOutcome.access?.stop() }

        let rootURL = rootAccessOutcome.access?.url.standardizedFileURL
            ?? configuredURL(configuration.normalizedWhisperCppRootDirectoryPath, isDirectory: true)
        let pathResults = diagnosticTargets(rootURL: rootURL)
            .map { target in probe(target) }

        return WhisperCppFileVisibilityDiagnosticResult(
            rootDirectoryAccessStarted: rootAccessOutcome.access?.didStartAccessing ?? false,
            executableAccessStarted: executableAccessOutcome.access?.didStartAccessing ?? false,
            modelAccessStarted: modelAccessOutcome.access?.didStartAccessing ?? false,
            rootDirectoryAccessError: rootAccessOutcome.error.map(Self.errorDescription),
            executableAccessError: executableAccessOutcome.error.map(Self.errorDescription),
            modelAccessError: modelAccessOutcome.error.map(Self.errorDescription),
            pathResults: pathResults
        )
    }

    private func diagnosticTargets(rootURL: URL?) -> [(label: String, url: URL)] {
        var targets: [(label: String, url: URL)] = []

        if let rootURL {
            targets.append(("root", rootURL))
            targets.append(("build", rootURL.appendingPathComponent("build", isDirectory: true)))
            targets.append(("build/bin", rootURL.appendingPathComponent("build/bin", isDirectory: true)))
            targets.append((
                "build/bin/whisper-cli",
                rootURL.appendingPathComponent("build/bin/whisper-cli", isDirectory: false)
            ))
            targets.append(("build/src", rootURL.appendingPathComponent("build/src", isDirectory: true)))
            targets.append(("build/ggml/src", rootURL.appendingPathComponent("build/ggml/src", isDirectory: true)))
            targets.append((
                "build/ggml/src/ggml-blas",
                rootURL.appendingPathComponent("build/ggml/src/ggml-blas", isDirectory: true)
            ))
            targets.append((
                "build/ggml/src/ggml-metal",
                rootURL.appendingPathComponent("build/ggml/src/ggml-metal", isDirectory: true)
            ))
            targets.append(("models", rootURL.appendingPathComponent("models", isDirectory: true)))
            targets.append((
                "models/ggml-small.bin",
                rootURL.appendingPathComponent("models/ggml-small.bin", isDirectory: false)
            ))
        }

        if let executableURL = configuredURL(configuration.normalizedExecutablePath, isDirectory: false),
           !targets.contains(where: { equivalent($0.url, executableURL) }) {
            targets.append(("configured executable", executableURL))
        }

        if let modelURL = configuredURL(configuration.normalizedModelPath, isDirectory: false),
           !targets.contains(where: { equivalent($0.url, modelURL) }) {
            targets.append(("configured model", modelURL))
        }

        return targets
    }

    private func probe(_ target: (label: String, url: URL)) -> WhisperCppFileVisibilityPathResult {
        let url = target.url.standardizedFileURL
        var isDirectoryValue: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectoryValue)
        let isDirectory = exists && isDirectoryValue.boolValue
        let reachability = Self.resourceReachabilityDescription(url)
        let readAccess = Self.posixAccessDescription(path: url.path, mode: R_OK)
        let executeAccess = Self.posixAccessDescription(path: url.path, mode: X_OK)
        let statDescription = Self.posixStatDescription(path: url.path)
        let directoryListing = isDirectory ? directoryEntries(at: url) : nil

        return WhisperCppFileVisibilityPathResult(
            label: target.label,
            path: url.path,
            standardizedPath: url.standardizedFileURL.path,
            resolvingSymlinksPath: url.resolvingSymlinksInPath().path,
            lastPathComponent: url.lastPathComponent,
            fileExists: exists,
            isDirectory: isDirectory,
            isReadable: fileManager.isReadableFile(atPath: url.path),
            isExecutable: fileManager.isExecutableFile(atPath: url.path),
            checkResourceIsReachable: reachability.reachable,
            checkResourceIsReachableError: reachability.errorDescription,
            posixReadAccessResult: readAccess.result,
            posixReadAccessErrno: readAccess.errno,
            posixReadAccessErrnoDescription: readAccess.errnoDescription,
            posixExecuteAccessResult: executeAccess.result,
            posixExecuteAccessErrno: executeAccess.errno,
            posixExecuteAccessErrnoDescription: executeAccess.errnoDescription,
            posixStatResult: statDescription.result,
            posixStatErrno: statDescription.errno,
            posixStatErrnoDescription: statDescription.errnoDescription,
            posixStatMode: statDescription.mode,
            posixStatUID: statDescription.uid,
            posixStatGID: statDescription.gid,
            posixStatSize: statDescription.size,
            directoryEntries: directoryListing?.entries ?? [],
            directoryEntryCount: directoryListing?.totalCount,
            directoryEntriesTruncated: directoryListing?.truncated ?? false,
            directoryListingError: directoryListing?.errorDescription,
            dylibRelatedEntries: directoryListing?.dylibRelatedEntries ?? []
        )
    }

    private func directoryEntries(at url: URL) -> (
        entries: [String],
        totalCount: Int,
        truncated: Bool,
        errorDescription: String?,
        dylibRelatedEntries: [String]
    ) {
        do {
            let entries = try fileManager.contentsOfDirectory(atPath: url.path)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let visibleEntries = Array(entries.prefix(maxDirectoryEntries))
            let dylibEntries = Array(entries.filter(Self.isDylibRelatedFileName).prefix(maxDirectoryEntries))
            return (
                visibleEntries,
                entries.count,
                entries.count > maxDirectoryEntries,
                nil,
                dylibEntries
            )
        } catch {
            return (
                [],
                0,
                false,
                Self.errorDescription(error),
                []
            )
        }
    }

    private func startRootAccess() -> (access: SecurityScopedResourceAccess?, error: Error?) {
        do {
            let access = try SecurityScopedFileAccess.startAccessingReadableDirectory(
                reference: configuration.whisperCppRootDirectoryReference,
                errors: Self.rootDirectoryErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            return (access, nil)
        } catch {
            return (nil, error)
        }
    }

    private func startExecutableAccess() -> (access: SecurityScopedExecutableAccess?, error: Error?) {
        do {
            let access = try SecurityScopedFileAccess.startAccessingExecutable(
                reference: configuration.executableReference,
                errors: Self.executableErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            return (access, nil)
        } catch {
            return (nil, error)
        }
    }

    private func startModelAccess() -> (access: SecurityScopedResourceAccess?, error: Error?) {
        do {
            let access = try SecurityScopedFileAccess.startAccessingReadableFile(
                reference: configuration.modelFileReference,
                errors: Self.modelFileErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            return (access, nil)
        } catch {
            return (nil, error)
        }
    }

    private func configuredURL(_ path: String, isDirectory: Bool) -> URL? {
        let normalized = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: normalized, isDirectory: isDirectory).standardizedFileURL
    }

    private func equivalent(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private nonisolated static func resourceReachabilityDescription(_ url: URL) -> (reachable: Bool, errorDescription: String) {
        do {
            return (try url.checkResourceIsReachable(), "none")
        } catch {
            return (false, errorDescription(error))
        }
    }

    private nonisolated static func posixAccessDescription(path: String, mode: Int32) -> (
        result: String,
        errno: String,
        errnoDescription: String
    ) {
        Darwin.errno = 0
        let result = path.withCString { pointer in
            Darwin.access(pointer, mode)
        }
        let errorNumber = result == 0 ? 0 : Darwin.errno
        return (
            "\(result)",
            "\(errorNumber)",
            errorNumber == 0 ? "none" : String(cString: strerror(errorNumber))
        )
    }

    private nonisolated static func posixStatDescription(path: String) -> (
        result: String,
        errno: String,
        errnoDescription: String,
        mode: String,
        uid: String,
        gid: String,
        size: String
    ) {
        var info = stat()
        Darwin.errno = 0
        let result = path.withCString { pointer in
            Darwin.fstatat(AT_FDCWD, pointer, &info, 0)
        }
        let errorNumber = result == 0 ? 0 : Darwin.errno
        return (
            "\(result)",
            "\(errorNumber)",
            errorNumber == 0 ? "none" : String(cString: strerror(errorNumber)),
            result == 0 ? String(format: "%#o", info.st_mode) : "unavailable",
            result == 0 ? "\(info.st_uid)" : "unavailable",
            result == 0 ? "\(info.st_gid)" : "unavailable",
            result == 0 ? "\(info.st_size)" : "unavailable"
        )
    }

    private nonisolated static func isDylibRelatedFileName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasSuffix(".dylib")
            || lowercasedName.contains("whisper")
            || lowercasedName.contains("ggml")
            || lowercasedName.contains("metal")
            || lowercasedName.contains("blas")
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
    }

    private static let executableErrors = ExecutableValidationErrors(
        pathMissing: .executablePathMissing,
        notFound: .executableNotFound,
        isDirectory: .executableIsDirectory,
        notExecutable: .executableNotExecutable,
        sandboxAccessDenied: .executableSandboxAccessDenied,
        executableEntitlementMissing: .executableEntitlementMissing,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let modelFileErrors = ReadableFileValidationErrors(
        pathMissing: .modelPathMissing,
        notFound: .modelNotFound,
        isDirectory: .modelIsDirectory,
        sandboxAccessDenied: .modelSandboxAccessDenied,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let rootDirectoryErrors = ReadableDirectoryValidationErrors(
        pathMissing: .whisperCppRootDirectoryPathMissing,
        notFound: .whisperCppRootDirectoryNotFound,
        isFile: .whisperCppRootDirectoryIsFile,
        sandboxAccessDenied: .whisperCppRootDirectorySandboxAccessDenied,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )
}
