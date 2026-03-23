import SwiftUI

struct ContentView: View {
    @State private var photoManager = PhotoManager()
    @State private var thumbnailSize: Double = 300
    
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var lastSelectedIndex: Int = 0
    @State private var viewingPhoto: PhotoGroup?
    
    @State private var isSplitView = false
    @State private var showInfoPanel = false
    @State private var showShortcuts = false
    @State private var showSettings = false
    
    @State private var showFileDetails = true
    @State private var showCameraDetails = true
    @State private var showExposureDetails = true
    @State private var showAdvancedEXIF = false
    @State private var showGPS = true
    
    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.5), spacing: 16)]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Left Side: Grid
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture { selectedPhotoIDs.removeAll() }
                    
                    if photoManager.isScanning {
                        ContentUnavailableView("Scanning", systemImage: "magnifyingglass")
                    } else if photoManager.photoGroups.isEmpty {
                        ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(Array(photoManager.photoGroups.enumerated()), id: \.element.id) { index, group in
                                    PhotoCardView(group: group, size: thumbnailSize)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedPhotoIDs.contains(group.id) ? Color.accentColor : Color.clear, lineWidth: 4))
                                        .highPriorityGesture(TapGesture(count: 1).onEnded {
                                            toggleSelection(for: group.id, at: index)
                                        })
                                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                                            viewingPhoto = group
                                            selectedPhotoIDs = [group.id]
                                            lastSelectedIndex = index
                                        })
                                        // NATIVE LIGHTROOM INTEGRATION: Click and drag!
                                        .draggable(group.rawPreferredURL)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(minWidth: 300, maxHeight: .infinity)
                
                // Middle: Side-by-Side Live Preview
                if isSplitView {
                    if let firstSelectedID = selectedPhotoIDs.first,
                       let group = photoManager.photoGroups.first(where: { $0.id == firstSelectedID }) {
                        LiveZoomableView(group: group, photoManager: photoManager)
                            .frame(minWidth: 400, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("No Photo Selected", systemImage: "cursorarrow.click.2")
                            .frame(minWidth: 400, maxHeight: .infinity)
                    }
                }
                
                // Right: Info Panel
                if showInfoPanel {
                    InfoPanelView(
                        photoManager: photoManager,
                        selectedIDs: selectedPhotoIDs,
                        showFileDetails: showFileDetails,
                        showCameraDetails: showCameraDetails,
                        showExposureDetails: showExposureDetails,
                        showAdvancedEXIF: showAdvancedEXIF,
                        showGPS: showGPS
                    )
                    .frame(minWidth: 250, maxWidth: 350, maxHeight: .infinity)
                }
            }
            
            Divider()
            
            // Bottom Toolbar
            HStack(spacing: 20) {
                Image(systemName: "photo").foregroundStyle(.secondary)
                Slider(value: $thumbnailSize, in: 100...800).frame(width: 150)
                Spacer()
                
                if !selectedPhotoIDs.isEmpty {
                    Text("\(selectedPhotoIDs.count) Selected").foregroundStyle(.secondary)
                    Button(role: .destructive) { deleteSelectedPhotos() } label: { Label("Trash", systemImage: "trash") }.keyboardShortcut(.delete, modifiers: [])
                }
                
                Divider().frame(height: 20)
                Button { isSplitView.toggle() } label: { Image(systemName: isSplitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1") }.help("Side-by-Side View")
                Button { showInfoPanel.toggle() } label: { Image(systemName: showInfoPanel ? "info.circle.fill" : "info.circle") }.help("Info Panel")
                Button { showShortcuts.toggle() } label: { Image(systemName: "keyboard") }.popover(isPresented: $showShortcuts) { ShortcutGuideView(isPresented: $showShortcuts) }
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .popover(isPresented: $showSettings) {
                        SettingsView(showFileDetails: $showFileDetails, showCameraDetails: $showCameraDetails, showExposureDetails: $showExposureDetails, showAdvancedEXIF: $showAdvancedEXIF, showGPS: $showGPS)
                    }
                Button("Select Folder") { selectFolder() }.keyboardShortcut("o", modifiers: .command)
            }
            .padding()
            .background(Material.bar)
        }
        .frame(minWidth: 1000, minHeight: 700)
        
        // Full Screen Double-Click Sheet
        .sheet(item: $viewingPhoto) { group in
            VStack(spacing: 0) {
                LiveZoomableView(group: group, photoManager: photoManager)
                HStack {
                    Spacer()
                    Button("Close View") { viewingPhoto = nil }
                        .keyboardShortcut(.defaultAction)
                        .padding()
                }
                .background(Material.bar)
            }
            .frame(minWidth: 900, minHeight: 700)
        }
        
        // Keyboard Setup
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .escape, "x", "X", "k", "K", "u", "U"] as Set<KeyEquivalent>) { press in
            switch press.key {
            case .leftArrow: moveSelection(offset: -1, extending: press.modifiers.contains(.shift)); return .handled
            case .rightArrow: moveSelection(offset: 1, extending: press.modifiers.contains(.shift)); return .handled
            case .escape: selectedPhotoIDs.removeAll(); return .handled
            case "x", "X": photoManager.flagSelected(ids: selectedPhotoIDs, keep: false); return .handled
            case "k", "K": photoManager.flagSelected(ids: selectedPhotoIDs, keep: true); return .handled
            case "u", "U": photoManager.unflagSelected(ids: selectedPhotoIDs); return .handled
            default: return .ignored
            }
        }
    }
    
    func moveSelection(offset: Int, extending: Bool) {
        guard !photoManager.photoGroups.isEmpty else { return }
        let newIndex = lastSelectedIndex + offset
        if newIndex >= 0 && newIndex < photoManager.photoGroups.count {
            let newID = photoManager.photoGroups[newIndex].id
            if extending { selectedPhotoIDs.insert(newID) } else { selectedPhotoIDs = [newID] }
            lastSelectedIndex = newIndex
        }
    }
    
    func toggleSelection(for id: UUID, at index: Int) {
        if selectedPhotoIDs.contains(id) { selectedPhotoIDs.remove(id) } else { selectedPhotoIDs = [id] }
        lastSelectedIndex = index
    }
    
    func deleteSelectedPhotos() {
        guard !selectedPhotoIDs.isEmpty else { return }
        for id in selectedPhotoIDs { photoManager.trashGroup(withID: id) }
        selectedPhotoIDs.removeAll()
        
        if !photoManager.photoGroups.isEmpty {
            lastSelectedIndex = min(lastSelectedIndex, photoManager.photoGroups.count - 1)
            selectedPhotoIDs = [photoManager.photoGroups[lastSelectedIndex].id]
        } else {
            lastSelectedIndex = 0
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            photoManager.scanDirectory(at: url)
            selectedPhotoIDs.removeAll(); lastSelectedIndex = 0
        }
    }
}

