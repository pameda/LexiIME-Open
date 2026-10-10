import Foundation
import CryptoKit

struct SyncPhrase: Codable, Equatable {
    var code: String
    var text: String
}

struct SyncConflict: Identifiable {
    var code: String
    var text: String
    var id: String { code + "\t" + text }
}

struct DictionarySyncResult {
    var imported: Int
    var published: Int
    var phrases: [SyncPhrase]
    var conflicts: [SyncConflict]
}

// Invocation is opt-in at the caller. This exchanges only custom TSV dictionaries
// and versioned phrase snapshots; the caller persists the returned local phrases.
// Validate the complete plan before destination writes. Cancellation stops future
// writes, but cannot recall files already published to a folder's sync client.
enum DictionarySync {
    private static let dictionaryLimit = 128
    private static let dictionaryBytes = 8 * 1024 * 1024
    private static let totalBytes = 64 * 1024 * 1024
    private static let snapshotBytes = 1024 * 1024
    private static let manager = FileManager.default

    private struct Snapshot: Codable {
        var version: Int
        var phrases: [SyncPhrase]
    }

    private struct DictionaryFile {
        var url: URL
        var data: Data
        var hash: String
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func variantID(code: String, text: String) -> String {
        digest(Data((code + "\t" + text).utf8))
    }

