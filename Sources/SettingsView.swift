import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Image(systemName: "camera.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.blue.gradient)
                VStack(alignment: .leading) {
                    Text("Screenshot Renamer")
                        .font(.title2.bold())
                    Text("Automatically rename screenshots based on their content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [.blue.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Folder Selection
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Watched Folder", systemImage: "folder.fill")
                                .font(.headline)

                            HStack {
                                if appState.watchedFolderPath.isEmpty {
                                    Text("No folder selected")
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                    Text(abbreviatePath(appState.watchedFolderPath))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button("Choose…") {
                                    selectFolder()
                                }
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(4)
                    }

                    // Gemini API Key
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Gemini API Key", systemImage: "key.fill")
                                .font(.headline)

                            @Bindable var state = appState
                            HStack {
                                SecureField("Paste your Gemini API key…", text: $state.geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)

                                if !appState.geminiAPIKey.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text("Get a free key at aistudio.google.com/apikey")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }

                    // Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Monitoring", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)

                            HStack {
                                Circle()
                                    .fill(appState.isActive ? .green : .gray)
                                    .frame(width: 10, height: 10)
                                Text(appState.isActive ? "Active" : "Paused")
                                    .foregroundStyle(appState.isActive ? .primary : .secondary)

                                Spacer()

                                Button {
                                    appState.toggleMonitoring()
                                } label: {
                                    Text(appState.isActive ? "Pause" : "Start")
                                        .frame(width: 60)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(appState.isActive ? .orange : .green)
                                .disabled(appState.watchedFolderPath.isEmpty)
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(appState.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }

                    // Rename History
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Rename History", systemImage: "clock.arrow.circlepath")
                                    .font(.headline)
                                Spacer()
                                if !appState.renameHistory.isEmpty {
                                    Text("\(appState.renameHistory.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if appState.renameHistory.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "tray")
                                            .font(.largeTitle)
                                            .foregroundStyle(.secondary)
                                        Text("No screenshots renamed yet")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 4) {
                                    ForEach(appState.renameHistory.prefix(20)) { record in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(record.newName)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                HStack(spacing: 4) {
                                                    Text("←")
                                                        .foregroundStyle(.secondary)
                                                    Text(record.originalName)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                .font(.caption2)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(record.date, style: .relative)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                Text(record.modelUsed)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(.blue.opacity(0.7))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(.blue.opacity(0.08))
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                        }
                                        .padding(8)
                                        .background(.background)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }

                    // How It Works
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("How It Works", systemImage: "questionmark.circle")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 10) {
                                howItWorksRow(
                                    icon: "eye",
                                    color: .blue,
                                    title: "Monitors",
                                    desc: "Watches your folder for new screenshot files"
                                )
                                howItWorksRow(
                                    icon: "brain.head.profile",
                                    color: .purple,
                                    title: "Analyzes",
                                    desc: "Sends to Gemini AI with smart model fallback — cascades through 6 models if one is rate-limited"
                                )
                                howItWorksRow(
                                    icon: "arrow.triangle.branch",
                                    color: .orange,
                                    title: "Fallback",
                                    desc: "If all Gemini models are unavailable, falls back to on-device Vision AI"
                                )
                                howItWorksRow(
                                    icon: "pencil",
                                    color: .green,
                                    title: "Renames",
                                    desc: "Creates a descriptive filename from the content"
                                )
                            }
                            .padding(10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(4)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Components

    private func howItWorksRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func selectFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder to watch for new screenshots"
        panel.prompt = "Watch This Folder"
        panel.level = .floating

        if panel.runModal() == .OK, let url = panel.url {
            appState.watchedFolderPath = url.path
            if appState.isActive {
                appState.startMonitoring()
            }
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
