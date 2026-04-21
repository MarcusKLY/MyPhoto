import SwiftUI
import AppKit

enum FlagFilter: String, CaseIterable {
    case all = "All"
    case kept = "Kept"
    case rejected = "Rejected"
    case unflagged = "Unflagged"
}

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
    
    @State private var marqueeStart: CGPoint?
    @State private var marqueeEnd: CGPoint = .zero
    @State private var isDraggingCoordinator: FileDragSourceCoordinator?
    @State private var filterText: String = ""
    @State private var flagFilter: FlagFilter = .all
    @State private var showOrganizeAlert = false
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var lastTapWasOnCard = false
    
    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.5), spacing: 16)]
    }
    
    var filteredGroups: [PhotoGroup] {
        var groups = photoManager.photoGroups
        
        // 1. Text Filter
        if !filterText.isEmpty {
            groups = groups.filter { group in
                group.baseName.lowercased().contains(filterText.lowercased())
            }
        }
        
        // 2. Flag Filter
        switch flagFilter {
        case .all: return groups
        case .kept: return groups.filter { $0.isKept }
        case .rejected: return groups.filter { $0.isRejected }
        case .unflagged: return groups.filter { !$0.isKept && !$0.isRejected }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // Left Side: Grid
                ZStack {
                    Color.clear
                    
                    if photoManager.isScanning {
                        ContentUnavailableView("Scanning", systemImage: "magnifyingglass")
                    } else if photoManager.photoGroups.isEmpty {
                        ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle")
                    } else {
                        PhotoGridView(
                            selectedPhotoIDs: $selectedPhotoIDs,
                            lastSelectedIndex: $lastSelectedIndex,
                            lastTapWasOnCard: $lastTapWasOnCard,
                            marqueeStart: $marqueeStart,
                            marqueeEnd: $marqueeEnd,
                            cardFrames: $cardFrames,
                            viewingPhoto: $viewingPhoto,
                            filteredGroups: filteredGroups,
                            gridColumns: gridColumns,
                            thumbnailSize: thumbnailSize,
                            photoManager: photoManager
                        )
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
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search photos...", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    
                    // NEW: Flag Filter UI
                    Picker("Flag Filter", selection: $flagFilter) {
                        Text("All").tag(FlagFilter.all)
                        Text("Kept").tag(FlagFilter.kept)
                        Text("Rejected").tag(FlagFilter.rejected)
                        Text("Unflagged").tag(FlagFilter.unflagged)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // Main toolbar
                HStack(spacing: 20) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Slider(value: $thumbnailSize, in: 100...800).frame(width: 150)
                    Spacer()
                    
                    if !selectedPhotoIDs.isEmpty {
                        Text("\(selectedPhotoIDs.count) Selected").foregroundStyle(.secondary)
                        Button(role: .destructive) { deleteSelectedPhotos() } label: { Label("Trash", systemImage: "trash") }.keyboardShortcut(.delete, modifiers: [])
                    }
                    
                    Divider().frame(height: 20)
                    
                    // RAW Organization Button
                    HStack(spacing: 8) {
                        if photoManager.hasRawOrganizationIssues {
                            Button(action: { showOrganizeAlert = true }) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                            .help("RAW Organization Issues")
                            .popover(isPresented: $showOrganizeAlert) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Organization Issues").font(.headline).bold()
                                    Divider()
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(photoManager.rawOrganizationIssues, id: \.self) { issue in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.orange)
                                                        .frame(width: 20)
                                                    Text(issue).font(.caption)
                                                }
                                            }
                                        }
                                    }
                                    .frame(height: 200)
                                    HStack {
                                        Spacer()
                                        Button("Close") { showOrganizeAlert = false }
                                            .keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding()
                                .frame(width: 350)
                            }
                        }
                        
                        Button(action: { photoManager.organizeRawFilesByExtension() }) {
                            Label("Organize RAWs", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(!photoManager.canOrganizeRaws || !photoManager.hasRawFiles)
                        .help(photoManager.hasRawFiles ? "Organize RAW files into ARW/RAF folders" : "No RAW files to organize")
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
        .onKeyPress(keys: [.leftArrow, .rightArrow, .escape, "x", "X", "z", "Z", "c", "C"] as Set<KeyEquivalent>) { press in
            switch press.key {
            case .leftArrow: moveSelection(offset: -1, extending: press.modifiers.contains(.shift)); return .handled
            case .rightArrow: moveSelection(offset: 1, extending: press.modifiers.contains(.shift)); return .handled
            case .escape: selectedPhotoIDs.removeAll(); return .handled
            case "z", "Z": photoManager.flagSelected(ids: selectedPhotoIDs, keep: false); return .handled
            case "x", "X": photoManager.flagSelected(ids: selectedPhotoIDs, keep: true); return .handled
            case "c", "C": photoManager.unflagSelected(ids: selectedPhotoIDs); return .handled
            default: return .ignored
            }
        }
    }
    
    func initiateDrag(from groups: [PhotoGroup], at index: Int) {
        let selectedGroups = groups.filter { selectedPhotoIDs.contains($0.id) }
        let dragGroups = selectedGroups.isEmpty ? groups : selectedGroups
        
        // For now, basic drag. Real implementation would use AppKit NSDraggingSource
        for group in dragGroups {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(group.rawPreferredURL.path, forType: .fileURL)
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
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
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

// --- DRAG SOURCE COORDINATOR ---
class FileDragSourceCoordinator: NSObject, NSDraggingSource {
    var isDragging = false
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
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
        if selectedIDs.count > 1 {
            VStack(alignment: .leading, spacing: 16) {
                Text("Metadata").font(.title2).bold()
                Text("\(selectedIDs.count) items selected").foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        } else if let id = selectedIDs.first, let group = photoManager.photoGroups.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Metadata").font(.title2).bold()
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
                        if group.rafURL != nil { Label("RAW (.RAF)", systemImage: "doc.text.image") }
                        if group.heifURL != nil { Label("HEIF", systemImage: "photo") }
                        if group.jpgURL != nil { Label("JPEG", systemImage: "photo") }
                        if group.pngURL != nil { Label("PNG", systemImage: "photo") }
                    }
                    Spacer()
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "photo").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("No Photo Selected").font(.headline).foregroundStyle(.secondary)
                    Text("Select a photo to view metadata").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct DetailRow: View { let title: String; let value: String; var body: some View { VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.body) } } }
struct PhotoCardView: View { 
    let group: PhotoGroup
    let size: Double
    
    var body: some View {
        VStack(spacing: 8) {
            if let cgImage = group.thumbnail {
                Image(decorative: cgImage, scale: 1.0).resizable().scaledToFit().frame(height: size * 0.75).cornerRadius(8)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: size * 0.75)
            }
            
            HStack {
                Text(group.baseName).font(.caption).fontWeight(.bold).lineLimit(1)
                Spacer()
                if group.isKept {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                } else if group.isRejected {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(0)
        .background(Color.clear)
        .frame(width: size)
    }
}

struct ShortcutGuideView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts").font(.headline)
                Spacer()
                Button("Close") { isPresented = false }.keyboardShortcut(.cancelAction)
            }
            Divider()
            HStack { Text("Arrows").bold(); Spacer(); Text("Navigate") }
            HStack { Text("Shift + Arrows").bold(); Spacer(); Text("Multi-Select") }
            HStack { Text("Cmd + Click").bold(); Spacer(); Text("Toggle Item") }
            HStack { Text("Shift + Click").bold(); Spacer(); Text("Select Range") }
            HStack { Text("Z").bold(); Spacer(); Text("Reject") }
            HStack { Text("X").bold(); Spacer(); Text("Keep") }
            HStack { Text("C").bold(); Spacer(); Text("Unflag") }
            HStack { Text("ESC").bold(); Spacer(); Text("Deselect All") }
        }
        .padding()
        .frame(width: 320)
    }
}

struct PhotoGridView: View {
    @Binding var selectedPhotoIDs: Set<UUID>
    @Binding var lastSelectedIndex: Int
    @Binding var lastTapWasOnCard: Bool
    @Binding var marqueeStart: CGPoint?
    @Binding var marqueeEnd: CGPoint
    @Binding var cardFrames: [UUID: CGRect]
    @Binding var viewingPhoto: PhotoGroup?
    
    let filteredGroups: [PhotoGroup]
    let gridColumns: [GridItem]
    let thumbnailSize: Double
    let photoManager: PhotoManager
    
    var body: some View {
        ScrollView {
            // FIX 1: ZStack placed inside the ScrollView so the overlay scrolls naturally
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(filteredGroups.enumerated()), id: \.element.id) { index, group in
                        PhotoCardView(group: group, size: thumbnailSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedPhotoIDs.contains(group.id) ? Color.accentColor : Color.clear, lineWidth: 4)
                            )
                            .background(GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        cardFrames[group.id] = geo.frame(in: .named("GridSpace"))
                                    }
                                    .onChange(of: geo.frame(in: .named("GridSpace"))) { _, newFrame in
                                        cardFrames[group.id] = newFrame 
                                    }
                            })
                            .onTapGesture(count: 2) {
                                viewingPhoto = group
                                selectedPhotoIDs = [group.id]
                                lastSelectedIndex = index
                            }
                            .highPriorityGesture(TapGesture(count: 1).onEnded {
                                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                                let isCmd = modifiers.contains(.command)
                                let isShift = modifiers.contains(.shift)
                                
                                if isCmd {
                                    if selectedPhotoIDs.contains(group.id) {
                                        selectedPhotoIDs.remove(group.id)
                                    } else {
                                        selectedPhotoIDs.insert(group.id)
                                    }
                                } else if isShift {
                                    extendSelection(to: group.id, at: index)
                                } else {
                                    selectedPhotoIDs = [group.id]
                                }
                                lastSelectedIndex = index
                            })
                            .onDrag {
                                let dragGroups: [PhotoGroup]
                                
                                // 1. Check if the dragged item is part of the current selection.
                                if selectedPhotoIDs.contains(group.id) {
                                    // Dragging an already selected item pulls the whole selection
                                    dragGroups = photoManager.photoGroups.filter { selectedPhotoIDs.contains($0.id) }
                                } else {
                                    // Dragging an UNSELECTED item should immediately select it
                                    dragGroups = [group]
                                    DispatchQueue.main.async {
                                        selectedPhotoIDs = [group.id]
                                    }
                                }
                                
                                // 2. Return the first item so SwiftUI can create the visual drag "ghost" under your cursor
                                let provider = NSItemProvider(object: dragGroups.first!.rawPreferredURL as NSURL)
                                
                                // 3. ✨ THE MAGIC HACK: Hijack the dedicated macOS Drag Pasteboard
                                // We wait 0.05 seconds so SwiftUI finishes creating the drag session,
                                // then we overwrite the drag clipboard with ALL selected files.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    let dragPasteboard = NSPasteboard(name: .drag)
                                    dragPasteboard.clearContents()
                                    
                                    let urls = dragGroups.map { $0.rawPreferredURL as NSURL }
                                    dragPasteboard.writeObjects(urls)
                                }
                                
                                return provider
                            }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 800, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPhotoIDs.removeAll()
                }
                
                // FIX 2: Marquee visual moved here
                if let start = marqueeStart {
                    let rect = CGRect(
                        x: min(start.x, marqueeEnd.x),
                        y: min(start.y, marqueeEnd.y),
                        width: abs(marqueeEnd.x - start.x),
                        height: abs(marqueeEnd.y - start.y)
                    )
                    
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY) 
                }
            }
        }
        .coordinateSpace(name: "GridSpace")
        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("GridSpace"))
            .onChanged { value in
                if marqueeStart == nil {
                    // FIX 3: If the drag starts ON a photo, completely abort the marquee
                    // This stops the marquee from resetting your selection during drag-and-drop
                    let isHit = cardFrames.values.contains { $0.contains(value.startLocation) }
                    if isHit { return }
                    marqueeStart = value.startLocation
                }
                
                guard marqueeStart != nil else { return } // Keep skipping if we aborted
                marqueeEnd = value.location
                updateMarqueeSelection()
            }
            .onEnded { _ in
                marqueeStart = nil
            }
        )
    }
    
    func updateMarqueeSelection() {
        guard let start = marqueeStart else { return }
        let marqueeRect = CGRect(
            x: min(start.x, marqueeEnd.x),
            y: min(start.y, marqueeEnd.y),
            width: abs(marqueeEnd.x - start.x),
            height: abs(marqueeEnd.y - start.y)
        )
        
        var newSelection: Set<UUID> = []
        for group in filteredGroups {
            if let cardFrame = cardFrames[group.id], marqueeRect.intersects(cardFrame) {
                newSelection.insert(group.id)
            }
        }
        selectedPhotoIDs = newSelection
    }
    
    func extendSelection(to photoID: UUID, at index: Int) {
        let lastIndex = lastSelectedIndex
        let startIndex = min(lastIndex, index)
        let endIndex = max(lastIndex, index)
        
        for i in startIndex...endIndex {
            if i >= 0 && i < filteredGroups.count {
                selectedPhotoIDs.insert(filteredGroups[i].id)
            }
        }
    }
}