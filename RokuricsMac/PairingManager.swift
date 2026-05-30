//
//  PairingManager.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

struct PairingChallenge {
    let code: String
    let expiresAt: Date
}

struct PairingResult {
    let device: PairedDevice
    let sharedSecretBase64URL: String
}

enum PairingState: Equatable {
    case idle
    case pairing(code: String, expiresAt: Date)
    case paired(deviceName: String)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "未配对"
        case .pairing:
            return "配对中"
        case .paired:
            return "已配对"
        case .failed:
            return "配对失败"
        }
    }
}

@MainActor
final class PairingManager: ObservableObject {
    @Published private(set) var state: PairingState = .idle
    @Published private(set) var activeChallenge: PairingChallenge?

    private let pairedDeviceStore: PairedDeviceStore
    private let validityDuration: TimeInterval = 5 * 60

    init(pairedDeviceStore: PairedDeviceStore) {
        self.pairedDeviceStore = pairedDeviceStore
    }

    func beginPairing(now: Date = Date()) {
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let expiresAt = now.addingTimeInterval(validityDuration)
        let challenge = PairingChallenge(code: code, expiresAt: expiresAt)

        activeChallenge = challenge
        state = .pairing(code: code, expiresAt: expiresAt)
        print("[RokuricsPairing] pairing code generated: codeIssued=true, expiresAt=\(expiresAt)")
    }

    func invalidatePairing(reason: String = "invalidated") {
        activeChallenge = nil
        state = .idle
        print("[RokuricsPairing] pairing code invalidated: \(reason)")
    }

    @discardableResult
    func unpairDevice(id deviceID: String) -> Bool {
        let removed = pairedDeviceStore.removeDevice(id: deviceID)
        if pairedDeviceStore.deviceCount == 0 {
            state = .idle
        }
        return removed
    }

    func unpairAll(reason: String = "user_disconnect") {
        pairedDeviceStore.clearAll()
        activeChallenge = nil
        state = .idle
        print("[RokuricsPairing] all paired devices cleared: \(reason)")
    }

    func completePairing(deviceName: String, deviceType: String, code: String, now: Date = Date()) -> PairingResult? {
        print("[RokuricsPairing] pairing attempt received: deviceType=\(deviceType), name=\(deviceName)")

        guard let activeChallenge else {
            state = .failed("no_active_code")
            print("[RokuricsPairing] pairing failure: no_active_code")
            return nil
        }

        guard now <= activeChallenge.expiresAt else {
            self.activeChallenge = nil
            state = .failed("expired_code")
            print("[RokuricsPairing] pairing failure: expired_code")
            return nil
        }

        guard code == activeChallenge.code else {
            state = .failed("bad_code")
            print("[RokuricsPairing] pairing failure: bad_code")
            return nil
        }

        let deviceID = "\(deviceType.lowercased())-\(UUID().uuidString.lowercased())"
        let sharedSecret = MacSecurityUtilities.randomBase64URLToken()
        let device = PairedDevice(
            id: deviceID,
            deviceName: deviceName,
            sharedSecretBase64URL: sharedSecret,
            pairedAt: now,
            lastSeenAt: now
        )

        pairedDeviceStore.upsert(device)
        self.activeChallenge = nil
        state = .paired(deviceName: deviceName)
        print("[RokuricsPairing] pairing success: deviceIDPrefix=\(device.idPrefix)")
        return PairingResult(device: device, sharedSecretBase64URL: sharedSecret)
    }

    func refresh(now: Date = Date()) {
        guard let activeChallenge, now > activeChallenge.expiresAt else {
            return
        }

        self.activeChallenge = nil
        state = .failed("expired_code")
        print("[RokuricsPairing] pairing code expired")
    }
}
