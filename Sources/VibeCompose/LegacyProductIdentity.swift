import Foundation
import Security

/// Technical compatibility identifiers for installations created before the
/// VibeCompose rename. These values are intentionally not user-facing.
enum LegacyProductIdentity {
    static let name = "VibeWhisper"
    static let defaultBundleIdentifier = "app.vibewhisper.mac"
    static let keychainService =
        "\(defaultBundleIdentifier).ChatGPTSession"
    static let recoveryAPIKeychainService =
        "\(defaultBundleIdentifier).OpenAICompatibleAPIKey"
    static let polishAPIKeychainService =
        "\(defaultBundleIdentifier).OpenAICompatiblePolishAPIKey"
    static let skillPackageExtension = "vibewhisperskill"

    static func applicationSupportURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
            .appendingPathComponent(name, isDirectory: true)
    }

    static func keychainService(forCurrentService service: String) -> String? {
        switch service {
        case ProductIdentity.keychainService:
            return keychainService
        case ProductIdentity.recoveryAPIKeychainService:
            return recoveryAPIKeychainService
        case ProductIdentity.polishAPIKeychainService:
            return polishAPIKeychainService
        default:
            return nil
        }
    }

    static func isUnavailableLegacyKeychainStatus(
        _ status: OSStatus
    ) -> Bool {
        status == errSecMissingEntitlement
            || status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecNotAvailable
    }

    static func canonicalizingBuiltInSkillReferences(
        in config: AppConfig,
        registry: SkillRegistry = .builtIn
    ) -> AppConfig {
        BuiltInSkillReferenceMigration(registry: registry)
            .canonicalizing(config)
    }

    private struct BuiltInSkillReferenceMigration {
        let skillIDs: [String: String]
        let installationIDs: [UUID: UUID]

        init(registry: SkillRegistry) {
            let currentPrefix = "app.\(ProductIdentity.slug).skill."
            let legacyPrefix = LegacyProductIdentity
                .defaultBundleIdentifier
                .replacingOccurrences(of: ".mac", with: ".skill.")
            var skillIDs: [String: String] = [:]
            var installationIDs: [UUID: UUID] = [:]

            for definition in registry.orderedDefinitions {
                let currentSkillID = definition.id
                guard currentSkillID.hasPrefix(currentPrefix) else {
                    continue
                }
                let legacySkillID = legacyPrefix
                    + currentSkillID.dropFirst(currentPrefix.count)
                skillIDs[legacySkillID] = currentSkillID

                let currentInstallationID = InstalledSkillIdentity
                    .normalized(
                        definition: definition,
                        sourceID: "builtin"
                    ).id
                let legacySeeds = [
                    (LegacyProductIdentity.name, legacySkillID),
                    (ProductIdentity.name, legacySkillID),
                    (LegacyProductIdentity.name, currentSkillID),
                ]
                for (productName, skillID) in legacySeeds {
                    installationIDs[
                        StableIdentifier.uuid(
                            namespace:
                                "\(productName).InstalledSkillIdentity",
                            components: [
                                "builtin",
                                nil,
                                skillID,
                                "1.0.0",
                            ]
                        )
                    ] = currentInstallationID
                    installationIDs[
                        StableIdentifier.uuid(
                            namespace:
                                "\(productName).AppSkillRule.Installation",
                            components: [skillID]
                        )
                    ] = currentInstallationID
                }
            }

            // Retired built-in Skills: references to a merged-away Skill
            // (current or pre-rename ID) canonicalize to its successor.
            for (retiredSkillID, successorSkillID)
                in SkillRegistry.retiredSkillIDAliases
            {
                guard
                    retiredSkillID.hasPrefix(currentPrefix),
                    let successor = registry.orderedDefinitions.first(
                        where: { $0.id == successorSkillID }
                    )
                else {
                    continue
                }
                let legacyRetiredSkillID = legacyPrefix
                    + retiredSkillID.dropFirst(currentPrefix.count)
                skillIDs[retiredSkillID] = successorSkillID
                skillIDs[legacyRetiredSkillID] = successorSkillID

                let successorInstallationID = InstalledSkillIdentity
                    .normalized(
                        definition: successor,
                        sourceID: "builtin"
                    ).id
                for productName in [
                    LegacyProductIdentity.name,
                    ProductIdentity.name,
                ] {
                    for skillID in [retiredSkillID, legacyRetiredSkillID] {
                        installationIDs[
                            StableIdentifier.uuid(
                                namespace:
                                    "\(productName).InstalledSkillIdentity",
                                components: [
                                    "builtin",
                                    nil,
                                    skillID,
                                    "1.0.0",
                                ]
                            )
                        ] = successorInstallationID
                        installationIDs[
                            StableIdentifier.uuid(
                                namespace:
                                    "\(productName).AppSkillRule.Installation",
                                components: [skillID]
                            )
                        ] = successorInstallationID
                    }
                }
            }

            self.skillIDs = skillIDs
            self.installationIDs = installationIDs
        }

        func canonicalizing(_ source: AppConfig) -> AppConfig {
            var config = source
            canonicalizeSkills(in: &config)
            canonicalizeContext(in: &config)
            canonicalizeStyleCapsules(in: &config)
            canonicalizeCommunitySkills(in: &config)
            canonicalizeSkillEcosystem(in: &config)
            return config
        }

        private func canonicalizeSkills(in config: inout AppConfig) {
            var skills = config.transcription.skills
            skills.defaultSkillID = canonicalSkillID(
                skills.defaultSkillID
            )
            skills.defaultSkillInstallationID =
                skills.defaultSkillInstallationID.map(
                    canonicalInstallationID
                )
            skills.enabledSkillIDs = canonicalizedValues(
                skills.enabledSkillIDs,
                transform: { skillID in
                    let canonical = canonicalSkillID(skillID)
                    return (canonical, canonical == skillID)
                },
                key: { $0 }
            )
            skills.applicationRules = skills.applicationRules.map { rule in
                var canonical = rule
                canonical.skillID = canonicalSkillID(rule.skillID)
                canonical.skillInstallationID = canonicalInstallationID(
                    rule.skillInstallationID
                )
                return canonical
            }
            config.transcription.skills = skills
        }

        private func canonicalizeContext(in config: inout AppConfig) {
            config.context.permissionGrants = canonicalizedValues(
                config.context.permissionGrants,
                transform: { grant in
                    var canonical = grant
                    canonical.skillID = canonicalSkillID(grant.skillID)
                    return (canonical, canonical.skillID == grant.skillID)
                },
                key: \.id
            )
            config.context.recentReceipts = config.context.recentReceipts.map {
                receipt in
                let installationID = canonicalInstallationID(
                    receipt.installationID
                )
                guard installationID != receipt.installationID else {
                    return receipt
                }
                return ContextReceipt(
                    id: receipt.id,
                    sessionID: receipt.sessionID,
                    installationID: installationID,
                    requestedSources: receipt.requestedSources,
                    grantedSources: receipt.grantedSources,
                    deniedSources: receipt.deniedSources,
                    characterCounts: receipt.characterCounts,
                    decisions: receipt.decisions,
                    createdAt: receipt.createdAt
                )
            }
        }

        private func canonicalizeStyleCapsules(in config: inout AppConfig) {
            config.styleCapsules.skillAssignments = canonicalizedValues(
                config.styleCapsules.skillAssignments,
                transform: { assignment in
                    var canonical = assignment
                    canonical.skillID = canonicalSkillID(assignment.skillID)
                    return (
                        canonical,
                        canonical.skillID == assignment.skillID
                    )
                },
                key: \.id
            )
        }

        private func canonicalizeCommunitySkills(in config: inout AppConfig) {
            config.communitySkills.activeVersions = canonicalizedValues(
                config.communitySkills.activeVersions,
                transform: { selection in
                    var canonical = selection
                    canonical.skillID = canonicalSkillID(selection.skillID)
                    return (
                        canonical,
                        canonical.skillID == selection.skillID
                    )
                },
                key: \.id
            )
        }

        private func canonicalizeSkillEcosystem(in config: inout AppConfig) {
            config.skillEcosystem.favoriteInstallationIDs =
                canonicalizedInstallationIDs(
                    config.skillEcosystem.favoriteInstallationIDs
                ).sorted {
                    $0.uuidString < $1.uuidString
                }
            config.skillEcosystem.recentInstallationIDs =
                canonicalizedInstallationIDs(
                    config.skillEcosystem.recentInstallationIDs
                )
            config.skillEcosystem.collections =
                config.skillEcosystem.collections.map { collection in
                    var canonical = collection
                    canonical.items = canonicalizedValues(
                        collection.items,
                        transform: { item in
                            var canonicalItem = item
                            canonicalItem.installationID =
                                canonicalInstallationID(
                                    item.installationID
                                )
                            return (
                                canonicalItem,
                                canonicalItem.installationID
                                    == item.installationID
                            )
                        },
                        key: \.installationID
                    )
                    return canonical
                }
        }

        private func canonicalizedInstallationIDs(
            _ values: [UUID]
        ) -> [UUID] {
            canonicalizedValues(
                values,
                transform: { installationID in
                    let canonical = canonicalInstallationID(installationID)
                    return (canonical, canonical == installationID)
                },
                key: { $0 }
            )
        }

        private func canonicalSkillID(_ value: String) -> String {
            skillIDs[value] ?? value
        }

        private func canonicalInstallationID(_ value: UUID) -> UUID {
            installationIDs[value] ?? value
        }

        private func canonicalizedValues<Value, Key: Hashable>(
            _ values: [Value],
            transform: (Value) -> (value: Value, isCanonical: Bool),
            key: (Value) -> Key
        ) -> [Value] {
            var output: [Value] = []
            var indexesByKey: [Key: Int] = [:]
            var canonicalKeys = Set<Key>()

            for value in values {
                let transformed = transform(value)
                let transformedKey = key(transformed.value)
                if let index = indexesByKey[transformedKey] {
                    if transformed.isCanonical,
                       canonicalKeys.insert(transformedKey).inserted
                    {
                        output[index] = transformed.value
                    }
                    continue
                }
                indexesByKey[transformedKey] = output.count
                if transformed.isCanonical {
                    canonicalKeys.insert(transformedKey)
                }
                output.append(transformed.value)
            }
            return output
        }
    }
}
