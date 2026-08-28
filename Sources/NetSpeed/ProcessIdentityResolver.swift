import Foundation
import AppKit
import Darwin

struct ProcessIdentity {
    enum Category {
        case application
        case systemServices
        case executable
    }

    let stableID: String
    let displayName: String
    let icon: NSImage
    let bundleURL: URL?
    let aliases: Set<String>
    let category: Category
}

final class ProcessIdentityResolver {
    static let systemServicesDisplayName = "System Services"

    private static let systemServicePathPrefixes = [
        "/usr/libexec/",
        "/usr/sbin/",
        "/System/Library/",
        "/System/Cryptexes/App/usr/libexec/",
        "/System/Cryptexes/App/System/Library/",
        "/Library/Apple/System/Library/",
    ]

    let systemServicesIcon = ProcessIdentityResolver.coreTypesIcon(
        named: "ToolbarCustomizeIcon.icns",
        fallbackSymbolName: "wrench.and.screwdriver.fill"
    )
    private let genericExecutableIcon = ProcessIdentityResolver.coreTypesIcon(
        named: "ExecutableBinaryIcon.icns",
        fallbackSymbolName: "terminal"
    )
    private let cacheLock = NSLock()
    private var identityCache: [String: ProcessIdentity] = [:]
    private var bundleURLCache: [String: [URL]] = [:]
    private var appInfoCache: [String: [String: Any]] = [:]
    private var missingAppInfoPaths: Set<String> = []
    private var applicationIconCache: [String: NSImage] = [:]
    private var wrappedAliasesCache: [String: String]?

    func resolve(pid: Int32, rawName: String) -> ProcessIdentity {
        let executablePath = getExecutablePath(pid: pid)

        // Prefer the bundle that directly owns the executable. This also resolves
        // Mac App Store iOS wrappers to their embedded application bundle.
        if let executablePath,
           let bundleURL = applicationBundleURL(containingExecutableAt: executablePath) {
            return applicationIdentity(bundleURL: bundleURL)
        }

        // Helper processes commonly inherit their public identity from a parent app.
        var currentPID = pid
        var depth = 0
        while depth < 5 && currentPID > 1 {
            if let runningApp = NSRunningApplication(processIdentifier: currentPID) {
                if let outerURL = runningApp.bundleURL {
                    return applicationIdentity(bundleURL: applicationIdentityBundleURL(at: outerURL))
                }
                if let localizedName = runningApp.localizedName, !localizedName.isEmpty {
                    let displayName = canonicalDisplayName(localizedName)
                    return ProcessIdentity(
                        stableID: "process:\(normalize(displayName))",
                        displayName: displayName,
                        icon: runningApp.icon ?? icon(appName: displayName, pid: currentPID),
                        bundleURL: nil,
                        aliases: [localizedName, displayName],
                        category: .executable
                    )
                }
            }
            guard let parentPID = getParentPID(pid: currentPID), parentPID > 1 else { break }
            currentPID = parentPID
            depth += 1
        }

        if let executablePath, isSystemServiceExecutable(at: executablePath) {
            return ProcessIdentity(
                stableID: "system-services",
                displayName: Self.systemServicesDisplayName,
                icon: systemServicesIcon,
                bundleURL: nil,
                aliases: [rawName, Self.systemServicesDisplayName],
                category: .systemServices
            )
        }

        let displayName = canonicalDisplayName(rawName)
        return ProcessIdentity(
            stableID: "process:\(normalize(displayName))",
            displayName: displayName,
            icon: icon(appName: displayName, pid: pid),
            bundleURL: nil,
            aliases: [rawName, displayName],
            category: .executable
        )
    }

