import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case text
        case url
        case file
        case image
    }

    public static let maxStoredTextUTF8Bytes = 256 * 1024
    public static let maxPreviewCharacters = 140

    public let id: UUID
    public let kind: Kind
    public let preview: String
    public let textContent: String?
    public let filePaths: [String]?
    public let blobFileName: String?
    public let byteSize: Int
    public let imageDimensions: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var copyCount: Int
    public var isPinned: Bool
    public let contentHash: UInt64

    public init(
        id: UUID = UUID(),
        kind: Kind,
        preview: String,
        textContent: String? = nil,
        filePaths: [String]? = nil,
        blobFileName: String? = nil,
        byteSize: Int,
        imageDimensions: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        copyCount: Int = 1,
        isPinned: Bool = false,
        contentHash: UInt64
    ) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.textContent = textContent
        self.filePaths = filePaths
        self.blobFileName = blobFileName
        self.byteSize = byteSize
        self.imageDimensions = imageDimensions
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.contentHash = contentHash
    }

    public static func makeText(
        _ rawText: String,
        sourceAppName: String? = nil,
        now: Date = Date()
    ) -> ClipboardItem? {
        let trimmedForCheck = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedForCheck.isEmpty else { return nil }

        let cappedText = capUTF8(rawText, maxBytes: maxStoredTextUTF8Bytes)
        let preview = buildSingleLinePreview(from: cappedText)
        let kind: Kind = isLikelySingleURL(trimmedForCheck) ? .url : .text
        let hash = fnv1a64(kind.rawValue + ":" + cappedText)

        return ClipboardItem(
            kind: kind,
            preview: preview,
            textContent: cappedText,
            byteSize: rawText.utf8.count,
            sourceAppName: sourceAppName,
            createdAt: now,
            contentHash: hash
        )
    }

    public static func makeFiles(
        paths: [String],
        sourceAppName: String? = nil,
        now: Date = Date()
    ) -> ClipboardItem? {
        let valid = paths.filter { !$0.isEmpty }
        guard let first = valid.first else { return nil }

        let firstName = URL(fileURLWithPath: first).lastPathComponent
        let preview: String
        if valid.count == 1 {
            preview = firstName
        } else {
            preview = "\(firstName) (+\(valid.count - 1) dosya)"
        }

        let joined = valid.joined(separator: "\n")
        let hash = fnv1a64("file:" + joined)

        return ClipboardItem(
            kind: .file,
            preview: preview,
            filePaths: valid,
            byteSize: joined.utf8.count,
            sourceAppName: sourceAppName,
            createdAt: now,
            contentHash: hash
        )
    }

    public static func makeImage(
        blobFileName: String,
        byteSize: Int,
        width: Int,
        height: Int,
        dataHash: UInt64,
        sourceAppName: String? = nil,
        now: Date = Date()
    ) -> ClipboardItem {
        let dims = (width > 0 && height > 0) ? "\(width)×\(height)" : nil
        let sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
        let preview = dims != nil ? "Görsel (\(dims!) • \(sizeLabel))" : "Görsel (\(sizeLabel))"

        return ClipboardItem(
            kind: .image,
            preview: preview,
            blobFileName: blobFileName,
            byteSize: byteSize,
            imageDimensions: dims,
            sourceAppName: sourceAppName,
            createdAt: now,
            contentHash: dataHash
        )
    }

    public func isSamePayload(as other: ClipboardItem) -> Bool {
        guard contentHash == other.contentHash && kind == other.kind else { return false }
        switch kind {
        case .text, .url:
            return textContent == other.textContent
        case .file:
            return filePaths == other.filePaths
        case .image:
            return contentHash == other.contentHash && byteSize == other.byteSize && imageDimensions == other.imageDimensions
        }
    }

    public static func buildSingleLinePreview(from string: String) -> String {
        var result = ""
        result.reserveCapacity(min(string.count, maxPreviewCharacters + 4))
        var lastWasSpace = true
        var count = 0

        for scalar in string.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                    count += 1
                }
            } else if scalar.value >= 32 {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
                count += 1
            }
            if count >= maxPreviewCharacters {
                return result.trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    public static func capUTF8(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        let data = Data(string.utf8.prefix(maxBytes))
        // Walk back up to 3 bytes if we sliced in the middle of a multi-byte UTF-8 sequence
        for trim in 0...3 where data.count >= trim {
            if let valid = String(data: data.dropLast(trim), encoding: .utf8) {
                return valid
            }
        }
        return String(string.prefix(maxBytes / 4))
    }

    private static func isLikelySingleURL(_ text: String) -> Bool {
        guard text.count <= 2048,
              !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              (text.hasPrefix("https://") || text.hasPrefix("http://")) else {
            return false
        }
        return URL(string: text)?.host != nil
    }

    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    public static func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

public enum SearchMatcher {
    private static let trLocale = Locale(identifier: "tr_TR")

    public static func normalize(_ input: String) -> String {
        let capped = input.count > 2048 ? String(input.prefix(2048)) : input
        return capped
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: trLocale)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Returns nil when not matched, or a score (higher is better: 2 = preview prefix, 1 = match).
    public static func matchScore(item: ClipboardItem, normalizedTokens: [String]) -> Int? {
        guard !normalizedTokens.isEmpty else { return 1 }

        let normPreview = normalize(item.preview)
        var lazyFullHaystack: String?

        for token in normalizedTokens {
            if normPreview.contains(token) {
                continue
            }
            if lazyFullHaystack == nil {
                var full = normPreview
                if let text = item.textContent {
                    full += " " + normalize(text)
                }
                if let files = item.filePaths {
                    full += " " + normalize(files.joined(separator: " "))
                }
                if let app = item.sourceAppName {
                    full += " " + normalize(app)
                }
                lazyFullHaystack = full
            }
            guard lazyFullHaystack!.contains(token) else {
                return nil
            }
        }

        if let first = normalizedTokens.first, normPreview.hasPrefix(first) {
            return 2
        }
        return 1
    }
}
