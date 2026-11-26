import Foundation

public final class HistoryStore {
    public private(set) var items: [ClipboardItem] = []

    public let storageDirectory: URL
    public let blobsDirectory: URL
    private let historyFileURL: URL

    private let ioQueue = DispatchQueue(label: "com.atac.history.io", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceSeconds: TimeInterval

    public var onItemsChanged: (() -> Void)?

    public init(storageDirectory: URL? = nil, saveDebounceSeconds: TimeInterval = 1.5) {
        if let custom = storageDirectory {
            self.storageDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("Atac", isDirectory: true)
        }
        self.blobsDirectory = self.storageDirectory.appendingPathComponent("blobs", isDirectory: true)
        self.historyFileURL = self.storageDirectory.appendingPathComponent("history.plist", isDirectory: false)
        self.saveDebounceSeconds = saveDebounceSeconds

        ensureDirectories()
        loadFromDisk()
        cleanupOrphanBlobsAsync()
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: historyFileURL) else { return }
        let decoder = PropertyListDecoder()
        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            self.items = sortCanonical(decoded)
        }
    }

    public func record(_ newItem: ClipboardItem, maxUnpinnedCount: Int) {
        if let existingIndex = items.firstIndex(where: { $0.isSamePayload(as: newItem) }) {
            var existing = items.remove(at: existingIndex)
            // If incoming item wrote a duplicate image blob file, remove the newly written duplicate blob
            if let newBlob = newItem.blobFileName, newBlob != existing.blobFileName {
                deleteBlobFile(named: newBlob)
            }
            existing.createdAt = newItem.createdAt
            existing.copyCount += 1
            if let app = newItem.sourceAppName {
                existing.sourceAppName = app
            }
            insertInOrder(existing)
        } else {
            insertInOrder(newItem)
            trimUnpinned(maxCount: maxUnpinnedCount)
        }
        scheduleSave()
        onItemsChanged?()
    }

    public func bumpToTop(id: UUID, now: Date = Date()) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: idx)
        item.createdAt = now
        item.copyCount += 1
        insertInOrder(item)
        scheduleSave()
        onItemsChanged?()
    }

    @discardableResult
    public func togglePin(id: UUID) -> Bool? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        var item = items.remove(at: idx)
        item.isPinned.toggle()
        let newState = item.isPinned
        insertInOrder(item)
        scheduleSave()
        onItemsChanged?()
        return newState
    }

    public func delete(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        if let blob = removed.blobFileName {
            deleteBlobFile(named: blob)
        }
        scheduleSave()
        onItemsChanged?()
    }

    public func clear(includingPinned: Bool = false) {
        if includingPinned {
            let blobs = items.compactMap(\.blobFileName)
            items.removeAll(keepingCapacity: false)
            for blob in blobs {
                deleteBlobFile(named: blob)
            }
        } else {
            let removedBlobs = items.filter { !$0.isPinned }.compactMap(\.blobFileName)
            items.removeAll { !$0.isPinned }
            for blob in removedBlobs {
                deleteBlobFile(named: blob)
            }
        }
        flushToDiskSynchronously()
        onItemsChanged?()
    }

    public func enforceLimit(maxUnpinnedCount: Int) {
        let beforeCount = items.count
        trimUnpinned(maxCount: maxUnpinnedCount)
        if items.count != beforeCount {
            scheduleSave()
            onItemsChanged?()
        }
    }

    public func search(query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let tokens = SearchMatcher.normalize(trimmed)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return items }

        var prefixMatches: [ClipboardItem] = []
        var otherMatches: [ClipboardItem] = []

        for item in items {
            guard let score = SearchMatcher.matchScore(item: item, normalizedTokens: tokens) else {
                continue
            }
            if score >= 2 {
                prefixMatches.append(item)
            } else {
                otherMatches.append(item)
            }
        }

        return prefixMatches + otherMatches
    }

    public func writeBlobData(_ data: Data, ext: String = "png") -> String? {
        ensureDirectories()
        let fileName = UUID().uuidString + "." + ext
        let url = blobsDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    public func readBlobData(named fileName: String) -> Data? {
        let url = blobsDirectory.appendingPathComponent(fileName, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    private func deleteBlobFile(named fileName: String) {
        let url = blobsDirectory.appendingPathComponent(fileName, isDirectory: false)
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func insertInOrder(_ item: ClipboardItem) {
        if item.isPinned {
            // Insert at the top of pinned items
            items.insert(item, at: 0)
        } else {
            // Insert right after all pinned items
            let firstUnpinnedIndex = items.firstIndex(where: { !$0.isPinned }) ?? items.count
            items.insert(item, at: firstUnpinnedIndex)
        }
    }

    private func sortCanonical(_ list: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = list.filter(\.isPinned).sorted { $0.createdAt > $1.createdAt }
        let unpinned = list.filter { !$0.isPinned }.sorted { $0.createdAt > $1.createdAt }
        return pinned + unpinned
    }

    private func trimUnpinned(maxCount: Int) {
        let limit = max(1, maxCount)
        var unpinnedSeen = 0
        var kept: [ClipboardItem] = []
        kept.reserveCapacity(min(items.count, limit + 16))

        for item in items {
            if item.isPinned {
                kept.append(item)
            } else if unpinnedSeen < limit {
                kept.append(item)
                unpinnedSeen += 1
            } else if let blob = item.blobFileName {
                deleteBlobFile(named: blob)
            }
        }
        items = kept
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let snapshot = items
        let targetURL = historyFileURL

        if saveDebounceSeconds <= 0 {
            writeSnapshot(snapshot, to: targetURL)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.writeSnapshot(snapshot, to: targetURL)
        }
        pendingSaveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + saveDebounceSeconds, execute: work)
    }

    public func flushToDiskSynchronously() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        let snapshot = items
        let targetURL = historyFileURL
        ioQueue.sync {
            writeSnapshot(snapshot, to: targetURL)
        }
    }

    private func writeSnapshot(_ snapshot: [ClipboardItem], to url: URL) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func cleanupOrphanBlobsAsync() {
        let referenced = Set(items.compactMap(\.blobFileName))
        let blobsDir = blobsDirectory
        ioQueue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: blobsDir.path) else { return }
            for file in files where !referenced.contains(file) {
                try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(file))
            }
        }
    }
}
