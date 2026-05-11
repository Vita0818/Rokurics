//
//  MacLocalNetworkAddressProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Darwin
import Foundation

enum MacLocalNetworkAddressProvider {
    struct AddressCandidate {
        let interfaceName: String
        let address: String
    }

    static func preferredIPv4Address(logPrefix: String = "[RokuricsSecurity]") -> String? {
        let addresses = localIPv4Addresses()
        let addressText = addresses.map { "\($0.interfaceName)=\($0.address)" }.joined(separator: ", ")
        print("\(logPrefix) local IP addresses: \(addressText.isEmpty ? "none" : addressText)")

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

            candidates.append(
                AddressCandidate(
                    interfaceName: String(cString: interface.ifa_name),
                    address: String(cString: hostname)
                )
            )
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