// --- NATIVE MAC IMAGE VIEWER ---
struct MacZoomableView: NSViewRepresentable {
    var image: NSImage

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1.0
        scrollView.maxMagnification = 5.0
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = scrollView.bounds
        
        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let imageView = nsView.documentView as? NSImageView {
            imageView.image = image
        }
    }
}

struct LiveZoomableView: View {
    let group: PhotoGroup
    let photoManager: PhotoManager
    @State private var highResImage: NSImage?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let nsImage = highResImage {
                MacZoomableView(image: nsImage)
            } else {
                ProgressView("Loading...").controlSize(.large)
            }
            
            VStack {
                HStack(spacing: 12) {
                    Text(group.baseName).font(.system(size: 14, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 8).background(Material.ultraThin).cornerRadius(8).shadow(radius: 2)
                    if group.isKept { Text("KEEP").font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 8).background(Color.green.opacity(0.8)).cornerRadius(8) }
                    if group.isRejected { Text("REJECT").font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).padding(.vertical, 8).background(Color.red.opacity(0.8)).cornerRadius(8) }
                    Spacer()
                }
                .padding(.top, 24).padding(.leading, 24)
                Spacer()
            }
        }
        // DRAG FROM PREVIEW VIEW TOO
        .draggable(group.rawPreferredURL)
        .task(id: group.id) {
            highResImage = nil
            let targetURL = group.previewURL
            if let url = targetURL {
                Task.detached {
                    let image = photoManager.extractHighRes(for: url)
                    await MainActor.run { self.highResImage = image }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var showFileDetails: Bool; @Binding var showCameraDetails: Bool; @Binding var showExposureDetails: Bool; @Binding var showAdvancedEXIF: Bool; @Binding var showGPS: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Metadata Preferences").font(.title2).bold()
            Form {
                Section(header: Text("File Information").bold()) { Toggle("Dimensions, File Size & Color", isOn: $showFileDetails) }
                Section(header: Text("Hardware").bold()) { Toggle("Camera Make, Model & Lens", isOn: $showCameraDetails) }
                Section(header: Text("Exposure").bold()) { Toggle("Aperture, Shutter Speed & ISO", isOn: $showExposureDetails) }
                Section(header: Text("Advanced EXIF").bold()) { Toggle("Exposure Bias, Metering, Flash & White Balance", isOn: $showAdvancedEXIF) }
                Section(header: Text("Location").bold()) { Toggle("GPS Coordinates & Altitude", isOn: $showGPS) }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding().frame(width: 350, height: 400)
    }
}

struct InfoPanelView: View {
    let photoManager: PhotoManager; let selectedIDs: Set<UUID>
    var showFileDetails: Bool; var showCameraDetails: Bool; var showExposureDetails: Bool; var showAdvancedEXIF: Bool; var showGPS: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Metadata").font(.title2).bold()
                if selectedIDs.count > 1 { Text("\(selectedIDs.count) items selected") } else if let id = selectedIDs.first, let group = photoManager.photoGroups.first(where: { $0.id == id }) {
                    let meta = photoManager.getMetadata(for: group)
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(title: "Filename", value: group.baseName)
                        if let date = meta["Date"] { DetailRow(title: "Date Taken", value: date) }
                        Divider()
                        if showFileDetails { if let dim = meta["Dimensions"] { DetailRow(title: "Dimensions", value: dim) }; if let size = meta["File Size"] { DetailRow(title: "File Size", value: size) }; if let cs = meta["Color Space"] { DetailRow(title: "Color Space", value: cs) }; Divider() }
                        if showCameraDetails { if let make = meta["Make"] { DetailRow(title: "Camera Make", value: make) }; if let model = meta["Camera"] { DetailRow(title: "Camera Model", value: model) }; if let lens = meta["Lens"] { DetailRow(title: "Lens", value: lens) }; if let focal = meta["Focal Length"] { DetailRow(title: "Focal Length", value: focal) }; Divider() }
                        if showExposureDetails { if let aperture = meta["Aperture"] { DetailRow(title: "Aperture", value: aperture) }; if let shutter = meta["Shutter Speed"] { DetailRow(title: "Shutter Speed", value: shutter) }; if let iso = meta["ISO"] { DetailRow(title: "ISO", value: iso) }; Divider() }
                        if showAdvancedEXIF { if let bias = meta["Exposure Bias"] { DetailRow(title: "Exposure Bias", value: bias) }; if let meter = meta["Metering"] { DetailRow(title: "Metering Mode", value: meter) }; if let wb = meta["White Balance"] { DetailRow(title: "White Balance", value: wb) }; if let flash = meta["Flash"] { DetailRow(title: "Flash", value: flash) }; Divider() }
                        if showGPS { if let gps = meta["GPS"] { DetailRow(title: "GPS", value: gps) }; if let alt = meta["Altitude"] { DetailRow(title: "Altitude", value: alt) }; if meta["GPS"] != nil { Divider() } }
                        Text("Linked Files:").font(.caption).foregroundStyle(.secondary)
                        if group.arwURL != nil { Label("RAW (.ARW)", systemImage: "doc.text.image") }
                        if group.rafURL != nil { Label("RAW (.RAF)", systemImage: "doc.text.image") } // FUJI IN INFO PANEL
                        if group.heifURL != nil { Label("HEIF", systemImage: "photo") }
                        if group.jpgURL != nil { Label("JPEG", systemImage: "photo") }
                    }
                } else { Text("No photo selected.").foregroundStyle(.secondary) }
                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct DetailRow: View { let title: String; let value: String; var body: some View { VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.body) } } }
