//
//  CanonicalLibraryMetadataRealCanaryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataRealCanaryTests {
    @Test func macRealCanaryConfigurationRemainsDefaultOffAndExplicitTestRootOnly() {
        let disabled = CanonicalLibraryMetadataProductionCanaryConfiguration.disabled
        #expect(disabled.mode == .disabled)
        #expect(!disabled.explicitInternalDebugConfiguration)
        #expect(!disabled.allowProductionRootWrites)

        let explicitTest = CanonicalLibraryMetadataProductionCanaryConfiguration.explicitTestRootN1Execute()
        #expect(explicitTest.mode == .canaryN1Execute)
        #expect(explicitTest.rootMode == .testRoot)
        #expect(explicitTest.explicitInternalDebugConfiguration)
        #expect(!explicitTest.allowProductionRootWrites)
        #expect(explicitTest.canaryMaxObjectsPerSyncRun == 1)
    }
}
