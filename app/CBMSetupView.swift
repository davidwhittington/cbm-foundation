import SwiftUI

/// Shown on first launch or when libvice.dylib is missing/outdated.
/// Dismissed automatically once the library is ready.
struct CBMSetupView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var lib = CBMLibraryManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)

                Text("VICE Emulation Core")
                    .font(.title2.weight(.semibold))

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 32)

            Divider()

            // Content
            VStack(spacing: 20) {
                switch lib.state {
                case .notInstalled:
                    notInstalledBody

                case .updateAvailable(let installed, let latest):
                    updateAvailableBody(installed: installed, latest: latest)

                case .downloading(let progress):
                    downloadingBody(progress: progress)

                case .installed:
                    installedBody

                case .error(let message):
                    errorBody(message: message)
                }
            }
            .padding(32)
            .frame(minHeight: 180)

            // Override hint
            Divider()
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Set **CBM_VICE_URL** or place a URL in `~/Library/Application Support/cbm-foundation/vice-source.url` to use a custom build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: lib.state) { _, newState in
            if case .installed = newState {
                lib.loadLibrary()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Close the hosting window — AppDelegate.windowWillClose fires the completion
                    NSApp.keyWindow?.close()
                }
            }
        }
    }

    // MARK: - State views

    private var notInstalledBody: some View {
        VStack(spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emulation core not found")
                        .fontWeight(.medium)
                    Text("cbm-foundation requires the VICE emulation core (~12 MB). It will be downloaded from GitHub Releases and stored in Application Support.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                    .font(.title2)
            }

            Button("Download VICE Core") {
                Task { await lib.download() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func updateAvailableBody(installed: String, latest: String) -> some View {
        VStack(spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update available")
                        .fontWeight(.medium)
                    Text("Installed: \(installed)  →  Latest: \(latest)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.orange)
                    .font(.title2)
            }

            HStack(spacing: 12) {
                Button("Update") {
                    Task { await lib.download() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip") { dismiss() }
                    .controlSize(.large)
            }
        }
    }

    private func downloadingBody(progress: Double) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading VICE core…")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal, 8)

            Button("Cancel") { lib.cancelDownload() }
                .foregroundStyle(.secondary)
        }
    }

    private var installedBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Ready")
                .font(.headline)
            if let version = lib.installedVersion {
                Text("VICE core \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorBody(message: String) -> some View {
        VStack(spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download failed")
                        .fontWeight(.medium)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.title2)
            }

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task { await lib.download() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        switch lib.state {
        case .notInstalled:
            return "The VICE emulation core needs to be downloaded before you can run the emulator."
        case .updateAvailable:
            return "A new version of the VICE emulation core is available."
        case .downloading:
            return "Downloading from GitHub Releases…"
        case .installed(let version):
            return "VICE core \(version) is installed and ready."
        case .error:
            return "Something went wrong. Check your internet connection and try again."
        }
    }
}