struct PhotoCardView: View { let group: PhotoGroup; let size: Double; var body: some View { VStack(spacing: 8) { if let cgImage = group.thumbnail { Image(decorative: cgImage, scale: 1.0).resizable().scaledToFit().frame(height: size * 0.75).cornerRadius(8) } else { Rectangle().fill(Color.gray.opacity(0.3)).frame(height: size * 0.75) }; HStack { Text(group.baseName).font(.caption).fontWeight(.bold).lineLimit(1); Spacer(); if group.isKept { Circle().fill(Color.green).frame(width: 10, height: 10) } else if group.isRejected { Circle().fill(Color.red).frame(width: 10, height: 10) } }.padding(.horizontal, 4) }.padding(0).background(Color.clear).frame(width: size) } }
struct ShortcutGuideView: View { @Binding var isPresented: Bool; var body: some View { VStack(alignment: .leading, spacing: 12) { HStack { Text("Shortcuts").font(.headline); Spacer(); Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction) }; Divider(); HStack { Text("Arrows").bold(); Spacer(); Text("Navigate") }; HStack { Text("Shift + Arrows").bold(); Spacer(); Text("Multi-Select") }; HStack { Text("X / K").bold(); Spacer(); Text("Reject / Keep") }; HStack { Text("ESC").bold(); Spacer(); Text("Deselect All") } }.padding().frame(width: 250) } }
