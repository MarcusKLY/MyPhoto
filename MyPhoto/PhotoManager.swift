import Foundation
import CoreGraphics
import ImageIO
import AppKit
import SwiftUI
import CoreImage
import QuickLookThumbnailing // NEW: Apple's native Finder thumbnail engine

@Observable
class PhotoManager {
    var photoGroups: [PhotoGroup] = []
    var isScanning = false
    
    @MainActor
    func scanDirectory(at folderURL: URL) {
        isScanning = true
        photoGroups.removeAll()
        Task {
            do {
                self.photoGroups = try await buildPhotoGroups(at: folderURL)
                self.isScanning = false
            } catch {
                print("Scanning failed: \(error.localizedDescription)")
                self.isScanning = false
            }
        }
    }
    
    nonisolated func extractHighRes(for url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        
        if ext == "arw" || ext == "raf" {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 4000
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        } else {
            return NSImage(contentsOf: url)
        }
    }
    
    nonisolated private func buildPhotoGroups(at folderURL: URL) async throws -> [PhotoGroup] {
        let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        let allowedExts = ["arw", "raf", "heif", "hif", "heic", "jpg", "jpeg", "png"]
        var groupedMap: [String: PhotoGroup] = [:]
        
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExts.contains(ext) else { continue }
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            if groupedMap[baseName] == nil { groupedMap[baseName] = PhotoGroup(baseName: baseName) }
            switch ext {
            case "arw": groupedMap[baseName]?.arwURL = fileURL
            case "raf": groupedMap[baseName]?.rafURL = fileURL
            case "heif", "hif", "heic": groupedMap[baseName]?.heifURL = fileURL
            case "jpg", "jpeg": groupedMap[baseName]?.jpgURL = fileURL
            case "png": groupedMap[baseName]?.pngURL = fileURL
            default: break
            }
        }
        
        var sortedGroups = groupedMap.values.sorted { $0.baseName < $1.baseName }
        
        // --- NEW: HIGH-SPEED CONCURRENT QUICKLOOK EXTRACTION ---
        await withTaskGroup(of: (Int, CGImage?, Double?).self) { groupTask in
            for i in 0..<sortedGroups.count {
                let group = sortedGroups[i]
                
                // Bypass Swift 6 computed property warning
                let targetURL = group.jpgURL ?? group.heifURL ?? group.arwURL ?? group.rafURL ?? group.pngURL
                
                if let url = targetURL {
                    groupTask.addTask {
                        let thumb = await self.extractThumbnail(for: url)
                        let score = thumb.flatMap { self.computeFocusScore(for: $0) }
                        return (i, thumb, score)
                    }
                }
            }
            
            // Collect the extracted thumbnails as they finish
            for await (index, thumbnail, score) in groupTask {
                sortedGroups[index].thumbnail = thumbnail
                sortedGroups[index].focusScore = score
            }
        }
        
