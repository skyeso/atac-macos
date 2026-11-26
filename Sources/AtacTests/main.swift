import AppKit
import Foundation
import AtacCore

private var passedTests = 0
private var failedTests = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passedTests += 1
    } else {
        failedTests += 1
        fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
    }
}

private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("AtacTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class MockPasteboardBackend: PasteboardBackend {
    var changeCount: Int = 0
    private var storageStrings: [NSPasteboard.PasteboardType: String] = [:]
    private var storageData: [NSPasteboard.PasteboardType: Data] = [:]
    private var storedPaths: [String] = []

    var types: [NSPasteboard.PasteboardType]? {
        var all = Set(storageStrings.keys).union(storageData.keys)
        if !storedPaths.isEmpty {
            all.insert(.fileURL)
        }
        return Array(all)
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        storageStrings[dataType]
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        storageData[dataType]
    }

    func readFileURLPaths() -> [String] {
        storedPaths
    }

    @discardableResult
    func clearContents() -> Int {
        storageStrings.removeAll()
        storageData.removeAll()
        storedPaths.removeAll()
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        storageStrings[dataType] = string
        return true
    }

    @discardableResult
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        if let data = data {
            storageData[dataType] = data
        } else {
            storageData.removeValue(forKey: dataType)
        }
        return true
    }

    func writeFileURLPaths(_ paths: [String]) {
        storedPaths = paths
    }
}

// 1. Preview formatting, URL detection & UTF-8 multibyte cap
do {
    let multiline = "   Merhaba   \n\t  dünya   nasılsın  \n "
    let item = ClipboardItem.makeText(multiline, sourceAppName: "Notlar")
    check(item != nil, "Text item should be created")
    check(item?.preview == "Merhaba dünya nasılsın", "Multiline whitespace should collapse cleanly")
    check(item?.kind == .text, "Plain text should be classified as .text")

    let urlItem = ClipboardItem.makeText("https://github.com/p0deje/Maccy")
    check(urlItem?.kind == .url, "HTTPS URL should be classified as .url")

    let repeatedTurkish = String(repeating: "ğüşiöçĞÜŞİÖÇ", count: 30_000)
    let cappedItem = ClipboardItem.makeText(repeatedTurkish)
    check(cappedItem != nil, "Large Turkish string should cap cleanly without invalid UTF-8")
    check((cappedItem?.textContent?.utf8.count ?? Int.max) <= ClipboardItem.maxStoredTextUTF8Bytes, "Stored text bytes must respect cap")
    check((cappedItem?.preview.count ?? Int.max) <= ClipboardItem.maxPreviewCharacters + 2, "Preview must remain compact")
}

// 2. Deduplication, Pinning, Eviction & Persistence
do {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(storageDirectory: dir, saveDebounceSeconds: 0)
    let a = ClipboardItem.makeText("Birinci kopya")!
    let b = ClipboardItem.makeText("İkinci kopya")!
    let c = ClipboardItem.makeText("Üçüncü kopya")!

    store.record(a, maxUnpinnedCount: 2)
    store.record(b, maxUnpinnedCount: 2)
    let pinnedState = store.togglePin(id: a.id)
    check(pinnedState == true, "Item A should become pinned")

    store.record(c, maxUnpinnedCount: 2)
    let d = ClipboardItem.makeText("Dördüncü kopya")!
    store.record(d, maxUnpinnedCount: 2)

    check(store.items.count == 3, "Store should keep 1 pinned + 2 unpinned items, got \(store.items.count)")
    check(store.items[0].preview == "Birinci kopya" && store.items[0].isPinned, "Pinned item should remain at index 0")
    check(store.items[1].preview == "Dördüncü kopya", "Newest unpinned item should follow pinned items")
    check(!store.items.contains(where: { $0.preview == "İkinci kopya" }), "Oldest unpinned item should be evicted")

    let cAgain = ClipboardItem.makeText("Üçüncü kopya")!
    store.record(cAgain, maxUnpinnedCount: 2)
    check(store.items[1].preview == "Üçüncü kopya", "Re-copied item should move to top of unpinned list")
    check(store.items[1].copyCount == 2, "Re-copied item copyCount should increment to 2")

    store.flushToDiskSynchronously()
    let reloaded = HistoryStore(storageDirectory: dir, saveDebounceSeconds: 0)
    check(reloaded.items.count == 3, "Reloaded store should preserve all 3 items")
    check(reloaded.items[0].isPinned && reloaded.items[0].preview == "Birinci kopya", "Reloaded store should preserve pinned state")

    reloaded.clear(includingPinned: false)
    check(reloaded.items.count == 1 && reloaded.items[0].isPinned, "Clearing unpinned should preserve pinned items")
}

// 3. Turkish Search Normalization & Speed
do {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(storageDirectory: dir, saveDebounceSeconds: 0)
    store.record(ClipboardItem.makeText("Işık hızında çalışan pano")!, maxUnpinnedCount: 300)
    store.record(ClipboardItem.makeText("Çağrı merkezi numarası: 444 0 123")!, maxUnpinnedCount: 300)
    store.record(ClipboardItem.makeText("Gizli şifre yönetimi")!, maxUnpinnedCount: 300)

    check(store.search(query: "isik").count == 1, "ASCII 'isik' must match Turkish 'Işık'")
    check(store.search(query: "cagri 444").count == 1, "Multi-token Turkish diacritic-insensitive search must match")
    check(store.search(query: "SIFRE").count == 1, "Uppercase ASCII 'SIFRE' must match 'şifre'")

    for idx in 0..<250 {
        store.record(ClipboardItem.makeText("Örnek metin satırı numara \(idx) - performans testi")!, maxUnpinnedCount: 300)
    }

    let t0 = CFAbsoluteTimeGetCurrent()
    let results = store.search(query: "ornek 199")
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
    check(!results.isEmpty, "Search on 250+ items must find target")
    check(elapsedMs < 25.0, "Search on 250+ items should be ultra-fast (<25ms), took \(String(format: "%.2f", elapsedMs))ms")
}

