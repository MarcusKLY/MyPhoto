# MyPhoto 📸

**MyPhoto** is a high-performance macOS culling tool built with **SwiftUI** and **AppKit**. It is designed for photographers who need to quickly screen, flag, and organize massive photo imports (Sony & Fujifilm) before moving them into a professional editor like Adobe Lightroom.

Unlike standard file browsers, MyPhoto understands the relationship between different file formats (RAW + JPEG/HEIF) and groups them into a single, manageable entity.

---

## 🚀 Key Features

* **Draggable Multi-Pane Layout:** A flexible `HSplitView` interface allowing you to resize the grid, high-res preview, and metadata panels independently.
* **Pro RAW Support:** Specialized handling for **Sony (.ARW)** and **Fujifilm (.RAF)** files, including high-speed embedded preview extraction.
* **AppKit-Powered Zoom:** Bridged `NSScrollView` and `NSImageView` via `NSViewRepresentable` to provide native, cursor-targeted pinch-to-zoom and panning.
* **Deep Metadata Engine:** Full EXIF extraction including Aperture, Shutter Speed, ISO, Lens info, and GPS coordinates.
* **Lightroom Integration:** Native Drag-and-Drop support. Drag any thumbnail directly into Lightroom; the app automatically prioritizes the RAW file for the transfer.
* **Culling Workflow:** Integrated flagging system (Keep/Reject) with instant auto-advance navigation upon deletion.

## 🛠 Technical Highlights

* **Concurrency:** Uses `TaskGroup` and `Task.detached` for multi-threaded folder scanning and thumbnail generation.
* **Performance:** Leverages `QuickLookThumbnailing` for glitch-free, hardware-accelerated previews, avoiding common "stride-mismatch" bugs on Apple Silicon.
* **State Management:** Utilizes the modern Swift 6 `@Observable` macro for efficient, reactive UI updates.
* **Memory-Only Settings:** User preferences are held in active memory to keep the system clean and avoid unnecessary disk writes.

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd + O` | Select a new folder to scan |
| `Arrows` | Navigate through photos |
| `Shift + Arrows` | Multi-select photo groups |
| `K` / `X` | Flag as **Keep** or **Reject** |
| `Delete` | Move selected group(s) to Trash |
| `Esc` | Clear selection / Deselect all |

## 📁 Supported File Types

* **RAW:** Sony (`.arw`), Fujifilm (`.raf`)
* **Standard:** `.heif`, `.hif`, `.heic`, `.jpg`, `.jpeg`, `.png`

---

## 💻 Installation & Development

### Requirements
* **macOS 14.0 (Sonoma)** or later.
* **Xcode 15.0+**

### Building from Source
1.  Clone the repository or download the source code.
2.  Open `MyPhoto.xcodeproj` in Xcode.
3.  In **Signing & Capabilities**, select your Team (Personal Apple ID).
4.  Ensure the **App Sandbox** is disabled to allow file system access.
5.  Build and Run (`Cmd + R`).

### Troubleshooting "Unverified Developer"
If sharing the exported `.app` with others, macOS Gatekeeper may block the launch. To bypass this:
1.  Right-click `MyPhoto.app` in the Applications folder and select **Open**.
2.  Click **Open Anyway** in the dialog box.
3.  Alternatively, run `xattr -cr /Applications/MyPhoto.app` in Terminal to clear the quarantine flag.

---

## 📄 License

This project is currently provided without a formal license. For portfolio review purposes only.