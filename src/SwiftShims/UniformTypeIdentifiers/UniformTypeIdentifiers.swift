// File types, as the open and save panels and the bug report's attachments use them. A small table of the types the
// app names, each with its parents, its extensions and its MIME type.
import Foundation

public struct UTType: Hashable, Sendable {
    public let identifier: String
    public var filenameExtension: String? { extensions.first }
    let extensions: [String]
    let parents: [String]
    public let preferredMIMEType: String?

    public init(identifier: String, ext: String? = nil) {
        if let k = UTType.known.first(where: { $0.identifier == identifier }) { self = k; return }
        self.identifier = identifier; extensions = ext.map { [$0] } ?? []; parents = ["public.data"]; preferredMIMEType = nil
    }
    init(_ id: String, _ exts: [String], _ parents: [String], _ mime: String?) {
        identifier = id; extensions = exts; self.parents = parents; preferredMIMEType = mime
    }
    public init?(_ identifier: String) { self.init(identifier: identifier) }
    public init?(filenameExtension e: String) {
        let e = e.lowercased()
        guard !e.isEmpty else { return nil }
        if let k = UTType.known.first(where: { $0.extensions.contains(e) }) { self = k; return }
        // Unknown: a dynamic type, as on the Mac, that is only data.
        identifier = "dyn.\(e)"; extensions = [e]; parents = ["public.data"]; preferredMIMEType = nil
    }
    public init(exportedAs id: String, conformingTo parent: UTType? = nil) {
        identifier = id; extensions = []; parents = [parent?.identifier ?? "public.data"]; preferredMIMEType = nil
    }
    public static func exportedType(_ id: String, ext: String, conformingTo parent: UTType = .json) -> UTType {
        UTType(id, [ext], [parent.identifier], parent.preferredMIMEType)
    }

    public var supertypes: Set<UTType> {
        var out = Set<UTType>(), todo = parents
        while let p = todo.popLast() {
            let t = UTType(identifier: p)
            if out.insert(t).inserted { todo += t.parents }
        }
        return out
    }
    public func conforms(to other: UTType) -> Bool { other.identifier == identifier || supertypes.contains { $0.identifier == other.identifier } }
    public static func == (a: UTType, b: UTType) -> Bool { a.identifier == b.identifier }
    public func hash(into h: inout Hasher) { h.combine(identifier) }

    static let known: [UTType] = [
        UTType("public.item", [], [], nil),
        UTType("public.data", [], ["public.item"], "application/octet-stream"),
        UTType("public.content", [], [], nil),
        UTType("public.text", [], ["public.data", "public.content"], "text/plain"),
        UTType("public.plain-text", ["txt", "text"], ["public.text"], "text/plain"),
        UTType("public.json", ["json"], ["public.text"], "application/json"),
        UTType("public.image", [], ["public.data", "public.content"], nil),
        UTType("public.png", ["png"], ["public.image"], "image/png"),
        UTType("public.jpeg", ["jpg", "jpeg", "jpe"], ["public.image"], "image/jpeg"),
        UTType("public.heic", ["heic"], ["public.image"], "image/heic"),
        UTType("public.heif", ["heif"], ["public.image"], "image/heif"),
        UTType("com.compuserve.gif", ["gif"], ["public.image"], "image/gif"),
        UTType("public.tiff", ["tif", "tiff"], ["public.image"], "image/tiff"),
        UTType("com.microsoft.bmp", ["bmp"], ["public.image"], "image/bmp"),
        UTType("org.webmproject.webp", ["webp"], ["public.image"], "image/webp"),
        UTType("public.audiovisual-content", [], ["public.data", "public.content"], nil),
        UTType("public.movie", [], ["public.audiovisual-content"], nil),
        UTType("public.mpeg-4", ["mp4", "m4v"], ["public.movie"], "video/mp4"),
        UTType("com.apple.quicktime-movie", ["mov", "qt"], ["public.movie"], "video/quicktime"),
        UTType("public.avi", ["avi"], ["public.movie"], "video/avi"),
        UTType("org.webmproject.webm", ["webm"], ["public.movie"], "video/webm"),
        UTType("com.microsoft.windows-media-wmv", ["wmv"], ["public.movie"], "video/x-ms-wmv"),
    ]
    public static let item = UTType(identifier: "public.item")
    public static let data = UTType(identifier: "public.data")
    public static let content = UTType(identifier: "public.content")
    public static let text = UTType(identifier: "public.text")
    public static let plainText = UTType(identifier: "public.plain-text")
    public static let json = UTType(identifier: "public.json")
    public static let image = UTType(identifier: "public.image")
    public static let png = UTType(identifier: "public.png")
    public static let jpeg = UTType(identifier: "public.jpeg")
    public static let heic = UTType(identifier: "public.heic")
    public static let gif = UTType(identifier: "com.compuserve.gif")
    public static let tiff = UTType(identifier: "public.tiff")
    public static let movie = UTType(identifier: "public.movie")
    public static let mpeg4Movie = UTType(identifier: "public.mpeg-4")
    public static let quickTimeMovie = UTType(identifier: "com.apple.quicktime-movie")
}
