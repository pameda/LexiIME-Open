import Foundation

// Standalone integration routine; the parent test entry point calls it. Every
// fixture (including mock secrets) stays under one UUID directory in /private/tmp.
func runSyncChecks() throws -> Int {
    let fm = FileManager.default
    let fixtures = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("LexiIME-Open-sync-checks-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: fixtures, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: fixtures) }
    var checks = 0
    let deviceA = UUID().uuidString.lowercased()
    let deviceB = UUID().uuidString.lowercased()
    let deviceC = UUID().uuidString.lowercased()
    let alpha = Data("alpha\talpha\t\tone\t\t\t100\tfixture\n".utf8)
    let beta = Data("beta\tbeta\t\ttwo\t\t\t100\tfixture\n".utf8)

    func check(_ condition: Bool, _ label: String) throws {
        guard condition else { throw NSError(domain: "LexiIME-Open.SyncChecks", code: 1,
            userInfo: [NSLocalizedDescriptionKey: label]) }
        checks += 1
    }
    func rejects(_ label: String, _ operation: () throws -> Void) throws {
        var rejected = false
        do { try operation() } catch { rejected = true }
        try check(rejected, label)
    }
    func scenario(_ name: String) throws -> (local: URL, folder: URL) {
        let base = fixtures.appendingPathComponent(name, isDirectory: true)
        let local = base.appendingPathComponent("local", isDirectory: true)
        let folder = base.appendingPathComponent("shared", isDirectory: true)
        try fm.createDirectory(at: local.appendingPathComponent("Dictionaries"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        return (local, folder)
    }
    func write(_ data: Data, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    func localFile(_ local: URL, _ name: String = "original.tsv") -> URL {
        local.appendingPathComponent("Dictionaries").appendingPathComponent(name)
    }
    func remoteFile(_ folder: URL, _ data: Data) -> URL {
        folder.appendingPathComponent("LexiIME-Open-Sync/dictionaries/" + DictionarySync.digest(data) + ".tsv")
    }
    func snapshotURL(_ folder: URL, _ id: String) -> URL {
        folder.appendingPathComponent("LexiIME-Open-Sync/phrases/" + id.lowercased() + ".json")
    }
    func snapshot(_ rows: [SyncPhrase], version: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": version,
            "phrases": rows.map { ["code": $0.code, "text": $0.text] }], options: [.sortedKeys])
    }
    func snapshotRows(_ url: URL) throws -> [SyncPhrase] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        try check(object["version"] as? Int == 1, "Snapshot version")
        return (object["phrases"] as! [[String: String]]).map { SyncPhrase(code: $0["code"]!, text: $0["text"]!) }
    }
    func run(_ local: URL, _ folder: URL, id: String = deviceA, phrases: [SyncPhrase] = [],
             hashes: Set<String> = [], codes: Set<String> = [], variants: Set<String> = [],
             packs: [URL] = []) throws -> DictionarySyncResult {
        try DictionarySync.run(local: local, folder: folder, deviceID: id, phrases: phrases,
            ignoredDictionaries: hashes, ignoredPhraseCodes: codes, ignoredVariants: variants, packs: packs)
    }
    func untouched(_ local: URL, _ folder: URL, original: Data = alpha) throws {
        try check(try Data(contentsOf: localFile(local)) == original, "Original dictionary retained")
        try check(!fm.fileExists(atPath: localFile(local, "sync-" + DictionarySync.digest(beta) + ".tsv").path), "No premature import")
        try check(!fm.fileExists(atPath: remoteFile(folder, original).path), "No premature publication")
        try check(!fm.fileExists(atPath: snapshotURL(folder, deviceA).path), "No premature own snapshot")
    }

    try check(DictionarySync.digest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 empty vector")
    try check(DictionarySync.digest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 abc vector")
    try check(DictionarySync.variantID(code: "mail", text: "fixture") == DictionarySync.digest(Data("mail\tfixture".utf8)), "Variant identity")
    try check(SyncConflict(code: "mail", text: "fixture").id == "mail\tfixture", "Conflict ForEach identity")

    // Two devices, bidirectional dictionary exchange, actual engine use, and no
    // parent-owned phrase writes. Uppercase device UUIDs publish lowercase names.
    let exchange = try scenario("exchange")
    let secondLocal = exchange.local.deletingLastPathComponent().appendingPathComponent("second")
    try write(alpha, localFile(exchange.local))
    try write(beta, localFile(secondLocal))
    let aPhrase = SyncPhrase(code: "alpha", text: "本地甲")
    let bPhrase = SyncPhrase(code: "beta", text: "本地乙")
    let originalPhrases = try CommonPhrase.encode([CommonPhrase(code: aPhrase.code, text: aPhrase.text)])
    try write(originalPhrases, exchange.local.appendingPathComponent("phrases.tsv"))
    let first = try run(exchange.local, exchange.folder, id: deviceA.uppercased(), phrases: [aPhrase])
    try check(first.imported == 0 && first.published == 1 && first.phrases == [aPhrase], "First device publication")
    let second = try run(secondLocal, exchange.folder, id: deviceB, phrases: [bPhrase])
    try check(second.imported == 1 && second.published == 1 && second.phrases == [bPhrase, aPhrase], "Second device exchange")
    let third = try run(exchange.local, exchange.folder, phrases: first.phrases)
    try check(third.imported == 1 && third.published == 0 && third.phrases == [aPhrase, bPhrase], "Return exchange")
    try check(try Data(contentsOf: exchange.local.appendingPathComponent("phrases.tsv")) == originalPhrases, "Caller owns phrase persistence")
    // Simulate the parent applying the returned phrases before another run.
    let appliedPhrases = try CommonPhrase.encode(third.phrases.map { CommonPhrase(code: $0.code, text: $0.text) })
    try write(appliedPhrases, exchange.local.appendingPathComponent("phrases.tsv"))
    let ownBefore = try Data(contentsOf: snapshotURL(exchange.folder, deviceA))
    let ownDate = try fm.attributesOfItem(atPath: snapshotURL(exchange.folder, deviceA).path)[.modificationDate] as! Date
    let repeated = try run(exchange.local, exchange.folder, phrases: third.phrases)
    try check(repeated.imported == 0 && repeated.published == 0 && repeated.phrases == third.phrases && repeated.conflicts.isEmpty, "Idempotence")
    try check(try Data(contentsOf: snapshotURL(exchange.folder, deviceA)) == ownBefore, "Stable own snapshot bytes")
    try check(try fm.attributesOfItem(atPath: snapshotURL(exchange.folder, deviceA).path)[.modificationDate] as? Date == ownDate, "Identical snapshot is not rewritten")
    try check(try Data(contentsOf: exchange.local.appendingPathComponent("phrases.tsv")) == appliedPhrases, "Repeated sync preserves caller-applied phrases")
    try check(try Data(contentsOf: localFile(exchange.local)) == alpha, "Exchange preserves original")
    let engine = Engine()
    try engine.load(localFile(exchange.local))
    try engine.load(localFile(exchange.local, "sync-" + DictionarySync.digest(beta) + ".tsv"))
    try check(engine.query("beta", Preferences()).first?.text == "beta", "Imported dictionary is queryable")

    let duplicate = try scenario("duplicate")
    try write(alpha, localFile(duplicate.local))
    try write(alpha, localFile(duplicate.local, "copy.tsv"))
    try write(alpha, remoteFile(duplicate.folder, alpha))
    let deduped = try run(duplicate.local, duplicate.folder)
    try check(deduped.imported == 0 && deduped.published == 0, "Deduplicate by bytes across different local filenames")
    try check(try fm.contentsOfDirectory(atPath: duplicate.local.appendingPathComponent("Dictionaries").path).count == 2, "No duplicate import")

    // Conflicts preserve local content. Multiple remote variants of an absent
    // code produce choices rather than an arbitrary winner; duplicates collapse.
    let conflict = try scenario("conflict")
    let localChoices = [SyncPhrase(code: "mail", text: "local"), SyncPhrase(code: "same", text: "same")]
    let remoteB = try snapshot([SyncPhrase(code: "mail", text: "remote"), SyncPhrase(code: "amb", text: "one"), localChoices[1]])
    let remoteC = try snapshot([SyncPhrase(code: "mail", text: "remote"), SyncPhrase(code: "amb", text: "two"), localChoices[1]])
    try write(remoteB, snapshotURL(conflict.folder, deviceB))
    try write(remoteC, snapshotURL(conflict.folder, deviceC))
    let choices = try run(conflict.local, conflict.folder, phrases: localChoices)
    try check(choices.phrases == localChoices, "Conflict preserves local choices")
    try check(choices.conflicts.map(\.id) == ["amb\tone", "amb\ttwo", "mail\tremote"], "Sorted deduplicated conflict variants")
    try check(try Data(contentsOf: snapshotURL(conflict.folder, deviceB)) == remoteB && Data(contentsOf: snapshotURL(conflict.folder, deviceC)) == remoteC, "Other device snapshots unchanged")
    try check(try snapshotRows(snapshotURL(conflict.folder, deviceA)) == localChoices, "Publish merged local choices only")

    let ignored = try scenario("ignored")
    try write(alpha, localFile(ignored.local))
    try write(beta, remoteFile(ignored.folder, beta))
    let chosen = SyncPhrase(code: "mail", text: "chosen")
    let hidden = SyncPhrase(code: "hidden", text: "kept locally")
    try write(try snapshot([SyncPhrase(code: "mail", text: "old"), SyncPhrase(code: "gone", text: "removed"), SyncPhrase(code: "amb", text: "one")]), snapshotURL(ignored.folder, deviceB))
    try write(try snapshot([SyncPhrase(code: "amb", text: "two")]), snapshotURL(ignored.folder, deviceC))
    let filtered = try run(ignored.local, ignored.folder, phrases: [chosen, hidden],
        hashes: [DictionarySync.digest(alpha), DictionarySync.digest(beta)], codes: ["gone", "hidden"],
        variants: [DictionarySync.variantID(code: "mail", text: "old"), DictionarySync.variantID(code: "mail", text: "chosen"), DictionarySync.variantID(code: "amb", text: "one")])
    try check(filtered.imported == 0 && filtered.published == 0 && filtered.conflicts.isEmpty, "Ignored hashes and pull variants")
    try check(filtered.phrases == [chosen, hidden, SyncPhrase(code: "amb", text: "two")], "Ignored codes preserve current local content")
    try check(try snapshotRows(snapshotURL(ignored.folder, deviceA)) == [chosen, SyncPhrase(code: "amb", text: "two")], "Chosen local variant publishes even if ignored on pull")
    try check(!fm.fileExists(atPath: remoteFile(ignored.folder, alpha).path), "Ignored local hash is not published")

    // ALL recognized snapshots, including this device's own, validate before any
    // import/publication. Unrecognized names and temporary files are ignored.
    let invalidRows: [[SyncPhrase]] = [
        [SyncPhrase(code: "UPPER", text: "x")], [SyncPhrase(code: "a", text: "x"), SyncPhrase(code: "a", text: "y")],
        [SyncPhrase(code: "a", text: "bad\nline")], [SyncPhrase(code: "a", text: "")],
        [SyncPhrase(code: "a", text: String(repeating: "字", count: 171))],
        [SyncPhrase(code: String(repeating: "a", count: 33), text: "x")],
        [SyncPhrase(code: "a1", text: "x")], [SyncPhrase(code: "a", text: "bad\u{7f}")]
    ]
    var corruptSnapshots = [Data("broken JSON".utf8), try snapshot([], version: 2), Data(repeating: 32, count: 1024 * 1024 + 1)]
    corruptSnapshots += try invalidRows.map { try snapshot($0) }
    for (index, bytes) in corruptSnapshots.enumerated() {
        let test = try scenario("invalid-snapshot-\(index)")
        try write(alpha, localFile(test.local))
        try write(beta, remoteFile(test.folder, beta))
        let badURL = snapshotURL(test.folder, deviceB)
        try write(bytes, badURL)
        try rejects("Invalid snapshot rejected") { _ = try run(test.local, test.folder, codes: ["a", "UPPER"]) }
        try untouched(test.local, test.folder)
        try check(try Data(contentsOf: badURL) == bytes, "Corrupt snapshot retained")
    }
    let ownCorrupt = try scenario("own-corrupt")
    try write(alpha, localFile(ownCorrupt.local))
    try write(beta, remoteFile(ownCorrupt.folder, beta))
    let corruptOwn = Data("corrupt own snapshot".utf8)
    try write(corruptOwn, snapshotURL(ownCorrupt.folder, deviceA))
    try rejects("Own corruption rejected before replacement") { _ = try run(ownCorrupt.local, ownCorrupt.folder) }
    try check(try Data(contentsOf: snapshotURL(ownCorrupt.folder, deviceA)) == corruptOwn, "Corrupt own snapshot not overwritten")
    try check(!fm.fileExists(atPath: remoteFile(ownCorrupt.folder, alpha).path), "Own corruption blocks dictionary publication")
    let ownStale = try scenario("own-stale")
    try write(try snapshot([SyncPhrase(code: "old", text: "stale")]), snapshotURL(ownStale.folder, deviceA))
    let stale = try run(ownStale.local, ownStale.folder, phrases: [chosen])
    try check(stale.phrases == [chosen], "Own valid snapshot ignored on pull")
    let unknown = try scenario("unknown")
    for name in ["random.json", deviceB + ".json.tmp", "." + deviceC + ".tmp", deviceC.uppercased() + ".json"] {
        try write(Data("not a snapshot".utf8), unknown.folder.appendingPathComponent("LexiIME-Open-Sync/phrases/" + name))
    }
    let unknownResult = try run(unknown.local, unknown.folder)
    try check(unknownResult.phrases.isEmpty, "Unknown and temporary snapshot names ignored")

    for (index, badData) in [Data("invalid TSV".utf8), beta].enumerated() {
        let test = try scenario("invalid-dictionary-\(index)")
        try write(alpha, localFile(test.local))
        let badURL = index == 0 ? remoteFile(test.folder, badData) : remoteFile(test.folder, alpha)
        try write(badData, badURL)
        try rejects("Malformed or misnamed dictionary rejected") { _ = try run(test.local, test.folder) }
        try check(try Data(contentsOf: localFile(test.local)) == alpha && Data(contentsOf: badURL) == badData, "Dictionary originals unchanged")
        try check(!fm.fileExists(atPath: snapshotURL(test.folder, deviceA).path), "Dictionary corruption blocks phrase publication")
    }
    let badLocal = try scenario("bad-local")
    let invalid = Data("local corruption".utf8)
    try write(invalid, localFile(badLocal.local))
    try write(beta, remoteFile(badLocal.folder, beta))
    try rejects("Corrupt local dictionary blocks import") { _ = try run(badLocal.local, badLocal.folder) }
    try untouched(badLocal.local, badLocal.folder, original: invalid)
    let collision = try scenario("collision")
    try write(alpha, localFile(collision.local))
    let collidingTarget = localFile(collision.local, "sync-" + DictionarySync.digest(beta) + ".tsv")
    try write(alpha, collidingTarget)
    try write(beta, remoteFile(collision.folder, beta))
    try rejects("Existing hash target must match") { _ = try run(collision.local, collision.folder) }
    try check(try Data(contentsOf: collidingTarget) == alpha, "Colliding target never overwritten")

    // Only Dictionaries/*.tsv and in-memory common phrases participate. Even
    // invalid usage, credentials and settings are excluded from reads/publication.
    let excluded = try scenario("excluded")
    try write(alpha, localFile(excluded.local))
    let excludedNames = ["usage.tsv", "words.json", "settings.json", "keys.json", "audio/recording.wav", "logs/session.log"]
    let privateBytes = Data("FIXTURE ONLY: not dictionary data or real credentials".utf8)
    for name in excludedNames {
        try write(privateBytes, excluded.local.appendingPathComponent(name))
        try write(privateBytes, excluded.folder.appendingPathComponent("LexiIME-Open-Sync/" + name))
    }
    try write(privateBytes, localFile(excluded.local, "usage.tsv"))
    let exclusion = try run(excluded.local, excluded.folder)
    try check(exclusion.published == 1, "Only custom dictionary published")
    try check(try fm.contentsOfDirectory(atPath: excluded.folder.appendingPathComponent("LexiIME-Open-Sync/dictionaries").path) == [DictionarySync.digest(alpha) + ".tsv"], "No sensitive files in dictionary exchange")
    for name in excludedNames {
        try check(try Data(contentsOf: excluded.local.appendingPathComponent(name)) == privateBytes, "Excluded local file unchanged")
    }

    let paths = try scenario("paths")
    try rejects("Missing folder") { _ = try run(paths.local, paths.folder.appendingPathComponent("missing")) }
    let regularFolder = paths.folder.appendingPathComponent("regular")
    try write(Data(), regularFolder)
    try rejects("Folder must be a directory") { _ = try run(paths.local, regularFolder) }
    try rejects("Local folder equality") { _ = try run(paths.local, paths.local) }
    try rejects("Local descendant folder") { _ = try run(paths.local, paths.local.appendingPathComponent("Dictionaries")) }
    try rejects("Invalid device identifier") { _ = try run(paths.local, paths.folder, id: "../../escape") }
    let similar = paths.local.deletingLastPathComponent().appendingPathComponent("local-extra")
    try fm.createDirectory(at: similar, withIntermediateDirectories: false)
    _ = try run(paths.local, similar)
    try check(fm.fileExists(atPath: snapshotURL(similar, deviceA).path), "Component containment permits sibling prefix")

    // Reject redirected roots, ancestors, dictionary/snapshot entries, nested
    // links, dangling links, parent-owned phrases, and active bundled packs.
    for kind in ["local-root", "folder-root", "dictionary", "nested", "dangling", "snapshot", "phrases", "dictionary-dir", "remote-dir", "pack"] {
        let test = try scenario("symlink-" + kind)
        try write(alpha, localFile(test.local))
        let outside = test.local.deletingLastPathComponent().appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        let outsideFile = outside.appendingPathComponent("sentinel.tsv")
        try write(beta, outsideFile)
        var local = test.local
        var folder = test.folder
        var packs: [URL] = []
        let link: URL
        let destination: URL
        switch kind {
        case "local-root": link = outside.appendingPathComponent("local-link"); destination = test.local; local = link
        case "folder-root": link = outside.appendingPathComponent("folder-link"); destination = test.folder; folder = link
        case "dictionary": link = localFile(test.local, "linked.tsv"); destination = outsideFile
        case "nested": link = test.folder.appendingPathComponent("LexiIME-Open-Sync/unused/deeper/link"); destination = outside
        case "dangling": link = test.folder.appendingPathComponent("LexiIME-Open-Sync/dangling"); destination = outside.appendingPathComponent("missing")
        case "snapshot": link = snapshotURL(test.folder, deviceB); destination = outsideFile
        case "phrases": link = test.local.appendingPathComponent("phrases.tsv"); destination = outsideFile
        case "dictionary-dir":
            link = test.local.appendingPathComponent("Dictionaries/nested/link"); destination = outside
        case "remote-dir": link = test.folder.appendingPathComponent("LexiIME-Open-Sync/dictionaries"); destination = outside
        default: link = outside.appendingPathComponent("pack-link.tsv"); destination = outsideFile; packs = [link]
        }
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: destination)
        try rejects("Symbolic link rejected: " + kind) { _ = try run(local, folder, packs: packs) }
        try check(try Data(contentsOf: outsideFile) == beta, "Symlink target untouched")
        try check(!fm.fileExists(atPath: remoteFile(test.folder, alpha).path), "Symlink rejection before publication")
    }

    // Limits apply to both sides and their combined unique set. Built-in packs
    // participate in the actual engine capacity, but never in publication.
    let many = try scenario("many-dictionaries")
    for index in 0..<128 {
        try write(alpha + Data("# \(index)\n".utf8), localFile(many.local, "\(index).tsv"))
    }
    try write(beta, remoteFile(many.folder, beta))
    try rejects("Combined dictionary count") { _ = try run(many.local, many.folder) }
    try check(!fm.fileExists(atPath: snapshotURL(many.folder, deviceA).path), "Count validation before writes")
    let oversized = try scenario("oversized")
    try write(Data(repeating: 32, count: 8 * 1024 * 1024 + 1), localFile(oversized.local))
    try rejects("Per dictionary byte limit") { _ = try run(oversized.local, oversized.folder) }
    let combinedBytes = try scenario("combined-bytes")
    for index in 0..<8 {
        let header = alpha + Data("# \(index) ".utf8)
        let data = header + Data(repeating: 120, count: 8 * 1024 * 1024 - header.count)
        if index < 4 { try write(data, localFile(combinedBytes.local, "\(index).tsv")) }
        else { try write(data, remoteFile(combinedBytes.folder, data)) }
    }
    try write(beta, remoteFile(combinedBytes.folder, beta))
    try rejects("Combined 64 MiB limit") { _ = try run(combinedBytes.local, combinedBytes.folder) }
    try check(!fm.fileExists(atPath: snapshotURL(combinedBytes.folder, deviceA).path), "Byte validation before writes")
    let manySnapshots = try scenario("many-snapshots")
    for _ in 0..<128 { try write(try snapshot([]), snapshotURL(manySnapshots.folder, UUID().uuidString)) }
    try rejects("Reserve capacity for own snapshot") { _ = try run(manySnapshots.local, manySnapshots.folder) }

    func letterCode(_ index: Int) -> String {
        var value = index
        var code = ""
        repeat { code.append(Character(UnicodeScalar(97 + value % 26)!)); value /= 26 } while value > 0
        return code
    }
    let packCap = try scenario("pack-cap")
    var largeText = ""
    for index in 0..<50_000 { largeText += "entry\(index)\t" + letterCode(index) + "\t\tx\t\t\t1\tfixture\n" }
    let pack = packCap.local.deletingLastPathComponent().appendingPathComponent("builtin.tsv")
    let largeDictionary = Data(largeText.utf8)
    try write(largeDictionary, pack)
    try write(alpha, localFile(packCap.local))
    try write(beta, remoteFile(packCap.folder, beta))
    try rejects("Built-in plus custom engine entry cap") { _ = try run(packCap.local, packCap.folder, packs: [pack]) }
    try untouched(packCap.local, packCap.folder)
    try check(try Data(contentsOf: pack) == largeDictionary, "Built-in pack unchanged")
    let ignoredCap = try scenario("ignored-cap")
    try write(alpha, localFile(ignoredCap.local))
    try write(largeDictionary, remoteFile(ignoredCap.folder, largeDictionary))
    let ignoredLarge = try run(ignoredCap.local, ignoredCap.folder, hashes: [DictionarySync.digest(largeDictionary)])
    try check(ignoredLarge.imported == 0 && ignoredLarge.published == 1, "Ignored remote dictionary excluded from engine capacity")
    try check(!fm.fileExists(atPath: remoteFile(ignoredCap.folder, beta).path), "Ignored capacity run does not synthesize dictionaries")
    let ignoredLocalCap = try scenario("ignored-local-cap")
    try write(largeDictionary, localFile(ignoredLocalCap.local))
    try write(beta, remoteFile(ignoredLocalCap.folder, beta))
    try rejects("Ignored hash still validates when locally loaded") {
        _ = try run(ignoredLocalCap.local, ignoredLocalCap.folder, hashes: [DictionarySync.digest(largeDictionary)])
    }

    let phraseCap = try scenario("phrase-cap")
    let thousand = (0..<1000).map { SyncPhrase(code: "p" + letterCode($0), text: "fixture") }
    try write(try snapshot([SyncPhrase(code: "new", text: "extra")]), snapshotURL(phraseCap.folder, deviceB))
    try rejects("Merged phrases limited to 1000") { _ = try run(phraseCap.local, phraseCap.folder, phrases: thousand) }
    try check(!fm.fileExists(atPath: snapshotURL(phraseCap.folder, deviceA).path), "Merged phrase failure does not publish")
    try write(try snapshot(thousand + [SyncPhrase(code: "new", text: "extra")]), snapshotURL(phraseCap.folder, deviceB))
    try rejects("Snapshot limited to 1000 unique triggers") { _ = try run(phraseCap.local, phraseCap.folder) }
    let invalidLocalPhrases = try scenario("invalid-local-phrases")
    try write(alpha, localFile(invalidLocalPhrases.local))
    try rejects("Invalid caller phrases block dictionary publication") {
        _ = try run(invalidLocalPhrases.local, invalidLocalPhrases.folder, phrases: [SyncPhrase(code: "BAD", text: "fixture")])
    }
    try check(!fm.fileExists(atPath: remoteFile(invalidLocalPhrases.folder, alpha).path), "Local phrase validation precedes all publication")

    // A failed Store rebuild can leave valid but stale in-memory phrases. Validate
    // the actual bounded local file before dictionary imports or snapshot writes.
    let invalidLocalFiles = [
        Data([0xff]), Data("broken TSV\n".utf8), Data("good\tok\nbroken\n".utf8),
        Data("a\tone\na\ttwo\n".utf8), Data("UPPER\tvalue\n".utf8),
        Data("a\tbad\u{0}control\n".utf8), Data("a\tvalue\r".utf8),
        Data("\n".utf8), Data("a\tvalue\n\n".utf8), Data("a\tone\ttwo\n".utf8),
        Data("# comment\n".utf8), Data("a\t\n".utf8), Data("a1\tvalue\n".utf8),
        Data((String(repeating: "a", count: 33) + "\tvalue\n").utf8),
        Data(("a\t" + String(repeating: "字", count: 171) + "\n").utf8),
        Data("\u{feff}a\tvalue\n".utf8),
        Data(thousand.map { $0.code + "\t" + $0.text + "\n" }.joined().utf8) + Data("new\textra\n".utf8),
        Data(repeating: 32, count: 1024 * 1024 + 1)
    ]
    for (index, bytes) in invalidLocalFiles.enumerated() {
        let test = try scenario("invalid-local-file-\(index)")
        let file = test.local.appendingPathComponent("phrases.tsv")
        try write(alpha, localFile(test.local))
        try write(beta, remoteFile(test.folder, beta))
        try write(try snapshot([SyncPhrase(code: "remote", text: "would import")]), snapshotURL(test.folder, deviceB))
        try write(bytes, file)
        let stalePhrases = [SyncPhrase(code: "good", text: "ok")]
        try rejects("Invalid existing local phrase file rejects stale caller state") {
            _ = try run(test.local, test.folder, phrases: stalePhrases, codes: ["a", "UPPER"])
        }
        try check(try Data(contentsOf: file) == bytes, "Invalid local phrases retained byte for byte")
        try untouched(test.local, test.folder)
    }

    let diskRows = [SyncPhrase(code: "first", text: "first value"), SyncPhrase(code: "second", text: "second value")]
    let diskBytes = try CommonPhrase.encode(diskRows.map { CommonPhrase(code: $0.code, text: $0.text) })
    let staleSnapshots: [[SyncPhrase]] = [[], [diskRows[0]],
        [SyncPhrase(code: "first", text: "old value"), diskRows[1]], Array(diskRows.reversed())]
    for (index, staleRows) in staleSnapshots.enumerated() {
        let test = try scenario("stale-local-snapshot-\(index)")
        let file = test.local.appendingPathComponent("phrases.tsv")
        try write(alpha, localFile(test.local))
        try write(beta, remoteFile(test.folder, beta))
        try write(diskBytes, file)
        try rejects("Caller snapshot must match the canonical local file") { _ = try run(test.local, test.folder, phrases: staleRows) }
        try check(try Data(contentsOf: file) == diskBytes, "Valid local phrases protected from stale snapshot")
        try untouched(test.local, test.folder)
    }
    let emptyStale = try scenario("empty-local-stale")
    try write(alpha, localFile(emptyStale.local))
    try write(beta, remoteFile(emptyStale.folder, beta))
    try write(Data(), emptyStale.local.appendingPathComponent("phrases.tsv"))
    try rejects("Empty local file does not resurrect stale phrases") { _ = try run(emptyStale.local, emptyStale.folder, phrases: [chosen]) }
    try check(try Data(contentsOf: emptyStale.local.appendingPathComponent("phrases.tsv")).isEmpty, "Empty local file retained")
    try untouched(emptyStale.local, emptyStale.folder)

    let ownProtected = try scenario("invalid-local-own-protected")
    try write(alpha, localFile(ownProtected.local))
    try write(beta, remoteFile(ownProtected.folder, beta))
    let ownProtectedBytes = try snapshot([chosen])
    try write(ownProtectedBytes, snapshotURL(ownProtected.folder, deviceA))
    try write(Data("broken".utf8), ownProtected.local.appendingPathComponent("phrases.tsv"))
    try rejects("Local corruption blocks replacement of valid own snapshot") { _ = try run(ownProtected.local, ownProtected.folder) }
    try check(try Data(contentsOf: snapshotURL(ownProtected.folder, deviceA)) == ownProtectedBytes, "Valid own snapshot retained when local phrases corrupt")
    try check(!fm.fileExists(atPath: remoteFile(ownProtected.folder, alpha).path), "Local corruption blocks dictionary publication")
    try check(!fm.fileExists(atPath: localFile(ownProtected.local, "sync-" + DictionarySync.digest(beta) + ".tsv").path), "Local corruption blocks dictionary import")

    let nonRegularPhrases = try scenario("local-phrases-directory")
    try write(alpha, localFile(nonRegularPhrases.local))
    try fm.createDirectory(at: nonRegularPhrases.local.appendingPathComponent("phrases.tsv"), withIntermediateDirectories: false)
    try rejects("Existing local phrases must be a readable regular file") { _ = try run(nonRegularPhrases.local, nonRegularPhrases.folder) }
    try untouched(nonRegularPhrases.local, nonRegularPhrases.folder)

    let boundaryRow = SyncPhrase(code: String(repeating: "a", count: 32), text: String(repeating: "字", count: 170) + "ab")
    let formats: [(Data, [SyncPhrase])] = [
        (diskBytes, diskRows),
        (Data(String(data: diskBytes, encoding: .utf8)!.replacingOccurrences(of: "\n", with: "\r\n").utf8), diskRows),
        (Data(diskBytes.dropLast()), diskRows),
        (Data(), []),
        (Data("space\t leading and trailing \n".utf8), [SyncPhrase(code: "space", text: " leading and trailing ")]),
        (try CommonPhrase.encode([CommonPhrase(code: boundaryRow.code, text: boundaryRow.text)]), [boundaryRow])
    ]
    for (index, format) in formats.enumerated() {
        let test = try scenario("valid-local-format-\(index)")
        let file = test.local.appendingPathComponent("phrases.tsv")
        try write(format.0, file)
        let result = try run(test.local, test.folder, phrases: format.1)
        try check(result.phrases == format.1 && result.conflicts.isEmpty, "Valid local file agrees canonically with caller")
        try check(try Data(contentsOf: file) == format.0, "Validation preserves original local phrase formatting")
        try check(try snapshotRows(snapshotURL(test.folder, deviceA)) == format.1, "Current validated local phrases published")
    }

    // A self-cancelled detached task checks the parent's execution model without
    // races/timing assumptions or touching UI, user folders or cloud services.
    let cancellation = try scenario("cancellation")
    try write(alpha, localFile(cancellation.local))
    let probe = SyncCancellationProbe()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached(priority: .utility) {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            _ = try DictionarySync.run(local: cancellation.local, folder: cancellation.folder, deviceID: deviceA,
                phrases: [], ignoredDictionaries: [], ignoredPhraseCodes: [], ignoredVariants: [])
            probe.finish(false)
        } catch is CancellationError { probe.finish(true) }
        catch { probe.finish(false) }
        semaphore.signal()
    }
    try check(semaphore.wait(timeout: .now() + 10) == .success && probe.cancelled(), "Detached task cancellation propagates")
    try check(!fm.fileExists(atPath: cancellation.folder.appendingPathComponent("LexiIME-Open-Sync").path), "Cancellation leaves destination untouched")
    return checks
}

private final class SyncCancellationProbe {
    private let lock = NSLock()
    private var value = false
    func finish(_ cancelled: Bool) { lock.lock(); defer { lock.unlock() }; value = cancelled }
    func cancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
