import AppKit
import SceneKit

/// Self-check screenshots without Screen Recording permission: `--snapshot <file.png>` renders
/// the settings window in-process, composites SceneKit views (which cacheDisplay leaves blank), then quits.
@MainActor enum Snapshot {
    static var target: URL? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[i + 1])
    }
    static func capture(_ window: NSWindow?, to url: URL) {
        guard let root = window?.contentView, let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
        let image = NSImage(size: root.bounds.size); image.addRepresentation(rep)
        let out = NSImage(size: root.bounds.size)
        out.lockFocus()
        image.draw(in: root.bounds)
        for scn in scenes(in: root) where !scn.isHidden {
            var r = scn.convert(scn.bounds, to: root)
            if root.isFlipped { r.origin.y = root.bounds.height - r.maxY }
            scn.snapshot().draw(in: r)
        }
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
    private static func scenes(in view: NSView) -> [SCNView] {
        (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(scenes)
    }
}