// 4. Disk-Backed Image Blob Eviction Cleanup
do {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = HistoryStore(storageDirectory: dir, saveDebounceSeconds: 0)
    let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    let blobName = store.writeBlobData(fakePNG, ext: "png")
    check(blobName != nil, "Image blob should write to disk")

    let imgItem = ClipboardItem.makeImage(
        blobFileName: blobName!,
        byteSize: fakePNG.count,
        width: 800,
        height: 600,
        dataHash: ClipboardItem.fnv1a64(fakePNG)
    )
    check(imgItem.textContent == nil, "Image item must hold zero bitmap/text payload in RAM")
    store.record(imgItem, maxUnpinnedCount: 5)
    check(store.readBlobData(named: blobName!) == fakePNG, "Stored blob must be readable on demand")

    store.delete(id: imgItem.id)
    store.flushToDiskSynchronously()
    check(store.readBlobData(named: blobName!) == nil, "Deleted image item must clean up its disk blob")
}

// 5. Pasteboard Monitor: Normal Copy, Concealed Password Filtering, Pause & Self-Copy Guard
do {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let suiteName = "com.atac.tests.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suiteName)!
    defer { testDefaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: testDefaults)
    let mockPB = MockPasteboardBackend()

    let store = HistoryStore(storageDirectory: dir, saveDebounceSeconds: 0)
    let monitor = ClipboardMonitor(backend: mockPB, store: store, settings: settings)

    // Normal copy
    mockPB.clearContents()
    mockPB.setString("Normal kopyalanan metin", forType: .string)
    monitor.pollOnce()
    check(store.items.count == 1, "Normal pasteboard string should be captured")

    // Password manager concealed copy must be ignored
    mockPB.clearContents()
    mockPB.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    mockPB.setString("SuperSecretPassword123!", forType: .string)
    monitor.pollOnce()
    check(store.items.count == 1, "Concealed password manager copy must be ignored")
    check(!store.items.contains(where: { $0.textContent?.contains("SuperSecretPassword") == true }), "Secret password must never enter history")

    // File copy
    mockPB.clearContents()
    mockPB.writeFileURLPaths(["/Users/test/Documents/rapor.pdf", "/Users/test/Documents/ozet.txt"])
    monitor.pollOnce()
    check(store.items.count == 2 && store.items[0].kind == .file, "Finder file URLs should be captured as .file")
    check(store.items[0].preview == "rapor.pdf (+1 dosya)", "Multiple files should format concise preview")

    // Pause blocks capture
    settings.setPaused(true)
    mockPB.clearContents()
    mockPB.setString("Duraklatılmış kopya", forType: .string)
    monitor.pollOnce()
    check(store.items.count == 2, "Paused monitor must ignore clipboard changes")
    settings.setPaused(false)

    // Self-copy from history must not create duplicates and must bump item to top
    let textItem = store.items[1]
    monitor.copyItemToPasteboard(textItem, plainTextOnly: false)
    monitor.pollOnce()
    check(store.items.count == 2, "Restoring item to pasteboard must not duplicate entry")
    check(store.items[0].id == textItem.id, "Restored item should bump to index 0")
    check(mockPB.string(forType: .string) == "Normal kopyalanan metin", "Restored item should be written to pasteboard")

    // Default openFilesOnSelect should be enabled
    check(settings.openFilesOnSelect == true, "openFilesOnSelect must default to true")
}

// 6. Plain NSTableView Geometry Check (No Horizontal Inset Drift)
do {
    final class DummySource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        func numberOfRows(in tableView: NSTableView) -> Int { 2 }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            NSTableCellView(frame: .zero)
        }
    }

    let w: CGFloat = 384
    let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: 120))
    sv.hasVerticalScroller = true
    sv.scrollerStyle = .overlay
    sv.borderType = .noBorder

    let tv = NSTableView(frame: NSRect(x: 0, y: 0, width: w, height: 120))
    tv.style = .plain
    tv.headerView = nil
    tv.intercellSpacing = NSSize(width: 0, height: 2)
    tv.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
    col.minWidth = w
    col.maxWidth = w
    col.width = w
    tv.addTableColumn(col)

    let ds = DummySource()
    tv.dataSource = ds
    tv.delegate = ds
    sv.documentView = tv
    sv.layoutSubtreeIfNeeded()
    tv.sizeLastColumnToFit()
    tv.reloadData()
    tv.layoutSubtreeIfNeeded()

    let rowRect = tv.rect(ofRow: 0)
    let cellRect = tv.frameOfCell(atColumn: 0, row: 0)
    check(rowRect.origin.x == 0 && rowRect.width == w, "Plain table row must start at x=0 and match width \(w), got \(rowRect)")
    check(cellRect.origin.x == 0 && cellRect.width == w, "Plain table cell must start at x=0 and match width \(w), got \(cellRect)")
}

print("AtacTests Tamamlandı: \(passedTests) başarılı, \(failedTests) başarısız.")
if failedTests > 0 {
    exit(1)
}