        return sortedGroups
    }
    
    // --- NEW: SAFE FINDER ENGINE (Fixes Fuji Stride Bug) ---
    nonisolated private func extractThumbnail(for url: URL) async -> CGImage? {
        let size = CGSize(width: 800, height: 800) // Crisp size for grid
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
        
        do {
            // Ask macOS to generate the thumbnail safely
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.cgImage
        } catch {
            // Fallback to ImageIO if QuickLook times out
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return cgImage
        }
    }
    
    nonisolated private func computeFocusScore(for image: CGImage) -> Double? {
        let context = CIContext(options: nil)
        let ciImage = CIImage(cgImage: image)
        guard let edgeFilter = CIFilter(name: "CIEdges"),
              let avgFilter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }
        
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(2.0, forKey: kCIInputIntensityKey)
        guard let edgedImage = edgeFilter.outputImage else {
            return nil
        }
        
        let extent = edgedImage.extent
        avgFilter.setValue(edgedImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = avgFilter.outputImage else {
            return nil
        }
        
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let average = (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3.0 * 255.0)
        return average
    }
    
    nonisolated func getMetadata(for group: PhotoGroup) -> [String: String] {
        let targetURL = group.jpgURL ?? group.heifURL ?? group.arwURL ?? group.rafURL ?? group.pngURL
        guard let url = targetURL else { return [:] }
        
        var results: [String: String] = [:]
        
        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path), let fileSize = attr[FileAttributeKey.size] as? UInt64 {
            results["File Size"] = String(format: "%.1f MB", Double(fileSize) / 1_048_576.0)
        }
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return results
        }
        
        if let width = metadata[kCGImagePropertyPixelWidth as String], let height = metadata[kCGImagePropertyPixelHeight as String] {
            results["Dimensions"] = "\(width) x \(height)"
        }
        if let colorModel = metadata[kCGImagePropertyColorModel as String] {
            results["Color Space"] = "\(colorModel)"
        }
        
        if let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake as String] { results["Make"] = "\(make)" }
            if let model = tiff[kCGImagePropertyTIFFModel as String] { results["Camera"] = "\(model)" }
            if let software = tiff[kCGImagePropertyTIFFSoftware as String] { results["Software"] = "\(software)" }
            if let dateTime = tiff[kCGImagePropertyTIFFDateTime as String] { results["Date"] = "\(dateTime)" }
        }
        
        if let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let lens = exif[kCGImagePropertyExifLensModel as String] { results["Lens"] = "\(lens)" }
            if let focal = exif[kCGImagePropertyExifFocalLength as String] { results["Focal Length"] = "\(focal)mm" }
            if let focal35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] { results["35mm Equivalent"] = "\(focal35)mm" }
            
            if let fNumber = exif[kCGImagePropertyExifFNumber as String] { results["Aperture"] = "f/\(fNumber)" }
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] {
                if let expDouble = exposure as? Double, expDouble < 1.0 {
                    results["Shutter Speed"] = "1/\(Int(1.0 / expDouble))s"
                } else {
                    results["Shutter Speed"] = "\(exposure)s"
                }
            }
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Any], let iso = isoArray.first { results["ISO"] = "\(iso)" }
            if let bias = exif[kCGImagePropertyExifExposureBiasValue as String] { results["Exposure Bias"] = "\(bias) EV" }
            if let metering = exif[kCGImagePropertyExifMeteringMode as String] {
                let modes = [1: "Average", 2: "Center-Weighted", 3: "Spot", 4: "Multi-Spot", 5: "Pattern"]
                results["Metering"] = modes[metering as? Int ?? 0] ?? "Unknown (\(metering))"
            }
            if let flash = exif[kCGImagePropertyExifFlash as String] as? Int {
                results["Flash"] = (flash % 2 == 1) ? "Fired" : "Did Not Fire"
            }
            if let wb = exif[kCGImagePropertyExifWhiteBalance as String] as? Int {
                results["White Balance"] = (wb == 0) ? "Auto" : "Manual"
            }
        }
        
        if let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String], let latRef = gps[kCGImagePropertyGPSLatitudeRef as String],
               let lon = gps[kCGImagePropertyGPSLongitude as String], let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] {
                results["GPS"] = "\(lat)°\(latRef), \(lon)°\(lonRef)"
            }
            if let alt = gps[kCGImagePropertyGPSAltitude as String] {
                results["Altitude"] = "\(alt)m"
            }
        }
        return results
    }
    
    @MainActor func flagSelected(ids: Set<UUID>, keep: Bool) {
        for id in ids {
            guard let index = photoGroups.firstIndex(where: { $0.id == id }) else { continue }
            if keep { photoGroups[index].isKept = true; photoGroups[index].isRejected = false }
            else { photoGroups[index].isRejected = true; photoGroups[index].isKept = false }
        }
    }
    
    @MainActor func unflagSelected(ids: Set<UUID>) {
        for id in ids {
            guard let index = photoGroups.firstIndex(where: { $0.id == id }) else { continue }
            photoGroups[index].isKept = false; photoGroups[index].isRejected = false
        }
    }
    
    @MainActor func toggleFlagSelected(ids: Set<UUID>) {
        for id in ids {
            guard let index = photoGroups.firstIndex(where: { $0.id == id }) else { continue }
            if photoGroups[index].isKept { photoGroups[index].isKept = false }
            else if photoGroups[index].isRejected { photoGroups[index].isRejected = false }
            else { photoGroups[index].isKept = true }
        }
    }
    
    var hasRawFiles: Bool {
        photoGroups.contains { $0.arwURL != nil || $0.rafURL != nil }
    }
    
    var rawOrganizationIssues: [String] {
        var issues: [String] = []
        for group in photoGroups {
            let raws = [group.arwURL, group.rafURL].compactMap { $0 }
            let hasPreview = group.heifURL != nil || group.jpgURL != nil || group.pngURL != nil
            if hasPreview && raws.isEmpty {
                issues.append("Missing RAW pair for \(group.baseName)")
            }
        }
        return issues
    }
    
    var hasRawOrganizationIssues: Bool {
        !rawOrganizationIssues.isEmpty
    }
    
    var canOrganizeRaws: Bool {
        !rawFilesOutsideExpectedFolders().isEmpty
    }
    
    @MainActor
    func organizeRawFilesByExtension() {
        guard !photoGroups.isEmpty else { return }
        let fileManager = FileManager.default
        var movedCount = 0
        
        for group in photoGroups {
            for rawURL in [group.arwURL, group.rafURL].compactMap({ $0 }) {
                let source = rawURL.standardizedFileURL
                let ext = source.pathExtension.lowercased()
                guard ["arw", "raf"].contains(ext) else { continue }
                
                let root = source.deletingLastPathComponent().deletingLastPathComponent()
                let folderName = ext.uppercased()
                let targetDirectory = root.appendingPathComponent(folderName, isDirectory: true)
                
                do {
                    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("Failed to create folder: \(error.localizedDescription)")
                    continue
                }
                
                let destination = targetDirectory.appendingPathComponent(source.lastPathComponent)
                guard destination.path != source.path else { continue }
                
                do {
                    try fileManager.moveItem(at: source, to: destination)
                    movedCount += 1
                } catch {
                    print("Failed to move file: \(error.localizedDescription)")
                }
            }
        }
        
        if movedCount > 0 {
            if let first = photoGroups.first, let url = first.arwURL?.deletingLastPathComponent().deletingLastPathComponent() {
                scanDirectory(at: url)
            }
        }
    }
    
    private func rawFilesOutsideExpectedFolders() -> [URL] {
        var rawsOutside: [URL] = []
        for group in photoGroups {
            for rawURL in [group.arwURL, group.rafURL].compactMap({ $0 }) {
                let source = rawURL.standardizedFileURL
                let ext = source.pathExtension.lowercased()
                guard ["arw", "raf"].contains(ext) else { continue }
                
                let folderName = ext.uppercased()
                let parentPath = source.deletingLastPathComponent().lastPathComponent
                if parentPath.uppercased() != folderName {
                    rawsOutside.append(rawURL)
                }
            }
        }
        return rawsOutside
    }
    
    @MainActor func trashGroup(withID id: UUID) {
        guard let index = photoGroups.firstIndex(where: { $0.id == id }) else { return }
        let group = photoGroups.remove(at: index)
        
        let urlsToTrash = [group.arwURL, group.rafURL, group.heifURL, group.jpgURL, group.pngURL].compactMap { $0 }
        guard !urlsToTrash.isEmpty else { return }
        
        Task.detached {
            NSWorkspace.shared.recycle(urlsToTrash) { _, _ in }
        }
    }
}
