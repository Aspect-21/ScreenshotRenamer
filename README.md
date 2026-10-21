# 📸 ScreenshotRenamer

A lightweight, native macOS menu bar application that automatically monitors your screenshots folder and intelligently renames files based on their visual content using Google Gemini Vision API and on-device Apple Vision AI.

Say goodbye to cluttered folders filled with `CleanShot 2026-04-27 at 16.44.14@2x.png` or `Screen Shot 2026-10-21 at 20.30.00.png`. ScreenshotRenamer instantly transforms them into clean, descriptive filenames like `2026-04-27_prompt-chat-summarizer-instructions.png` or `2026-10-21_github-pull-request-review.png`.

---

## ✨ Features

- **🧠 Multi-Model AI Vision Pipeline**: Uses Google Gemini Vision models to understand screenshot context, UI elements, code snippets, documents, and web pages to generate concise, descriptive filenames.
- **🛡️ Resilient Model Fallback Chain**: Automatically cascades across multiple Gemini models (`gemini-3.1-flash-lite-preview`, `gemini-2.5-flash-lite`, `gemini-2.5-flash`, etc.) with exponential backoff and rate-limit cooldown handling.
- **📴 On-Device Offline Fallback**: If offline or if the API is unavailable, the app falls back to Apple's native Vision framework (`VNRecognizeTextRequest` OCR and `VNClassifyImageRequest`) with natural language title scoring.
- **⚡ Real-Time File System Monitoring**: Combines macOS `DispatchSource` kernel events (`kqueue`) with a background polling timer to reliably catch new screenshots without stalling or missing events.
- **🔒 Safe & Collision-Proof**: Verifies file write stabilization before processing to prevent reading partially written screenshots, and automatically indexes duplicate filenames (`-2`, `-3`).
- **💻 Native macOS Experience**: Sits unobtrusively in your menu bar (`MenuBarExtra`), features instant folder selection, start/pause controls, live rename history, and a modern SwiftUI Settings window.

---

## 🛠️ Architecture & Highlights

```
┌────────────────────────────────────────────────────────┐
│                   ScreenshotRenamer                    │
└────────────────────────────────────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
    [FolderMonitor]             [MenuBar & Settings]
  Hybrid kqueue + Poll          Native SwiftUI (macOS 14+)
             │
             ▼
    [File Stabilization]
   Non-blocking size check
             │
             ▼
     [Analysis Engine]
   ┌──────────────────────────────────────────────────┐
   │ 1. GeminiAnalyzer (Multi-model cascade)          │
   │    gemini-3.1-flash-lite-preview                 │
   │    └── gemini-2.5-flash-lite                     │
   │        └── gemini-2.5-flash                      │
   │            └── gemini-3-flash-preview            │
   │ 2. Fallback: Apple Vision Framework              │
   │    VNRecognizeTextRequest (OCR)                  │
   │    VNClassifyImageRequest (Image Classification) │
   └──────────────────────────────────────────────────┘
             │
             ▼
    [FileRenamer Engine]
  Date prefix + slug sanitization + collision avoidance
```

- **Built with**: Swift 5.9+, SwiftUI, AppKit, Vision framework, DispatchSource, URLSession.
- **Target OS**: macOS 14.0 (Sonoma) or later.
- **Zero Third-Party Dependencies**: Clean SPM package with no external package bloat.

---

## 🚀 Quick Start

### 1. Requirements

- macOS 14.0 (Sonoma) or newer
- Xcode 15+ or Swift 5.9+ command-line tools (`xcode-select --install`)
- A free Google Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey) (optional, but recommended for semantic naming)

### 2. Build and Run

Clone the repository and build the app using the included build script:

```bash
git clone https://github.com/<your-username>/ScreenshotRenamer.git
cd ScreenshotRenamer

# Build and package the .app bundle
./build.sh

# Launch the application
open ScreenshotRenamer.app
```

Alternatively, run directly with Swift Package Manager:

```bash
swift run
```

---

## ⚙️ Configuration

1. **Launch the App**: The camera icon `camera.viewfinder` will appear in your macOS menu bar.
2. **Select Watched Folder**: Click the menu bar icon and select your screenshots directory (e.g., `~/Pictures/Screenshots` or `~/Desktop`).
3. **Set API Key**:
   - Open **Settings…** (`Cmd + ,`) from the menu bar.
   - Enter your Gemini API key in the secure key field.
   - The key is securely stored in your local macOS user defaults and never committed to version control.
4. **Start Monitoring**: Click **Start Monitoring**. The app will automatically watch for new screenshots and rename them as they appear.

---

## 📁 Project Structure

```
ScreenshotRenamer/
├── Package.swift           # Swift Package Manager manifest
├── Info.plist              # macOS application metadata & LSUIElement
├── build.sh                # Build and packaging script
├── Sources/
│   ├── AppMain.swift       # Application entry point & MenuBarExtra setup
│   ├── AppState.swift      # Central state machine & pipeline coordinator
│   ├── FolderMonitor.swift # Hybrid kqueue + polling file system watcher
│   ├── GeminiAnalyzer.swift# Multi-model Gemini Vision API integration
│   ├── ImageAnalyzer.swift # Apple Vision OCR and image classification
│   ├── NameGenerator.swift # Heuristic scoring for Vision-derived titles
│   ├── FileRenamer.swift   # Atomic rename and collision resolution
│   ├── MenuBarView.swift   # Menu bar dropdown UI
│   ├── SettingsView.swift  # Settings and configuration window
│   └── Logger.swift        # Rotating persistent logger
└── README.md
```

---

## 🤝 Contributing & License

Contributions, issues, and feature requests are welcome!
Feel free to fork this project and submit a PR.

Distributed under the [MIT License](LICENSE).
