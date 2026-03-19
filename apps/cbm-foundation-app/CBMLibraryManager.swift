import Foundation
import CommonCrypto

// MARK: - Configuration

/// Override the default download URL by setting CBM_VICE_URL in the environment,
/// or by writing a custom URL to ~/Library/Application Support/cbm-foundation/vice-source.url
///
/// Priority order:
///   1. Environment variable: CBM_VICE_URL
///   2. User override file:   ~/Library/Application Support/cbm-foundation/vice-source.url
///   3. Default:              GitHub Releases (davidwhittington/cbm-foundation)

// MARK: - Types

enum CBMLibraryState: Equatable {
    case notInstalled
    case installed(version: String)
    case updateAvailable(installed: String, latest: String)
    case downloading(progress: Double)
    case error(String)
}

struct CBMReleaseInfo: Codable {
    let tagName: String
    let assets: [CBMReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct CBMReleaseAsset: Codable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

// MARK: - CBMLibraryManager

@Observable
final class CBMLibraryManager {

    static let shared = CBMLibraryManager()

    // GitHub Releases API endpoint
    private static let releasesURL = "https://api.github.com/repos/davidwhittington/cbm-foundation/releases/latest"
    private static let appSupportDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cbm-foundation")
    }()

    var state: CBMLibraryState = .notInstalled
    var downloadProgress: Double = 0

    private var downloadTask: URLSessionDownloadTask?

    // MARK: - Paths

    var libraryURL: URL {
        Self.appSupportDir.appendingPathComponent("libvice.dylib")
    }

    var installedVersionURL: URL {
        Self.appSupportDir.appendingPathComponent("libvice-version.txt")
    }

    private var userOverrideURL: URL {
        Self.appSupportDir.appendingPathComponent("vice-source.url")
    }

    // MARK: - Init

    private init() {
        try? FileManager.default.createDirectory(at: Self.appSupportDir,
                                                  withIntermediateDirectories: true)
        refreshState()
    }

    // MARK: - State

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: libraryURL.path)
    }

    var installedVersion: String? {
        try? String(contentsOf: installedVersionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refreshState() {
        if isInstalled, let version = installedVersion {
            state = .installed(version: version)
        } else {
            state = .notInstalled
        }
    }

    // MARK: - Override URL resolution

    /// Returns the download base URL to use, respecting overrides.
    private func resolveDownloadSource() async throws -> String {
        // 1. Environment variable
        if let envURL = ProcessInfo.processInfo.environment["CBM_VICE_URL"],
           !envURL.isEmpty {
            return envURL
        }

        // 2. User override file
        if FileManager.default.fileExists(atPath: userOverrideURL.path),
           let override = try? String(contentsOf: userOverrideURL, encoding: .utf8)
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }

        // 3. Default: fetch latest GitHub Release
        return try await fetchLatestReleaseURL()
    }

    // MARK: - GitHub Release lookup

    func checkForUpdate() async {
        guard case .installed(let current) = state else { return }
        do {
            let latest = try await fetchLatestTag()
            if latest != current {
                state = .updateAvailable(installed: current, latest: latest)
            }
        } catch {
            // Non-fatal — stay in installed state
        }
    }

    private func fetchLatestTag() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: URL(string: Self.releasesURL)!)
        let release = try JSONDecoder().decode(CBMReleaseInfo.self, from: data)
        return release.tagName
    }

    private func fetchLatestReleaseURL() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: URL(string: Self.releasesURL)!)
        let release = try JSONDecoder().decode(CBMReleaseInfo.self, from: data)

        guard let asset = release.assets.first(where: { $0.name == "libvice.dylib" }) else {
            throw CBMLibraryError.assetNotFound
        }
        return asset.browserDownloadURL
    }

    // MARK: - Download

    func download() async {
        state = .downloading(progress: 0)
        downloadProgress = 0

        do {
            let urlString = try await resolveDownloadSource()
            guard let url = URL(string: urlString) else {
                throw CBMLibraryError.invalidURL(urlString)
            }

            let tempURL = try await downloadFile(from: url)
            try await verifyAndInstall(tempURL: tempURL, sourceURL: url)

            refreshState()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        refreshState()
    }

    private func downloadFile(from url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default,
                                     delegate: DownloadDelegate(manager: self),
                                     delegateQueue: nil)
            let task = session.downloadTask(with: url) { tempURL, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tempURL {
                    continuation.resume(returning: tempURL)
                } else {
                    continuation.resume(throwing: CBMLibraryError.downloadFailed)
                }
            }
            self.downloadTask = task
            task.resume()
        }
    }

    private func verifyAndInstall(tempURL: URL, sourceURL: URL) async throws {
        // Verify SHA256 if a checksum file is available
        let checksumURL = URL(string: sourceURL.absoluteString + ".sha256")!
        if let checksumData = try? await URLSession.shared.data(from: checksumURL).0,
           let expected = String(data: checksumData, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines) {
            let actual = try sha256(of: tempURL)
            guard actual == expected else {
                throw CBMLibraryError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        // Install
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            try FileManager.default.removeItem(at: libraryURL)
        }
        try FileManager.default.copyItem(at: tempURL, to: libraryURL)

        // Fetch and store version tag
        if let tag = try? await fetchLatestTag() {
            try tag.write(to: installedVersionURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - SHA256

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - dlopen

    /// Load the VICE library into the process. Must be called before VICEEngine starts.
    @discardableResult
    func loadLibrary() -> Bool {
        guard isInstalled else { return false }
        let handle = dlopen(libraryURL.path, RTLD_LAZY | RTLD_GLOBAL)
        return handle != nil
    }
}

// MARK: - Download delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: CBMLibraryManager?
    init(manager: CBMLibraryManager) { self.manager = manager }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.manager?.downloadProgress = progress
            self.manager?.state = .downloading(progress: progress)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

// MARK: - Errors

enum CBMLibraryError: LocalizedError {
    case assetNotFound
    case invalidURL(String)
    case downloadFailed
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "libvice.dylib not found in the latest GitHub release."
        case .invalidURL(let url):
            return "Invalid download URL: \(url)"
        case .downloadFailed:
            return "Download failed with no error information."
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch — expected \(expected), got \(actual). Download may be corrupt."
        }
    }
}
