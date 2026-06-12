@preconcurrency import AppKit
import Foundation

public protocol ImageThumbnailGenerating: Sendable {
    func thumbnailPNGData(from data: Data, maxPixel: CGFloat) async throws -> Data?
}

public struct AppKitImageThumbnailGenerator: ImageThumbnailGenerating {
    public init() {}

    public func thumbnailPNGData(from data: Data, maxPixel: CGFloat = 256) async throws -> Data? {
        await Task.detached(priority: .utility) {
            guard let image = NSImage(data: data) else {
                return nil
            }

            let sourceSize = image.size
            guard sourceSize.width > 0, sourceSize.height > 0 else {
                return nil
            }

            let scale = min(maxPixel / sourceSize.width, maxPixel / sourceSize.height, 1)
            let targetSize = NSSize(
                width: max(1, floor(sourceSize.width * scale)),
                height: max(1, floor(sourceSize.height * scale))
            )

            let thumbnail = NSImage(size: targetSize)
            thumbnail.lockFocus()
            defer { thumbnail.unlockFocus() }

            image.draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .copy,
                fraction: 1
            )

            guard
                let tiffData = thumbnail.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData)
            else {
                return nil
            }

            return bitmap.representation(using: .png, properties: [:])
        }.value
    }
}