    static func run(local: URL, folder: URL, deviceID: String, phrases: [SyncPhrase],
                    ignoredDictionaries: Set<String>, ignoredPhraseCodes: Set<String>,
                    ignoredVariants: Set<String>, packs: [URL] = []) throws -> DictionarySyncResult {
        try Task.checkCancellation()
        let local = try checkedURL(local)
        let folder = try checkedURL(folder)
        guard try isDirectory(folder) else { throw failure("同步文件夹不存在或不是目录。") }
        if try attributes(local) != nil, !(try isDirectory(local)) {
            throw failure("本地数据路径不是目录。")
        }
        guard !contains(local, folder), let uuid = UUID(uuidString: deviceID),
              uuid.uuidString.lowercased() == deviceID.lowercased() else {
            throw failure("同步文件夹不能位于本地数据内，设备标识须为 UUID。")
        }
        let ownName = uuid.uuidString.lowercased() + ".json"
        let root = folder.appendingPathComponent("LexiIME-Open-Sync", isDirectory: true)
        guard !contains(local, root), !contains(root, local) else {
            throw failure("同步目录与本地数据不能重叠。")
        }
        let localDictionaries = local.appendingPathComponent("Dictionaries", isDirectory: true)
        let remoteDictionaries = root.appendingPathComponent("dictionaries", isDirectory: true)
        let remotePhrases = root.appendingPathComponent("phrases", isDirectory: true)
        let ownURL = remotePhrases.appendingPathComponent(ownName)
        try checkTree(localDictionaries)
        try checkTree(root)
        // Store can retain stale in-memory phrases after a failed rebuild. An
        // existing file must be valid and agree with the captured caller snapshot
        // before it can be merged or published. Persistence remains caller-owned.
        let localPhrasesURL = try checkedURL(local.appendingPathComponent("phrases.tsv"))
        let originalPhraseData = try CommonPhrase.encode(phrases.map { CommonPhrase(code: $0.code, text: $0.text) })
        let localPhraseSource = try validatedLocalPhrases(at: localPhrasesURL, matching: originalPhraseData)

        let localFiles = try dictionaries(in: localDictionaries, addressed: false)
        let remoteFiles = try dictionaries(in: remoteDictionaries, addressed: true)
        var combined: [String: Data] = [:]
        for file in localFiles + remoteFiles {
            try Task.checkCancellation()
            if let previous = combined[file.hash], previous != file.data {
                throw failure("词库摘要发生冲突。")
            }
            combined[file.hash] = file.data
        }
        guard combined.count <= dictionaryLimit,
              combined.values.reduce(0, { $0 + $1.count }) <= totalBytes else {
            throw failure("合并词库超过 128 份或 64 MiB。")
        }

        let snapshotURLs = try children(remotePhrases).filter { snapshotName($0.lastPathComponent) }
        guard snapshotURLs.count + (snapshotURLs.contains(ownURL) ? 0 : 1) <= 128 else {
            throw failure("常用语快照最多 128 份。")
        }
        var variants: [String: Set<String>] = [:]
        var snapshotSources: [(URL, Data)] = []
        for url in snapshotURLs {
            try Task.checkCancellation()
            let data = try read(url, limit: snapshotBytes)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.version == 1 else { throw failure("不支持的常用语快照版本。") }
            _ = try CommonPhrase.encode(snapshot.phrases.map { CommonPhrase(code: $0.code, text: $0.text) })
            snapshotSources.append((url, data))
            // Own snapshots still undergo validation before any replacement.
            if url.lastPathComponent == ownName { continue }
            for phrase in snapshot.phrases where !ignoredPhraseCodes.contains(phrase.code)
                && !ignoredVariants.contains(variantID(code: phrase.code, text: phrase.text)) {
                variants[phrase.code, default: []].insert(phrase.text)
            }
        }
        var merged = phrases
        let localByCode = Dictionary(uniqueKeysWithValues: phrases.map { ($0.code, $0.text) })
        var conflicts: [SyncConflict] = []
        for code in variants.keys.sorted() {
            let texts = variants[code]!.sorted()
            if localByCode[code] == nil, texts.count == 1 {
                merged.append(SyncPhrase(code: code, text: texts[0]))
            } else {
                conflicts += texts.filter { $0 != localByCode[code] }.map { SyncConflict(code: code, text: $0) }
            }
        }
        let mergedData = try CommonPhrase.encode(merged.map { CommonPhrase(code: $0.code, text: $0.text) })
        // Ignored variants are pull decisions, not a tombstone for a local choice.
        let publishedPhrases = merged.filter { !ignoredPhraseCodes.contains($0.code) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let snapshotData = try encoder.encode(Snapshot(version: 1, phrases: publishedPhrases))
        guard snapshotData.count <= snapshotBytes else { throw failure("常用语快照超过 1 MiB。") }

        var packSources: [(URL, Data)] = []
        for pack in packs {
            try Task.checkCancellation()
            let url = try checkedURL(pack)
            packSources.append((url, try read(url, limit: dictionaryBytes)))
        }
        // Staging uses captured, bounded bytes, not paths which a sync client can
        // change between hashing and engine validation. No destination changes yet.
        let staging = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("LexiIME-Open-sync-" + UUID().uuidString, isDirectory: true)
        try createDirectory(staging)
        defer { try? manager.removeItem(at: staging) }
        let freshEngine = Engine()
        if let data = localPhraseSource {
            let url = staging.appendingPathComponent("local-phrases.tsv")
            try atomicWrite(data, to: url)
            try Task.checkCancellation()
            try freshEngine.phrases(url)
        }
        for (index, source) in packSources.enumerated() {
            let url = staging.appendingPathComponent("pack-\(index).tsv")
            try atomicWrite(source.1, to: url)
            try Task.checkCancellation()
            try freshEngine.load(url)
        }
        let localHashes = Set(localFiles.map(\.hash))
        for hash in combined.keys.sorted() where localHashes.contains(hash) || !ignoredDictionaries.contains(hash) {
            let url = staging.appendingPathComponent(hash + ".tsv")
            try atomicWrite(combined[hash]!, to: url)
            try Task.checkCancellation()
            try freshEngine.load(url)
        }
        let stagedPhrases = staging.appendingPathComponent("phrases.tsv")
        try atomicWrite(mergedData, to: stagedPhrases)
        try Task.checkCancellation()
        try freshEngine.phrases(stagedPhrases)

        let remoteHashes = Set(remoteFiles.map(\.hash))
        let pulls = remoteFiles.filter { !localHashes.contains($0.hash) && !ignoredDictionaries.contains($0.hash) }
        let publishes = combined.keys.sorted().filter { localHashes.contains($0)
            && !remoteHashes.contains($0) && !ignoredDictionaries.contains($0) }
        // Detect a colliding local sync name even if its bytes already exist under
        // another local name. Hash-addressed destinations may never be overwritten.
        for file in remoteFiles {
            let target = localDictionaries.appendingPathComponent("sync-" + file.hash + ".tsv")
            _ = try matchesExisting(file.data, at: target)
        }
        // Recheck captured originals before the first destination mutation.
        for file in localFiles + remoteFiles {
            guard try read(file.url, limit: dictionaryBytes) == file.data else {
                throw failure("校验期间词库已改变，请重试。")
            }
        }
        for source in packSources + snapshotSources {
            let limit = source.0.pathExtension == "tsv" ? dictionaryBytes : snapshotBytes
            guard try read(source.0, limit: limit) == source.1 else {
                throw failure("校验期间同步数据已改变，请重试。")
            }
        }
        try checkTree(localDictionaries)
        try checkTree(root)
        // Also catch changes, removal, or creation during validation. The parent
        // separately compares its captured original bytes before local apply.
        if let data = localPhraseSource {
            guard try read(localPhrasesURL, limit: snapshotBytes) == data else {
                throw failure("本地常用语在校验期间改变，请重试。")
            }
        } else {
            _ = try checkedURL(localPhrasesURL)
            guard try attributes(localPhrasesURL) == nil else {
                throw failure("本地常用语在校验期间改变，请重试。")
            }
        }
        try Task.checkCancellation()
        try createDirectory(localDictionaries)
        try createDirectory(remoteDictionaries)
        try createDirectory(remotePhrases)
        var imported = 0
        var published = 0
        for file in pulls {
            try Task.checkCancellation()
            let target = localDictionaries.appendingPathComponent("sync-" + file.hash + ".tsv")
            if try writeIfAbsent(file.data, to: target) { imported += 1 }
        }
        for hash in publishes {
            try Task.checkCancellation()
            if try writeIfAbsent(combined[hash]!, to: remoteDictionaries.appendingPathComponent(hash + ".tsv")) {
                published += 1
            }
        }
        // Repeated runs leave an identical own snapshot untouched. Only this
        // device's validated snapshot is replaceable; other devices are add-only.
        try Task.checkCancellation()
        if try attributes(ownURL) != nil {
            let expected = snapshotSources.first { $0.0 == ownURL }?.1
            guard let expected, try read(ownURL, limit: snapshotBytes) == expected else {
                throw failure("本设备快照在校验后改变，请重试。")
            }
            if expected != snapshotData { try atomicWrite(snapshotData, to: ownURL) }
        } else {
            _ = try writeIfAbsent(snapshotData, to: ownURL)
        }
        try Task.checkCancellation()
        return DictionarySyncResult(imported: imported, published: published, phrases: merged, conflicts: conflicts)
    }

    private static func failure(_ message: String) -> AppError { .message(message) }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        let prefix = parent.pathComponents
        return child.pathComponents.starts(with: prefix)
    }

