import Foundation
import CoreGraphics

struct PhotoGroup: Identifiable, Sendable {
    let id = UUID()
    let baseName: String
    
    var arwURL: URL?
    var rafURL: URL? // NEW: Fuji RAW Support
    var heifURL: URL?
    var jpgURL: URL?
    var pngURL: URL?
    
    var thumbnail: CGImage?
    
    var isRejected: Bool = false
    var isKept: Bool = false
    
    // For fast viewing: Prefers the tiny, pre-baked JPEGs/HEIFs
    var previewURL: URL? {
        return jpgURL ?? heifURL ?? arwURL ?? rafURL ?? pngURL
    }
    
    // NEW FOR LIGHTROOM: Prefers the heavy RAW sensor data for dragging/editing
    var rawPreferredURL: URL {
        return arwURL ?? rafURL ?? heifURL ?? jpgURL ?? pngURL ?? URL(fileURLWithPath: "/")
    }
}
