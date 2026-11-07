// File types, as the open and save panels use them.
import Foundation
public struct UTType: Hashable, Sendable {
    public let identifier: String
    public var filenameExtension: String?
    public init(identifier: String, ext: String? = nil) { self.identifier = identifier; filenameExtension = ext }
    public init?(filenameExtension e: String) { identifier = "public.\(e)"; filenameExtension = e }
    public static let json = UTType(identifier: "public.json", ext: "json")
    public static let png = UTType(identifier: "public.png", ext: "png")
    public static let jpeg = UTType(identifier: "public.jpeg", ext: "jpg")
    public static let image = UTType(identifier: "public.image")
    public static let heic = UTType(identifier: "public.heic", ext: "heic")
    public static let gif = UTType(identifier: "com.compuserve.gif", ext: "gif")
    public static let tiff = UTType(identifier: "public.tiff", ext: "tiff")
    public static let plainText = UTType(identifier: "public.plain-text", ext: "txt")
    public static let data = UTType(identifier: "public.data")
    public static let movie = UTType(identifier: "public.movie")
}
