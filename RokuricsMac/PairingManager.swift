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
    let confirmationToken: String
}

enum PairingState: Equatable {
    case idle
    case pairing(code: String, expiresAt: Date)
    case paired(deviceName: String)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return RokuricsCopy.text("未配对", "Unpaired")
        case .pairing:
            return RokuricsCopy.text("配对中", "Pairing")
        case .paired:
            return RokuricsCopy.text("已配对", "Paired")
        case .failed:
            return RokuricsCopy.text("配对失败", "Pairing failed")
        }
    }
}

@MainActor
final class PairingManager: ObservableObject {
    private struct PendingPairing {
        let result: PairingResult
        let deviceName: String
        let deviceType: String
        let pairingCode: String
        let expiresAt: Date
    }

    @Published private(set) var state: PairingState = .idle
    @Published private(set) var activeChallenge: PairingChallenge?

    private let pairedDeviceStore: PairedDeviceStore
    private let validityDuration: TimeInterval = 5 * 60
    private var pendingPairing: PendingPairing?
    private var confirmedTokensByDeviceID: [String: String] = [:]

    init(pairedDeviceStore: PairedDeviceStore) {
        self.pairedDeviceStore = pairedDeviceStore
    }

    func beginPairing(now: Date = Date()) {
        pendingPairing = nil
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let expiresAt = now.addingTimeInterval(validityDuration)
        let challenge = PairingChallenge(code: code, expiresAt: expiresAt)

        activeChallenge = challenge
        state = .pairing(code: code, expiresAt: expiresAt)
        print("[RokuricsPairing] pairing code generated: codeIssued=true, expiresAt=\(expiresAt)")
    }

    func invalidatePairing(reason: String = "invalidated") {
        activeChallenge = nil
        pendingPairing = nil
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
        pendingPairing = nil
        confirmedTokensByDeviceID.removeAll()
        state = .idle
        print("[RokuricsPairing] all paired devices cleared: \(reason)")
    }

    func preparePairing(deviceName: String, deviceType: String, code: String, now: Date = Date()) -> PairingResult? {
        print("[RokuricsPairing] pairing attempt received: deviceType=\(deviceType), name=\(deviceName)")

        guard let activeChallenge else {
            state = .failed("no_active_code")
            print("[RokuricsPairing] pairing failure: no_active_code")
            return nil
        }

        guard now <= activeChallenge.expiresAt else {
            self.activeChallenge = nil
            pendingPairing = nil
            state = .failed("expired_code")
            print("[RokuricsPairing] pairing failure: expired_code")
            return nil
        }

        guard code == activeChallenge.code else {
            state = .failed("bad_code")
            print("[RokuricsPairing] pairing failure: bad_code")
            return nil
        }

        if let pendingPairing,
           now <= pendingPairing.expiresAt,
           pendingPairing.deviceName == deviceName,
           pendingPairing.deviceType == deviceType,
           pendingPairing.pairingCode == code {
            return pendingPairing.result
        }

        let deviceID = "\(deviceType.lowercased())-\(UUID().uuidString.lowercased())"
        let sharedSecret = MacSecurityUtilities.randomBase64URLToken()
        let confirmationToken = MacSecurityUtilities.randomBase64URLToken()
        let device = PairedDevice(
            id: deviceID,
            deviceName: deviceName,
            sharedSecretBase64URL: sharedSecret,
            pairedAt: now,
            lastSeenAt: now
        )

        let result = PairingResult(
            device: device,
            sharedSecretBase64URL: sharedSecret,
            confirmationToken: confirmationToken
        )
        pendingPairing = PendingPairing(
            result: result,
            deviceName: deviceName,
            deviceType: deviceType,
            pairingCode: code,
            expiresAt: activeChallenge.expiresAt
        )
        print("[RokuricsPairing] pairing prepared: deviceIDPrefix=\(device.idPrefix)")
        return result
    }

    @discardableResult
    func confirmPairing(deviceID: String, confirmationToken: String, now: Date = Date()) -> Bool {
        if let storedToken = confirmedTokensByDeviceID[deviceID],
           MacSecurityUtilities.constantTimeEquals(storedToken, confirmationToken),
           pairedDeviceStore.device(for: deviceID) != nil {
            return true
        }
        guard let pendingPairing,
              now <= pendingPairing.expiresAt,
              pendingPairing.result.device.id == deviceID,
              MacSecurityUtilities.constantTimeEquals(pendingPairing.result.confirmationToken, confirmationToken),
              pairedDeviceStore.upsertPersisted(pendingPairing.result.device) else {
            return false
        }
        confirmedTokensByDeviceID[deviceID] = confirmationToken
        self.pendingPairing = nil
        activeChallenge = nil
        state = .paired(deviceName: pendingPairing.deviceName)
        print("[RokuricsPairing] pairing confirmed: deviceIDPrefix=\(pendingPairing.result.device.idPrefix)")
        return true
    }

    func pendingDeviceForCredentialProof(deviceID: String, now: Date = Date()) -> PairedDevice? {
        guard let pendingPairing,
              now <= pendingPairing.expiresAt,
              pendingPairing.result.device.id == deviceID else {
            return nil
        }
        return pendingPairing.result.device
    }

    @discardableResult
    func confirmPairingByCredentialProof(deviceID: String, now: Date = Date()) -> Bool {
        guard let pendingPairing,
              now <= pendingPairing.expiresAt,
              pendingPairing.result.device.id == deviceID,
              pairedDeviceStore.upsertPersisted(pendingPairing.result.device) else {
            return false
        }
        confirmedTokensByDeviceID[deviceID] = pendingPairing.result.confirmationToken
        self.pendingPairing = nil
        activeChallenge = nil
        state = .paired(deviceName: pendingPairing.deviceName)
        return true
    }

    /// Compatibility helper for non-network callers. Production `/pair` uses
    /// prepare + explicit confirmation.
    func completePairing(deviceName: String, deviceType: String, code: String, now: Date = Date()) -> PairingResult? {
        guard let result = preparePairing(deviceName: deviceName, deviceType: deviceType, code: code, now: now),
              confirmPairing(deviceID: result.device.id, confirmationToken: result.confirmationToken, now: now) else {
            return nil
        }
        return result
    }

    func refresh(now: Date = Date()) {
        guard let activeChallenge, now > activeChallenge.expiresAt else {
            return
        }

        self.activeChallenge = nil
        pendingPairing = nil
        state = .failed("expired_code")
        print("[RokuricsPairing] pairing code expired")
    }
}
