/// Pasteboard marker types used to identify writes produced by DevClip itself.
public enum PasteboardInternalTypes {
    public static let transactionID = "devclip.internal.transaction-id"
    public static let contentHash = "devclip.internal.content-hash"
    public static let markerVersion = "devclip.internal.marker-version"
    public static let thumbnailPNG = "devclip.internal.thumbnail.png"

    public static func isInternal(_ pasteboardType: String) -> Bool {
        pasteboardType.hasPrefix("devclip.internal.")
    }
}
