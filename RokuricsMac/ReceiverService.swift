//
//  ReceiverService.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation
import Darwin

@MainActor
final class ReceiverService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port = 8787
    @Published private(set) var statusText = "未启动"
    @Published private(set) var detailText = "等待 iPhone 连接"
    @Published private(set) var lastError: String?
    @Published private(set) var receivedCount = 0
    @Published private(set) var lastReceivedFileName = "暂无"
    @Published private(set) var localIPAddress = "未知"

    private let fileStore = ReceivedFileStore()
    private var server: LocalHTTPServer?
    private static let insecureHTTPDebugOverride = false

    init() {
        receivedCount = fileStore.savedFileCount()
        refreshLocalIPAddress()
    }

    func start() {
        refreshLocalIPAddress()
        guard Self.insecureHTTPDebugOverride else {
            print("[RokuricsSecurity] insecure HTTP receiver start blocked")
            lastError = "裸 HTTP 接收已禁用。请使用安全 HTTPS 接收。"
            statusText = "已隔离"
            detailText = lastError ?? "HTTP disabled"
            isRunning = false
            return
        }

        print("[RokuricsMacReceiver] server start requested")
        lastError = nil

        guard server == nil else {
            isRunning = true
            statusText = "运行中"
            detailText = "\(localIPAddress):\(port)"
            return
        }

        let server = LocalHTTPServer(
            port: port,
            store: fileStore,
            onReceived: { [weak self] record in
                Task { @MainActor [weak self] in
                    self?.handleReceivedFile(record)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleError(message)
                }
            },
            onRunningStateChanged: { [weak self] isRunning in
                Task { @MainActor [weak self] in
                    self?.handleRunningStateChanged(isRunning)
                }
            }
        )

        do {
            try server.start()
            self.server = server
            isRunning = true
            statusText = "运行中"
            detailText = "\(localIPAddress):\(port)"
        } catch {
            handleError("start failed: \(error)")
            self.server = nil
            isRunning = false
            statusText = "启动失败"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        statusText = "未启动"
        detailText = "等待 iPhone 连接"
    }

    private func handleReceivedFile(_ record: ReceivedFileRecord) {
        receivedCount = fileStore.savedFileCount()
        lastReceivedFileName = record.fileName
        lastError = nil
        detailText = "最近收到 \(record.fileName)"
    }

    private func handleError(_ message: String) {
        lastError = message
        detailText = message
    }

    private func handleRunningStateChanged(_ running: Bool) {
        isRunning = running
        statusText = running ? "运行中" : "未启动"
        if running {
            detailText = "\(localIPAddress):\(port)"
        }
    }

    private func refreshLocalIPAddress() {
        localIPAddress = LocalNetworkAddressProvider.preferredIPv4Address() ?? "未知"
    }
}

private enum LocalNetworkAddressProvider {
    struct AddressCandidate {
        let interfaceName: String
        let address: String
    }

    static func preferredIPv4Address() -> String? {
        let addresses = localIPv4Addresses()
        let addressText = addresses.map { "\($0.interfaceName)=\($0.address)" }.joined(separator: ", ")
        print("[RokuricsMacReceiver] local IP addresses: \(addressText.isEmpty ? "none" : addressText)")

        return addresses
            .sorted { lhs, rhs in
                score(lhs) > score(rhs)
            }
            .first { isPrivateIPv4($0.address) }?
            .address
    }

    private static func localIPv4Addresses() -> [AddressCandidate] {
        var interfaceAddressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddressPointer) == 0, let firstAddress = interfaceAddressPointer else {
            return []
        }

        defer {
            freeifaddrs(interfaceAddressPointer)
        }

        var candidates: [AddressCandidate] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let currentPointer = pointer {
            defer {
                pointer = currentPointer.pointee.ifa_next
            }

            let interface = currentPointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard
                flags & IFF_UP == IFF_UP,
                flags & IFF_LOOPBACK == 0,
                let addressPointer = interface.ifa_addr,
                addressPointer.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let interfaceName = String(cString: interface.ifa_name)
            let address = String(cString: hostname)
            candidates.append(AddressCandidate(interfaceName: interfaceName, address: address))
        }

        return candidates
    }

    private static func score(_ candidate: AddressCandidate) -> Int {
        var value = 0

        if isPrivateIPv4(candidate.address) {
            value += 100
        }

        if candidate.interfaceName == "en0" {
            value += 20
        } else if candidate.interfaceName.hasPrefix("en") {
            value += 10
        }

        if candidate.address.hasPrefix("192.168.") {
            value += 6
        } else if candidate.address.hasPrefix("10.") {
            value += 5
        } else if is172PrivateIPv4(candidate.address) {
            value += 4
        }

        return value
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        address.hasPrefix("192.168.") || address.hasPrefix("10.") || is172PrivateIPv4(address)
    }

    private static func is172PrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        guard parts.count == 4, parts[0] == "172", let second = Int(parts[1]) else {
            return false
        }

        return (16...31).contains(second)
    }
}