    func icon(appName: String, pid: Int32 = 0) -> NSImage {
        if appName == Self.systemServicesDisplayName {
            return systemServicesIcon
        }

        if pid > 0,
           let executablePath = getExecutablePath(pid: pid),
           let bundleURL = applicationBundleURL(containingExecutableAt: executablePath) {
            return iconForApplication(at: bundleURL)
        }

        if pid > 0,
           let runningApp = NSRunningApplication(processIdentifier: pid),
           let icon = runningApp.icon {
            return icon
        }

        if pid > 0 {
            var currentPID = pid
            var depth = 0
            while depth < 5 && currentPID > 1 {
                if let runningApp = NSRunningApplication(processIdentifier: currentPID),
                   let icon = runningApp.icon {
                    return icon
                }
                guard let parentPID = getParentPID(pid: currentPID) else { break }
                currentPID = parentPID
                depth += 1
            }
        }

        let targetName = normalize(appName)
        for runningApp in NSWorkspace.shared.runningApplications {
            if let localizedName = runningApp.localizedName,
               normalize(localizedName) == targetName,
               let icon = runningApp.icon {
                return icon
            }
        }

        for directory in applicationSearchDirectories() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for outerURL in children where outerURL.pathExtension.lowercased() == "app" {
                if appBundleURLs(at: outerURL).contains(where: {
                    applicationNameMatches(appName, bundleURL: $0)
                }) {
                    return iconForApplication(at: outerURL)
                }
            }
        }

