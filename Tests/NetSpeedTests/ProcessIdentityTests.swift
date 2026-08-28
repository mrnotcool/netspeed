import XCTest
@testable import NetSpeed

final class ProcessIdentityTests: XCTestCase {
    func testStableIDUsesBundleIdentifierAcrossBundlePathChanges() {
        let first = ProcessIdentityResolver.stableID(
            bundleIdentifier: "com.example.product",
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let second = ProcessIdentityResolver.stableID(
            bundleIdentifier: "com.example.product",
            bundleURL: URL(fileURLWithPath: "/Applications/示例.app")
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "bundle:com.example.product")
    }

    func testLocalizedNamesMigrateToOneStableIdentity() {
        var index = IdentityAliasIndex()
        index.add(
            stableID: "bundle:com.example.product",
            displayName: "示例",
            aliases: ["Example", "示例"]
        )

        let migrated = UsageIdentityMigration.migrate(
            ["Example": 40, "示例": 60],
            using: index
        )

        XCTAssertEqual(migrated, ["bundle:com.example.product": 100])
    }

    func testConflictingAliasRemainsUnchanged() {
        var index = IdentityAliasIndex()
        index.add(stableID: "bundle:one", displayName: "One", aliases: ["Helper"])
        index.add(stableID: "bundle:two", displayName: "Two", aliases: ["Helper"])

        let migrated = UsageIdentityMigration.migrate(["Helper": 75], using: index)

        XCTAssertEqual(migrated, ["Helper": 75])
    }

    func testLegacyMigrationIsIdempotent() {
        var index = IdentityAliasIndex()
        index.add(stableID: "bundle:com.example.product", displayName: "Example", aliases: ["Example"])

        let first = UsageIdentityMigration.migrate(["Example": 25], using: index)
        let second = UsageIdentityMigration.migrate(first, using: index)

        XCTAssertEqual(first, second)
    }

    func testLegacyDiaHelperAliasIsIsolatedToMigration() {
        var index = IdentityAliasIndex()
        index.add(stableID: "bundle:company.thebrowser", displayName: "Dia", aliases: ["Dia"])
        UsageIdentityMigration.addLegacyV3DiaAliases(to: &index)

        let migrated = UsageIdentityMigration.migrate(["Browser Helper": 25], using: index)

        XCTAssertEqual(migrated, ["bundle:company.thebrowser": 25])
    }

    func testWrappedIOSExecutableUsesInnerApplicationBundle() {
        let executable = "/Applications/rednote.app/Wrapper/discover.app/discover"

        let bundleURL = ProcessIdentityResolver.owningApplicationBundleURL(
            containingExecutableAt: executable
        )

        XCTAssertEqual(bundleURL?.path, "/Applications/rednote.app/Wrapper/discover.app")
    }

    func testRegularHelperUsesOwningOuterApplicationBundle() {
        let executable = "/Applications/Dia.app/Contents/Frameworks/Browser Helper.app/Contents/MacOS/Browser Helper"

        let bundleURL = ProcessIdentityResolver.owningApplicationBundleURL(
            containingExecutableAt: executable
        )

        XCTAssertEqual(bundleURL?.path, "/Applications/Dia.app")
    }
}
