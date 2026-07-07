//
//  CanonicalProductionExecutionResultTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalProductionExecutionResultTests {
    @Test func disabledAndDryRunModesProduceNoProductionSideEffects() async {
        let disabled = await CanonicalKernelFacade().executeProduction(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )
        let dryRun = await CanonicalKernelFacade(configuration: CanonicalKernelConfiguration(mode: .dryRun)).executeProduction(
            CanonicalKernelFacadeTestSupport.productionInput(),
            token: CanonicalKernelFacadeTestSupport.token()
        )

        #expect(disabled.payload?.trace.sideEffects.isEmpty == true)
        #expect(dryRun.payload?.trace.sideEffects.isEmpty == true)
    }

    @Test func sideEffectTraceRedactsContentPathsAndSecrets() {
        let effect = CanonicalProductionSideEffect(
            kind: .fileWrite,
            domain: .fileRuntime,
            objectID: "recording-01",
            byteSize: 64,
            hashPrefix: String(repeating: "a", count: 64),
            summary: "/Users/example/secret/full-note.md api-key"
        )

        #expect(effect.hashPrefix?.count == 12)
        #expect(effect.redactedSummary.contains("/Users/") == false)
        #expect(effect.redactedSummary.contains("secret/full-note") == false)
    }

    @Test func canonicalRouteListAndUploadRoutesRemainUnchanged() {
        #expect(CanonicalTransportRoute.allCases.map(\.rawValue) == [
            "manifestExchange",
            "applyPlan",
            "applyMetadata",
            "fileRead",
            "uploadStart",
            "uploadStatus",
            "uploadChunk",
            "uploadFinalize"
        ])
        #expect(CanonicalTransportRoute.allCases.contains { $0.rawValue.lowercased().contains("audiodownload") } == false)
    }

    @Test func productionSideEffectKindsDoNotCreateGeneratedArtifactUploadJob() {
        let rawValues = CanonicalProductionSideEffectKind.allCases.map(\.rawValue)

        #expect(rawValues.contains("generatedArtifactUpload") == false)
        #expect(rawValues.contains("audioDownload") == false)
    }

    @Test func appSourcesKeepProductionExecuteOutOfRuntimeShadowSeams() throws {
        let root = try projectRoot()
        let appDirectories = ["Rokurics", "RokuricsMac"].map { root.appendingPathComponent($0) }
        let swiftFiles = try appDirectories.flatMap { directory in
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
        }
        let allowedKernelFacadeFiles: Set<String> = [
            "CanonicalIPhoneMigrationFacade.swift",
            "CanonicalMacMigrationFacade.swift"
        ]
        let runtimeShadowSeamFiles: Set<String> = [
            "StudyLibrarySyncCoordinator.swift",
            "SecureLocalHTTPSServer.swift"
        ]

        for file in swiftFiles {
            let text = try String(contentsOf: file)
            if text.contains("CanonicalKernelFacade") {
                #expect(allowedKernelFacadeFiles.contains(file.lastPathComponent))
            }
            if runtimeShadowSeamFiles.contains(file.lastPathComponent) {
                #expect(text.contains("executeProduction(") == false)
                #expect(text.contains(".productionExecute") == false)
            }
        }
    }

    private func projectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Rokurics.xcodeproj").path) {
                return url
            }
        }
        throw CanonicalKernelError.missingInput("projectRoot")
    }
}