        return genericExecutableIcon
    }

    func wrappedApplicationAliases() -> [String: String] {
        cacheLock.lock()
        if let cached = wrappedAliasesCache {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var aliases: [String: String] = [:]

        for directory in applicationSearchDirectories(includeSystemApplications: false) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for outerURL in children where outerURL.pathExtension.lowercased() == "app" {
                for bundleURL in appBundleURLs(at: outerURL)
                    where bundleURL.path != outerURL.path && isIOSApplicationBundle(at: bundleURL) {
                    // Startup migration only needs metadata. Avoid decoding every
                    // wrapped app icon just to construct its historical aliases.
                    let displayName = applicationDisplayName(at: bundleURL)
                    let bundleAliases = applicationAliases(at: bundleURL).union([
                        outerURL.deletingPathExtension().lastPathComponent,
                    ])
                    for alias in bundleAliases {
                        aliases[normalize(alias)] = displayName
                    }
                }
            }
        }

        cacheLock.lock()
        if let cached = wrappedAliasesCache {
            cacheLock.unlock()
            return cached
        }
        wrappedAliasesCache = aliases
        cacheLock.unlock()
        return aliases
    }

    func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applicationIdentity(bundleURL: URL) -> ProcessIdentity {
        let identityURL = applicationIdentityBundleURL(at: bundleURL)
        let cacheKey = identityURL.resolvingSymlinksInPath().standardizedFileURL.path

        cacheLock.lock()
        if let cached = identityCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let displayName = applicationDisplayName(at: identityURL)
        let info = appInfoDictionary(at: identityURL)
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let stableID = bundleIdentifier.map { "bundle:\($0.lowercased())" }
            ?? "bundle-path:\(identityURL.standardizedFileURL.path.lowercased())"

        let identity = ProcessIdentity(
            stableID: stableID,
            displayName: displayName,
            icon: iconForApplication(at: identityURL),
            bundleURL: identityURL,
            aliases: applicationAliases(at: identityURL),
            category: .application
        )

        cacheLock.lock()
        if let cached = identityCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        identityCache[cacheKey] = identity
        cacheLock.unlock()
        return identity
    }

    private func canonicalDisplayName(_ name: String) -> String {
        switch name {
        case "Browser Helper", "Browser Helper (Renderer)":
            return "Dia"
        default:
            return name
        }
    }

    private func getParentPID(pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        return result == size ? Int32(info.pbi_ppid) : nil
    }

    private func getExecutablePath(pid: Int32) -> String? {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        defer { buffer.deallocate() }
        guard proc_pidpath(pid, buffer, UInt32(MAXPATHLEN)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func isSystemServiceExecutable(at path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return Self.systemServicePathPrefixes.contains { standardizedPath.hasPrefix($0) }
    }

    private func applicationBundleURL(containingExecutableAt path: String) -> URL? {
        let components = path.components(separatedBy: "/")
        let appIndices = components.indices.filter {
            components[$0].lowercased().hasSuffix(".app")
        }
        guard let outerIndex = appIndices.first else { return nil }

        let identityIndex = appIndices.last { index in
            guard index > outerIndex else { return false }
            return components[outerIndex...index].contains("Wrapper")
                || components[outerIndex...index].contains("WrappedBundle")
        } ?? outerIndex

        let appPath = "/" + components[1...identityIndex].joined(separator: "/")
        return URL(fileURLWithPath: appPath, isDirectory: true)
    }

    private func applicationIdentityBundleURL(at outerURL: URL) -> URL {
        appBundleURLs(at: outerURL).first {
            $0.path != outerURL.path && isIOSApplicationBundle(at: $0)
        } ?? outerURL
    }

    private func applicationDisplayName(at bundleURL: URL) -> String {
        let dictionaries = [
            Bundle(url: bundleURL)?.localizedInfoDictionary,
            appInfoDictionary(at: bundleURL),
        ]

        for dictionary in dictionaries {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = dictionary?[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    private func applicationAliases(at bundleURL: URL) -> Set<String> {
        var aliases: Set<String> = [
            bundleURL.deletingPathExtension().lastPathComponent,
            applicationDisplayName(at: bundleURL),
        ]

        if let info = appInfoDictionary(at: bundleURL) {
            for key in ["CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"] {
                if let value = info[key] as? String, !value.isEmpty {
                    aliases.insert(value)
                }
            }
            if let identifier = info["CFBundleIdentifier"] as? String {
                aliases.insert(identifier)
                if let lastComponent = identifier.split(separator: ".").last {
                    aliases.insert(String(lastComponent))
                }
            }
        }
        return aliases
    }

    private func applicationSearchDirectories(includeSystemApplications: Bool = true) -> [URL] {
        var paths = ["/Applications", "\(NSHomeDirectory())/Applications"]
        if includeSystemApplications {
            paths.insert(contentsOf: ["/System/Applications", "/System/Applications/Utilities"], at: 1)
        }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func appBundleURLs(at outerURL: URL) -> [URL] {
        let cacheKey = outerURL.resolvingSymlinksInPath().standardizedFileURL.path
        cacheLock.lock()
        if let cached = bundleURLCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var urls: [URL] = []

        func appendIfNeeded(_ url: URL) {
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.pathExtension.lowercased() == "app",
                  FileManager.default.fileExists(atPath: resolvedURL.path),
                  !urls.contains(where: { $0.path == resolvedURL.path }) else { return }
            urls.append(resolvedURL)
        }

        appendIfNeeded(outerURL.appendingPathComponent("WrappedBundle"))

        let wrapperURL = outerURL.appendingPathComponent("Wrapper", isDirectory: true)
        if let children = try? FileManager.default.contentsOfDirectory(
            at: wrapperURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for child in children where child.pathExtension.lowercased() == "app" {
                appendIfNeeded(child)
            }
        }

        appendIfNeeded(outerURL)

        cacheLock.lock()
        if let cached = bundleURLCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        bundleURLCache[cacheKey] = urls
        cacheLock.unlock()
        return urls
    }

    private func appInfoDictionary(at bundleURL: URL) -> [String: Any]? {
        let cacheKey = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        cacheLock.lock()
        if let cached = appInfoCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        if missingAppInfoPaths.contains(cacheKey) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        let infoURLs = [
            bundleURL.appendingPathComponent("Contents/Info.plist"),
            bundleURL.appendingPathComponent("Info.plist"),
        ]

        for infoURL in infoURLs {
            guard let data = try? Data(contentsOf: infoURL),
                  let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = propertyList as? [String: Any] else { continue }

            cacheLock.lock()
            appInfoCache[cacheKey] = dictionary
            cacheLock.unlock()
            return dictionary
        }

        cacheLock.lock()
        missingAppInfoPaths.insert(cacheKey)
        cacheLock.unlock()
        return nil
    }

    private func isIOSApplicationBundle(at bundleURL: URL) -> Bool {
        guard let info = appInfoDictionary(at: bundleURL) else { return false }
        return (info["LSRequiresIPhoneOS"] as? Bool == true) || info["UIDeviceFamily"] != nil
    }

    private func applicationNameMatches(_ appName: String, bundleURL: URL) -> Bool {
        let target = normalize(appName)
        return !target.isEmpty && applicationAliases(at: bundleURL).contains {
            normalize($0) == target
        }
    }

    private func declaredIconNames(in object: Any) -> [String] {
        if let dictionary = object as? [String: Any] {
            return dictionary.flatMap { key, value -> [String] in
                var names: [String] = []
                if key == "CFBundleIconName" || key.hasPrefix("CFBundleIconFile") {
                    if let name = value as? String {
                        names.append(name)
                    } else if let values = value as? [String] {
                        names.append(contentsOf: values)
                    }
                }
                names.append(contentsOf: declaredIconNames(in: value))
                return names
            }
        }
        if let array = object as? [Any] {
            return array.flatMap { declaredIconNames(in: $0) }
        }
        return []
    }

    private func normalizedIOSIcon(_ image: NSImage) -> NSImage {
        let side = max(image.size.width, image.size.height)
        guard side > 0 else { return image }

        let canvasSize = NSSize(width: side, height: side)
        let inset = side * 0.065
        let iconRect = NSRect(
            x: inset,
            y: inset,
            width: side - inset * 2,
            height: side - inset * 2
        )
        let cornerRadius = iconRect.width * 0.22

        let normalized = NSImage(size: canvasSize, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            NSBezierPath(
                roundedRect: iconRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).addClip()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: iconRect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        normalized.isTemplate = false
        return normalized
    }

    private func declaredIcon(at bundleURL: URL) -> NSImage? {
        guard let info = appInfoDictionary(at: bundleURL) else { return nil }
        let isIOSApplication = (info["LSRequiresIPhoneOS"] as? Bool == true)
            || info["UIDeviceFamily"] != nil
        let resourceURLs = [
            bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
            bundleURL.appendingPathComponent("Resources", isDirectory: true),
            bundleURL,
        ]

        for declaredName in declaredIconNames(in: info) {
            let name = (declaredName as NSString).deletingPathExtension
            let originalExtension = (declaredName as NSString).pathExtension
            let filenames = originalExtension.isEmpty
                ? ["\(name)@3x.png", "\(name)@2x.png", "\(name).png", "\(name).icns", name]
                : [declaredName]

            for resourceURL in resourceURLs {
                for filename in filenames {
                    let iconURL = resourceURL.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: iconURL) {
                        return isIOSApplication ? normalizedIOSIcon(image) : image
                    }
                }
            }
        }
        return nil
    }

    private func iconForApplication(at outerURL: URL) -> NSImage {
        let cacheKey = outerURL.resolvingSymlinksInPath().standardizedFileURL.path
        cacheLock.lock()
        if let cached = applicationIconCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let bundleURLs = appBundleURLs(at: outerURL)
        let icon: NSImage
        for bundleURL in bundleURLs {
            if let declaredIcon = declaredIcon(at: bundleURL) {
                icon = declaredIcon
                cacheLock.lock()
                applicationIconCache[cacheKey] = icon
                cacheLock.unlock()
                return icon
            }
        }
        icon = NSWorkspace.shared.icon(forFile: (bundleURLs.first ?? outerURL).path)
        cacheLock.lock()
        applicationIconCache[cacheKey] = icon
        cacheLock.unlock()
        return icon
    }

    private static func coreTypesIcon(named filename: String, fallbackSymbolName: String) -> NSImage {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(filename)"
        if let image = NSImage(contentsOfFile: path) {
            return image
        }

        if #available(macOS 11.0, *),
           let symbolImage = NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil) {
            return symbolImage.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) ?? symbolImage
        }

        return NSWorkspace.shared.icon(
            forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon))
        )
    }
}