    private static func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try manager.attributesOfItem(atPath: url.path) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
            throw error
        }
    }

    private static func checkedURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw failure("同步只支持本地文件夹路径。") }
        // Inspect lexical ancestors before normalization, including dangling links.
        var path = ""
        for component in url.pathComponents {
            try Task.checkCancellation()
            path = component == "/" ? "/" : (path as NSString).appendingPathComponent(component)
            if let info = try attributes(URL(fileURLWithPath: path)),
               info[.type] as? FileAttributeType == .typeSymbolicLink {
                throw failure("同步路径不能包含符号链接。")
            }
        }
        // Foundation's standardizedFileURL can rewrite an existing /private/tmp
        // path to /tmp (itself a symlink). Normalize only lexical dot components
        // so a previously checked physical path stays physical.
        var normalized: [String] = []
        for component in url.pathComponents where component != "/" {
            if component == "." { continue }
            if component == ".." { if !normalized.isEmpty { normalized.removeLast() } }
            else { normalized.append(component) }
        }
        return URL(fileURLWithPath: "/" + normalized.joined(separator: "/"), isDirectory: url.hasDirectoryPath)
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        _ = try checkedURL(url)
        return try attributes(url)?[.type] as? FileAttributeType == .typeDirectory
    }

    private static func children(_ directory: URL) throws -> [URL] {
        _ = try checkedURL(directory)
        guard try attributes(directory) != nil else { return [] }
        guard try isDirectory(directory) else { throw failure("同步路径不是目录。") }
        try Task.checkCancellation()
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func checkTree(_ directory: URL) throws {
        _ = try checkedURL(directory)
        guard try attributes(directory) != nil else { return }
        guard try isDirectory(directory) else { throw failure("词库或同步路径不是目录。") }
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw failure("无法检查同步目录。")
        }
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            _ = try checkedURL(url)
        }
        if let error = enumerationError { throw error }
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        _ = try checkedURL(url)
        guard let info = try attributes(url), info[.type] as? FileAttributeType == .typeRegular,
              let size = info[.size] as? NSNumber, size.int64Value <= Int64(limit) else {
            throw failure("同步文件不是普通文件或超过容量限制。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let part = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
            if part.isEmpty { break }
            data.append(part)
            guard data.count <= limit else { throw failure("同步文件超过容量限制。") }
        }
        _ = try checkedURL(url)
        return data
    }

    private static func validatedLocalPhrases(at url: URL, matching canonical: Data) throws -> Data? {
        _ = try checkedURL(url)
        guard try attributes(url) != nil else { return nil }
        let data = try read(url, limit: snapshotBytes)
        guard let text = String(data: data, encoding: .utf8) else {
            throw failure("本地常用语不是有效 UTF-8，原文件已保留。")
        }
        // Match the core TSV reader: a terminal LF does not add a row, and CR is
        // stripped only before an actual LF. Empty/interior malformed rows fail.
        var lines = data.isEmpty ? [] : text.components(separatedBy: "\n")
        let terminalLF = data.last == 10
        if terminalLF { lines.removeLast() }
        guard lines.count <= 1000 else { throw failure("本地常用语最多 1000 条，原文件已保留。") }
        var rows: [CommonPhrase] = []
        for (index, source) in lines.enumerated() {
            try Task.checkCancellation()
            var line = source
            if (index < lines.count - 1 || terminalLF), line.hasSuffix("\r") { line.removeLast() }
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 2 else { throw failure("本地常用语格式不正确，原文件已保留。") }
            rows.append(CommonPhrase(code: fields[0], text: fields[1]))
        }
        guard try CommonPhrase.encode(rows) == canonical else {
            throw failure("本地常用语与同步快照不一致，原文件已保留；请重新加载后同步。")
        }
        return data
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func dictionaries(in directory: URL, addressed: Bool) throws -> [DictionaryFile] {
        let urls = try children(directory).filter { $0.pathExtension == "tsv" && $0.lastPathComponent != "usage.tsv" }
        guard urls.count <= dictionaryLimit else { throw failure("词库最多 128 份。") }
        var result: [DictionaryFile] = []
        var bytes = 0
        for url in urls {
            try Task.checkCancellation()
            let data = try read(url, limit: dictionaryBytes)
            bytes += data.count
            guard bytes <= totalBytes else { throw failure("词库超过 64 MiB。") }
            let hash = digest(data)
            let name = url.deletingPathExtension().lastPathComponent
            if addressed && (!isHash(name) || name != hash) {
                throw failure("同步词库文件名与 SHA-256 摘要不符。")
            }
            if !addressed, name.hasPrefix("sync-"), isHash(String(name.dropFirst(5))), String(name.dropFirst(5)) != hash {
                throw failure("本地同步词库与 SHA-256 摘要不符。")
            }
            result.append(DictionaryFile(url: url, data: data, hash: hash))
        }
        return result
    }

    private static func snapshotName(_ name: String) -> Bool {
        guard name.hasSuffix(".json"), let uuid = UUID(uuidString: String(name.dropLast(5))) else { return false }
        return name == uuid.uuidString.lowercased() + ".json"
    }

    private static func createDirectory(_ url: URL) throws {
        _ = try checkedURL(url)
        if try attributes(url) != nil {
            guard try isDirectory(url) else { throw failure("同步路径不是目录。") }
            return
        }
        let parent = url.deletingLastPathComponent()
        try createDirectory(parent)
        _ = try checkedURL(url)
        try Task.checkCancellation()
        try manager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        _ = try checkedURL(url)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }

    private static func matchesExisting(_ data: Data, at url: URL) throws -> Bool {
        _ = try checkedURL(url)
        guard try attributes(url) != nil else { return false }
        guard try read(url, limit: max(dictionaryBytes, data.count)) == data else {
            throw failure("已存在的同步目标内容不同，原文件已保留。")
        }
        return true
    }

    private static func writeIfAbsent(_ data: Data, to url: URL) throws -> Bool {
        try Task.checkCancellation()
        if try matchesExisting(data, at: url) { return false }
        // .atomic alone replaces an existing destination. Atomically write a
        // sibling first, then link its complete inode exclusively into the target.
        // linkItem fails if a concurrent writer has already created the target.
        let temporary = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".tmp")
        defer { try? manager.removeItem(at: temporary) }
        try atomicWrite(data, to: temporary)
        _ = try checkedURL(url)
        try Task.checkCancellation()
        do { try manager.linkItem(at: temporary, to: url) }
        catch {
            try Task.checkCancellation()
            if try matchesExisting(data, at: url) { return false }
            throw error
        }
        return true
    }
}
