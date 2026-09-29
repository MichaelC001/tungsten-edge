import Foundation

/// The item provider a folder / shelf popup cell hands to a real file drag.
///
/// Registers the file URL only — the shape a Finder drag has — so the receiver works on the file
/// itself. Never `NSItemProvider(contentsOf:)`: it registers the content type first
/// (`public.zip-archive`, `public.plain-text`, …) with no name, and Finder / mail clients take that
/// data copy and name it after the type ("Zip归档.zip").
enum FileDragItemProvider {
    static func make(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        // Only matters to a receiver that still lands a data copy: the copy keeps the real name.
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
