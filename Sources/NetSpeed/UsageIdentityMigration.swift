import Foundation

struct IdentityAliasIndex {
    var candidates: [String: Set<String>] = [:]
    var displayNames: [String: String] = [:]

    mutating func add(stableID: String, displayName: String, aliases: Set<String>) {
        displayNames[stableID] = displayName
        for alias in aliases {
            let normalized = Self.normalize(alias)
            guard !normalized.isEmpty else { continue }
            candidates[normalized, default: []].insert(stableID)
        }
    }

    mutating func addLegacyAlias(_ alias: String, candidates stableIDs: Set<String>) {
        let normalized = Self.normalize(alias)
        guard !normalized.isEmpty else { return }
        candidates[normalized, default: []].formUnion(stableIDs)
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum UsageIdentityMigration {
    static func addLegacyV3DiaAliases(to aliasIndex: inout IdentityAliasIndex) {
        let diaCandidates = aliasIndex.candidates[IdentityAliasIndex.normalize("Dia")] ?? []
        aliasIndex.addLegacyAlias("Browser Helper", candidates: diaCandidates)
        aliasIndex.addLegacyAlias("Browser Helper (Renderer)", candidates: diaCandidates)
    }

    static func migrate(
        _ usage: [String: UInt64],
        using aliasIndex: IdentityAliasIndex
    ) -> [String: UInt64] {
        var migrated: [String: UInt64] = [:]

        for (existingKey, bytes) in usage {
            let candidates = aliasIndex.candidates[IdentityAliasIndex.normalize(existingKey)] ?? []
            let destination: String
            if candidates.count == 1, let stableID = candidates.first {
                destination = stableID
            } else {
                destination = existingKey
            }
            migrated[destination, default: 0] += bytes
        }

        return migrated
    }
}
