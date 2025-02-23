import Foundation
import SourceKittenFramework

extension String {
    internal func hasTrailingWhitespace() -> Bool {
        if isEmpty {
            return false
        }

        if let unicodescalar = unicodeScalars.last {
            return CharacterSet.whitespaces.contains(unicodescalar)
        }

        return false
    }

    internal func isUppercase() -> Bool {
        return self == uppercased()
    }

    internal func isLowercase() -> Bool {
        return self == lowercased()
    }

    internal func nameStrippingLeadingUnderscoreIfPrivate(_ dict: SourceKittenDictionary) -> String {
        if let acl = dict.accessibility,
            acl.isPrivate && first == "_" {
            return String(self[index(after: startIndex)...])
        }
        return self
    }

    private subscript (range: Range<Int>) -> String {
        let nsrange = NSRange(location: range.lowerBound,
                              length: range.upperBound - range.lowerBound)
        if let indexRange = nsrangeToIndexRange(nsrange) {
            return String(self[indexRange])
        }
        queuedFatalError("invalid range")
    }

    internal func substring(from: Int, length: Int? = nil) -> String {
        if let length = length {
            return self[from..<from + length]
        }
        return String(self[index(startIndex, offsetBy: from, limitedBy: endIndex)!...])
    }

    internal func lastIndex(of search: String) -> Int? {
        if let range = range(of: search, options: [.literal, .backwards]) {
            return distance(from: startIndex, to: range.lowerBound)
        }
        return nil
    }

    internal func nsrangeToIndexRange(_ nsrange: NSRange) -> Range<Index>? {
        guard nsrange.location != NSNotFound else {
            return nil
        }
        let from16 = utf16.index(utf16.startIndex, offsetBy: nsrange.location,
                                 limitedBy: utf16.endIndex) ?? utf16.endIndex
        let to16 = utf16.index(from16, offsetBy: nsrange.length,
                               limitedBy: utf16.endIndex) ?? utf16.endIndex

        guard let fromIndex = Index(from16, within: self),
            let toIndex = Index(to16, within: self) else {
                return nil
        }

        return fromIndex..<toIndex
    }

    internal var fullNSRange: NSRange {
        return NSRange(location: 0, length: utf16.count)
    }

    /// Returns a new string, converting the path to a canonical absolute path.
    ///
    /// - returns: A new `String`.
    public func absolutePathStandardized() -> String {
        return bridge().absolutePathRepresentation().bridge().standardizingPath
    }

    internal var isFile: Bool {
        if self.isEmpty {
            return false
        }
        var isDirectoryObjC: ObjCBool = false
        if FileManager.default.fileExists(atPath: self, isDirectory: &isDirectoryObjC) {
            return !isDirectoryObjC.boolValue
        }
        return false
    }

    /// Count the number of occurrences of the given character in `self`
    /// - Parameter character: Character to count
    /// - Returns: Number of times `character` occurs in `self`
    public func countOccurrences(of character: Character) -> Int {
        return self.reduce(0, {
            $1 == character ? $0 + 1 : $0
        })
    }

    /// If self is a path, this method can be used to get a path expression relative to a root directory
    public func path(relativeTo rootDirectory: String) -> String {
        let normalizedRootDir = rootDirectory.bridge().standardizingPath
        let normalizedSelf = bridge().standardizingPath
        if normalizedRootDir.isEmpty {
            return normalizedSelf
        }
        var rootDirComps = normalizedRootDir.components(separatedBy: "/")
        let rootDirCompsCount = rootDirComps.count

        while true {
            let sharedRootDir = rootDirComps.joined(separator: "/")
            if normalizedSelf == sharedRootDir || normalizedSelf.hasPrefix(sharedRootDir + "/") {
                let path = (0 ..< rootDirCompsCount - rootDirComps.count).map { _ in "/.." }.flatMap { $0 }
                    + String(normalizedSelf.dropFirst(sharedRootDir.count))
                return String(path.dropFirst()) // Remove leading '/'
            } else {
                rootDirComps = rootDirComps.dropLast()
            }
        }
    }

    internal func hasAnyPrefix(of prefixes: [String]) -> Bool {
        prefixes.contains(where: hasPrefix)
    }
}
