import AVFoundation
import AppKit
import Combine
import MovieCore
import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable {
    case small = "Small previews", large = "Large previews", list = "List", detail = "Details"
    var symbol: String { switch self { case .small: return "square.grid.3x3"; case .large: return "square.grid.2x2"; case .list: return "list.bullet"; case .detail: return "list.bullet.rectangle" } }
    var columns: [GridItem] {
        let n = self == .small ? 3 : self == .large ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: n)
    }
    var isRow: Bool { self == .list || self == .detail }
}

enum LeftTab: String, CaseIterable {
    case media = "Media", files = "Files", titles = "Titles", overlays = "Overlays", audio = "Audio", transitions = "Transitions"
    case effects = "Effects", color = "Color", templates = "Templates", smart = "Smart"

    var symbol: String {
        switch self {
        case .media: return "photo.on.rectangle.angled"
        case .files: return "folder"
        case .titles: return "textformat"
        case .overlays: return "sparkle.magnifyingglass"
        case .audio: return "waveform"
        case .transitions: return "arrow.left.arrow.right.square"
        case .effects: return "wand.and.sparkles"
        case .color: return "paintpalette"
        case .templates: return "square.grid.2x2"
        case .smart: return "brain.head.profile"
        }
    }
}

enum RightTab: String, CaseIterable {
    case assistant = "Assistant", adjust = "Adjust", effects = "Effects", inspector = "Inspector"
    var symbol: String {
        switch self {
        case .assistant: return "sparkles"
        case .adjust: return "slider.horizontal.3"
        case .effects: return "wand.and.sparkles"
        case .inspector: return "info.circle"
        }
    }
}

enum MediaFilter: String, CaseIterable { case all = "All", favorites = "Favorites", recent = "Recent", videos = "Videos", photos = "Photos", audio = "Audio", unused = "Unused" }

enum InfoTarget: Identifiable, Equatable {
    case asset(UUID), clip(UUID)
    var id: String { switch self { case .asset(let u): return "a\(u)"; case .clip(let u): return "c\(u)" } }
}

/// A request to let the user mark parts of their videos (offline mode).
extension ScriptDraft: Identifiable { public var id: String { title + logline } }

struct SelectionRequest: Identifiable {
    let id = UUID()
    let reason: String
    let assetIDs: [UUID]
}

struct PendingQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [AskOption]
    let allowText: Bool
}

struct ImportJob: Identifiable {
    let id = UUID()
    let name: String
    var step = 0            // 0 reading, 1 thumbnail, 2 waveform, 3 done
    var failure: String?
}

/// Slider values being dragged; committed as one command on release (one undo step, one rebuild).
struct Draft {
    var volume = 1.0, fadeIn = 0.0, fadeOut = 0.0          // fades in seconds
    var opacity = 1.0, scale = 1.0, offsetX = 0.0, offsetY = 0.0
    var style = TextStyle()
    var transitionSeconds = 0.5
    var transitionType = TransitionType.crossfade
    var speed = 1.0
    var look = Look()
    var keyRotation = 0.0
}

@MainActor
final class AppModel: ObservableObject {
    let editor = Editor()
    let player = AVPlayer()
    @Published var thumbnails: [UUID: CGImage] = [:]
    @Published var waveforms: [UUID: [Float]] = [:]
    @Published var selection: UUID? { didSet { if selection != nil { selectedTransition = nil }; loadDraft() } }
    @Published var selectedTransition: UUID? { didSet { if selectedTransition != nil { selection = nil }; loadDraft() } }
    @Published var draft = Draft()
    @Published var leftTab = LeftTab.media
    @Published var rightTab = RightTab.assistant
    @Published var mediaFilter = MediaFilter.all
    @Published var viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .large { didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") } }
    @Published var navExpanded = UserDefaults.standard.bool(forKey: "navExpanded") { didSet { UserDefaults.standard.set(navExpanded, forKey: "navExpanded") } }
    @Published var showLeft = true
    @Published var showRight = true
    @Published var showTimeline = true
    @Published var filesPreviewHeight = AppModel.stored("filesPreviewHeight", 250) { didSet { UserDefaults.standard.set(filesPreviewHeight, forKey: "filesPreviewHeight") } }
    @Published var leftWidth = AppModel.stored("leftWidth", 320) { didSet { UserDefaults.standard.set(leftWidth, forKey: "leftWidth") } }
    @Published var rightWidth = AppModel.stored("rightWidth", 360) { didSet { UserDefaults.standard.set(rightWidth, forKey: "rightWidth") } }
    @Published var timelineHeight = AppModel.stored("timelineHeight", 310) { didSet { UserDefaults.standard.set(timelineHeight, forKey: "timelineHeight") } }
    @Published var previewVolume = 1.0 { didSet { player.volume = Float(previewVolume) } }
    @Published var timelineScroll = ScrollPosition(x: 0, y: 0)
    var timelineOffsetX: CGFloat = 0, timelineViewportWidth: CGFloat = 900
    @Published var filmstrips: [UUID: [CGImage]] = [:]
    @Published var lastEdit = Date()
    @Published var infoTarget: InfoTarget?
    @Published var renameTarget: Asset?
    @Published var rampSheet = false
    @Published var templateToApply: EditTemplate?
    @Published var matchCuts: [MatchCut] = []
    @Published var matchStatus: String?
    @Published var ghost: Editor?                 // a copy of the timeline Claude works on until you accept it
    @Published var ghostRange: ClosedRange<Ms>?
    @Published var ghostPreview = false { didSet { rebuild(playbackProject) } }
    @Published var pendingQuestion: PendingQuestion?
    @Published var pendingSelection: SelectionRequest?
    @Published var pendingScript: ScriptDraft?
    @Published var scriptLevel = ScriptLevel(rawValue: UserDefaults.standard.string(forKey: "scriptLevel") ?? "") ?? .off { didSet { UserDefaults.standard.set(scriptLevel.rawValue, forKey: "scriptLevel"); ScriptMode.level = scriptLevel; ScriptMode.approved = false } }
    @Published var workspaceRoots: [URL] = (UserDefaults.standard.stringArray(forKey: "workspaceRoots") ?? []).map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) } { didSet { UserDefaults.standard.set(workspaceRoots.map(\.path), forKey: "workspaceRoots") } }
    private var scriptContinuation: CheckedContinuation<String, Never>?
    @Published var offlineMode = UserDefaults.standard.bool(forKey: "offlineMode") { didSet { UserDefaults.standard.set(offlineMode, forKey: "offlineMode"); Privacy.offline = offlineMode } }
    private var selectionContinuation: CheckedContinuation<String, Never>?
    private var manualSelectionDone: ((String) -> Void)?
    @Published var templateThumbs: [String: CGImage] = [:]
    @Published var lookThumbs: [String: CGImage] = [:]
    @Published var overlayFrames: [GeneratorKind: [CGImage]] = [:]
    @Published var titleThumbs: [TitlePreset: CGImage] = [:]
    @Published var musicCategory = "All"
    @Published var templateCategory = "All"
    @Published var duckDraft: Double?
    private var questionContinuation: CheckedContinuation<String, Never>?
    private var keyMonitor: Any?
    private var ghostBag = Set<AnyCancellable>()
    private var thumbsKey = ""

    static func stored(_ key: String, _ fallback: Double) -> Double { UserDefaults.standard.object(forKey: key) as? Double ?? fallback }
    @Published var importJobs: [ImportJob] = []
    @Published var importTotal = 0
    @Published var importDone = 0
    @Published var importFailures: [String] = []
    private var importQueue: [URL] = []
    private var importWorkers = 0
    private var filmstripPending = Set<UUID>()
    @Published var playhead: Ms = 0
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?    // non-modal hint, clears itself
    @Published var importing = false
    @Published var searchText = ""
    @Published var multiSelection = Set<UUID>()      // extra clips picked with shift-click, for grouping
    @Published var recording = false
    @Published var showExport = false
    @Published var exportProgress: Double?          // nil while nothing is exporting
    @Published var exportMessage: String?
    @Published var exportPreset: ExportPreset?      // nil = the movie's own canvas
    @Published var exportShortSide = 1080
    @Published var batchPresets: Set<ExportPreset> = [.youtube1080, .tiktok]
    private var exportTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var recordingStart: Ms = 0
    private var recordingURL: URL?
    var exporting: Bool { exportProgress != nil }
    @Published var autoMaking = false
    @Published var pxPerSec: Double = 80
    @Published var snapEnabled = true
    @Published var previewingID: String?
    let previewPlayer = AVPlayer()
    @Published var assetToRemove: Asset?
    @Published var transitionFrames: [TransitionType: [CGImage]] = [:]
    @Published var effectFrames: [EffectType: [CGImage]] = [:]
    @Published var effectDrafts: [UUID: Double] = [:]
    private var effectPreviewKey = ""
    private var effectPending = Set<EffectType>()
    private var previewKey = ""
    private var previewPending = Set<TransitionType>()
    @Published var documentURL: URL?
    @Published var mcpCommand: String?   // `claude mcp add ...` line, once the server is up
    private var mcpServer: MCPServer?
    private(set) var mcpToken: String?
    var mcpPort: UInt16 { Self.mcpPort }

    private var bag = Set<AnyCancellable>()
    private var buildGeneration = 0

    init(restoreRecovery restore: Bool = true, startServer: Bool = true) {
        Privacy.offline = offlineMode; ScriptMode.level = scriptLevel
        editor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        // Debounced: a batch of edits (Claude's whole edit) builds the preview once, not once per step.
        editor.$project.dropFirst().debounce(for: 0.12, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in guard let self else { return }; self.lastEdit = Date(); self.rebuild(self.playbackProject) }.store(in: &bag)
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.playhead = Ms(t.seconds * 1000)
                self.followPlayhead()
                if self.playhead >= self.editor.project.duration { self.pause() }
            }
        }
        // Recovery copy: every change is written (debounced) here; Save/Save As writes the real document.
        editor.$project.dropFirst().debounce(for: 2, scheduler: DispatchQueue.main)
            .sink { [weak self] p in self?.writeRecovery(p) }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, (n.object as? AVPlayerItem) === self.previewPlayer.currentItem else { return }
                self.previewingID = nil
            }
        }
        if restore { restoreRecovery() }
        if startServer { startMCP(); installKeyMonitor() }
        player.volume = Float(previewVolume)
    }

    // MARK: Derived state

    var project: Project { editor.project }
    var activeEditor: Editor { ghost ?? editor }          // where Claude's tools write
    var playbackProject: Project { ghostPreview ? (ghost?.project ?? project) : project }
    var frameMs: Double { 1000 / Double(max(1, project.fps)) }
    var hasVideo: Bool { project.tracks.contains { $0.kind == .video && !$0.clips.isEmpty } }
    var usedAssetIDs: Set<UUID> { Set(project.tracks.flatMap(\.clips).compactMap(\.assetID)) }
    var visibleAssets: [Asset] {
        searchText.isEmpty ? project.assets : project.assets.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }
    func isMissing(_ asset: Asset) -> Bool { !FileManager.default.fileExists(atPath: asset.url.path) }
    var anyMissing: Bool { project.assets.contains { isMissing($0) } }
    var selectedClip: Clip? { project.tracks.flatMap(\.clips).first { $0.id == selection } }
    var selectedTransitionValue: MovieCore.Transition? { project.transitions.first { $0.id == selectedTransition } }

    /// The transition a clip belongs to (as outgoing or incoming clip).
    func transition(of clipID: UUID) -> MovieCore.Transition? {
        project.transitions.first { $0.fromClip == clipID || $0.toClip == clipID }
    }

    // MARK: Messages

    func report(_ error: Error, quiet: Bool = false) {
        if quiet { status("\(error)") } else { errorMessage = "\(error)" }
    }

    func status(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if statusMessage == message { statusMessage = nil }
        }
    }

    // MARK: Documents

    var title: String { documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    private static var recoveryURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/recovery.\(Project.fileExtension)")
    }

    private func writeRecovery(_ p: Project) {
        guard let url = Self.recoveryURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? p.write(to: url)
    }

    private func restoreRecovery() {
        guard let url = Self.recoveryURL, let p = try? Project.read(from: url), !(p.assets.isEmpty && p.tracks.isEmpty) else { return }
        adopt(p)
    }

    private func adopt(_ p: Project) {
        do { try editor.replace(with: p) } catch { errorMessage = "Can't open project: \(error)"; return }
        selection = nil; selectedTransition = nil; seek(0)
        Task {
            for a in p.assets {
                thumbnails[a.id] = await a.thumbnail()
                waveforms[a.id] = await Waveform.levels(url: a.url)
            }
        }
        if !p.missingAssets.isEmpty {
            errorMessage = "Missing media: " + p.missingAssets.map(\.url.lastPathComponent).joined(separator: ", ")
        }
    }

    private var projectType: UTType { UTType(filenameExtension: Project.fileExtension) ?? .json }

    /// The project as last saved or opened; nil until then. Unsaved work is what differs from it.
    private var savedSnapshot: Project?

    var hasUnsavedWork: Bool {
        guard !(project.assets.isEmpty && project.tracks.isEmpty) else { return false }
        return project != savedSnapshot
    }

    /// Runs `proceed` right away, or after asking what to do with unsaved work (Save, Don't Save, Cancel).
    func confirmDiscard(_ proceed: () -> Void) {
        guard hasUnsavedWork else { proceed(); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(title)”?"
        alert.informativeText = "Your edits will be lost if you don't save them."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Don't Save"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); if !hasUnsavedWork { proceed() }   // a cancelled Save panel keeps the project
        case .alertSecondButtonReturn: proceed()
        default: break
        }
    }

    func newProject() { confirmDiscard { resetProject() } }

    private func resetProject() {
        try? editor.replace(with: Project())
        documentURL = nil; selection = nil; selectedTransition = nil; seek(0); thumbnails = [:]; waveforms = [:]
        savedSnapshot = project
    }

    func open() {
        confirmDiscard {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [projectType]
            if panel.runModal() == .OK, let url = panel.url { openFile(url) }
        }
    }

    func load(_ url: URL) { confirmDiscard { openFile(url) } }

    private func openFile(_ url: URL) {
        do { adopt(try Project.read(from: url)); documentURL = url; savedSnapshot = project }
        catch { errorMessage = "Can't open \(url.lastPathComponent): \(error)" }
    }

    func save() { if let url = documentURL { write(to: url) } else { saveAs() } }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [projectType]
        panel.nameFieldStringValue = "\(title).\(Project.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url { write(to: url); documentURL = url }
    }

    private func write(to url: URL) {
        do { try project.write(to: url); savedSnapshot = project } catch { errorMessage = "Save failed: \(error)" }
    }

    // MARK: MCP

    private static let mcpPort: UInt16 = 39_127

    private func startMCP() {
        Task {
            do {
                let token = try MCPServer.loadOrCreateToken()
                let server = MCPServer(
                    editorProvider: { [unowned self] in self.activeEditor },
                    host: MCPHost(importMedia: { [unowned self] in try await self.importAsset($0) },
                                  playhead: { [unowned self] in self.playhead },
                                  ask: { [unowned self] question, options, allowText in await self.ask(question, options, allowText) },
                                  pickRanges: { [unowned self] reason, ids in await self.pickRanges(reason, ids) },
                                  reviewScript: { [unowned self] draft in await self.reviewScript(draft) },
                                  workspaceRoots: { [unowned self] in self.workspaceRoots }),
                    token: token, port: Self.mcpPort)
                try await server.start()
                mcpServer = server
                mcpToken = token
                mcpCommand = "claude mcp add --transport http movie-maker http://127.0.0.1:\(Self.mcpPort)/mcp --header \"Authorization: Bearer \(token)\""
            } catch { errorMessage = "Claude link unavailable (port \(Self.mcpPort) in use?): \(error)" }
        }
    }

    func copyClaudeCommand() {
        guard let cmd = mcpCommand else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string)
        errorMessage = "Command copied. Paste it in a terminal once to connect Claude Code to this editor."
    }

    // MARK: Editing

    func perform(_ command: Command, quiet: Bool = false) {
        do { try editor.apply(command) } catch { report(error, quiet: quiet) }
    }

    /// Registers the file (re-using the entry if it is already in the bin), then fills in thumbnail and waveform.
    @discardableResult
    func importAsset(_ url: URL, job: UUID? = nil) async throws -> Asset {
        func step(_ n: Int) { if let i = importJobs.firstIndex(where: { $0.id == job }) { importJobs[i].step = n } }
        if let existing = project.assets.first(where: { $0.url == url }) { return existing }
        let asset = try await Asset.load(url: url)
        try editor.apply(.addAsset(asset)); step(1)
        if let ghost, !ghost.project.assets.contains(where: { $0.id == asset.id }) { try? ghost.apply(.addAsset(asset)) }   // a ghost edit can use it too
        thumbnails[asset.id] = await asset.thumbnail(); step(2)
        waveforms[asset.id] = await Waveform.levels(url: url); step(3)
        return asset
    }

    /// Files dragged from the Files tab ("files:" + newline-separated paths); folders bring their media.
    func importDropped(_ payload: String) {
        var urls: [URL] = []
        for path in payload.split(separator: "\n").map(String.init) {
            let url = URL(fileURLWithPath: path)
            if Workspace.isFolder(url) { urls += Workspace.mediaFiles(in: url) } else if Workspace.kind(url) != nil { urls.append(url) }
        }
        if !urls.isEmpty { importFiles(urls) }
    }

    func importFiles(_ dropped: [URL]) {
        let urls = dropped.flatMap { Workspace.isFolder($0) ? Workspace.mediaFiles(in: $0) : [$0] }   // a dragged folder brings its media
            .filter { url in !importQueue.contains(url) && !project.assets.contains { $0.url == url } }
        guard !urls.isEmpty else { return }
        importTotal += urls.count; importQueue += urls
        while importWorkers < 3 && !importQueue.isEmpty { importWorkers += 1; Task { await importWorker() } }   // a few at a time, so 200 files don't stall the app
    }

    private func importWorker() async {
        while !importQueue.isEmpty {
            let url = importQueue.removeFirst()
            let job = ImportJob(name: url.lastPathComponent)
            importJobs.append(job)
            do { try await importAsset(url, job: job.id) } catch { importFailures.append("\(url.lastPathComponent): \(error)") }
            importJobs.removeAll { $0.id == job.id }
            importDone += 1
        }
        importWorkers -= 1
        if importWorkers == 0 { importTotal = 0; importDone = 0 }
    }

    func cancelImports() { importTotal -= importQueue.count; importQueue = [] }

    /// Timeline thumbnails are made when a clip first needs them, not for every imported file.
    func ensureFilmstrip(_ asset: Asset) {
        guard filmstrips[asset.id] == nil, filmstripPending.insert(asset.id).inserted else { return }
        Task { filmstrips[asset.id] = await Self.filmstrip(asset); filmstripPending.remove(asset.id) }
    }

    func addToTimeline(_ asset: Asset) {
        do { try editor.addClip(asset: asset) } catch { report(error) }
    }

    func addTitle(_ preset: TitlePreset = .center, at start: Ms? = nil) {
        do {
            let clip = try editor.addTitle(preset.text, start: start ?? playhead)
            try editor.apply(.setTextStyle(clip.id, preset.style))
            selection = clip.id
        } catch { report(error, quiet: true) }
    }

    func addSoundEffect(_ name: String, at start: Ms? = nil, track: UUID? = nil) {
        Task {
            do {
                let asset = try await importAsset(SoundEffects.url(for: name))
                selection = try editor.addClip(asset: asset, start: start ?? playhead, track: track).id
            } catch { report(error, quiet: true) }
        }
    }

    /// Plays or stops a sound preview (a local file, or an online preview streamed from its URL).
    func togglePreview(id: String, url: @escaping @Sendable () async throws -> URL) {
        if previewingID == id { previewPlayer.pause(); previewingID = nil; return }
        previewingID = id
        pause()
        Task {
            do {
                let resolved = try await url()
                guard previewingID == id else { return }
                previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: resolved))
                previewPlayer.play()
            } catch { previewingID = nil; report(error, quiet: true) }
        }
    }

    func addMusic(_ name: String) {
        Task {
            do {
                let url = try await Task.detached { try MusicLibrary.url(for: name) }.value
                let asset = try await importAsset(url)
                selection = try editor.addMusicBed(asset, start: playhead).id
            } catch { report(error, quiet: true) }
        }
    }

    /// Downloads an online sound (credit is recorded) and puts it on the timeline at the playhead.
    func addOnline(_ sound: OnlineSound, music: Bool) async {
        do {
            let file = try await OnlineLibrary.download(sound)
            let asset = try await importAsset(file)
            selection = music ? try editor.addMusicBed(asset, start: playhead).id : try editor.addClip(asset: asset, start: playhead).id
            if sound.needsCredit { status("Added. This sound needs a credit: use \"Copy credits\" for the description.") }
        } catch { report(error, quiet: true) }
    }

    /// Credit lines for downloaded sounds that are used in this project and need attribution.
    func creditsText() -> String {
        let used = Set(project.assets.map { $0.url.lastPathComponent })
        return OnlineLibrary.creditsText(for: OnlineLibrary.credits().filter { used.contains(OnlineLibrary.localFileName(for: $0)) })
    }

    func setFormat(width: Int, height: Int, fps: Int? = nil) {
        perform(.setFormat(width: width, height: height, fps: fps ?? project.fps), quiet: true)
    }

    func addLayer() {
        do { _ = try editor.addTrack(.video, onTop: true); status("New video layer added on top. Drop clips onto it.") }
        catch { report(error) }
    }

    func removeTrack(_ id: UUID) { perform(.removeTrack(id)) }

    func splitAtPlayhead() {
        let clips = project.tracks.flatMap(\.clips)
        let target = clips.first { $0.id == selection && $0.start < playhead && playhead < $0.end }
            ?? clips.first { $0.start < playhead && playhead < $0.end }
        if let target { perform(.splitClip(target.id, at: playhead), quiet: true) }
    }

    func detachAudioOfSelection() {
        guard let id = selection else { return }
        do { try editor.detachAudio(id) } catch { report(error, quiet: true) }
    }

    func duplicateSelection() {
        guard let id = selection else { return }
        do { selection = try editor.duplicate(id).id } catch { report(error, quiet: true) }
    }

    /// Deletes the clip and moves later clips on its track earlier to close the gap.
    func rippleDeleteSelection() {
        guard let id = selection else { return }
        perform(.rippleRemove(id), quiet: true); selection = nil
    }

    func setTrack(_ track: Track, muted: Bool? = nil, hidden: Bool? = nil) {
        perform(.setTrackFlags(track.id, muted: muted ?? track.muted, hidden: hidden ?? track.hidden), quiet: true)
    }

    /// Removes a file from the library; asks first when clips use it.
    func requestRemove(_ asset: Asset) {
        if usedAssetIDs.contains(asset.id) { assetToRemove = asset } else { removeAsset(asset) }
    }

    func removeAsset(_ asset: Asset) {
        perform(.removeAsset(asset.id))
        thumbnails[asset.id] = nil; waveforms[asset.id] = nil
        if selectedClip == nil { selection = nil }
        assetToRemove = nil
    }

    func zoomToFit(width: Double) {
        let seconds = max(1, Double(project.duration) / 1000)
        pxPerSec = min(400, max(10, (width - 160) / seconds))
    }

    /// Previews of every transition are rendered once with the real renderer, then looped.
    func ensurePreview(_ type: TransitionType) {
        let videos = project.assets.filter(\.hasVideo)
        let key = videos.prefix(2).map(\.id.uuidString).joined()
        if key != previewKey { previewKey = key; transitionFrames = [:]; previewPending = [] }
        guard transitionFrames[type] == nil, !previewPending.contains(type) else { return }
        previewPending.insert(type)
        let a = videos.first.flatMap { thumbnails[$0.id] }
        let b = videos.dropFirst().first.flatMap { thumbnails[$0.id] } ?? a
        Task.detached(priority: .utility) {
            let frames = TransitionRenderer.previewFrames(type, a: a, b: b)
            await MainActor.run { [weak self] in
                guard let self, self.previewKey == key else { return }
                self.transitionFrames[type] = frames
            }
        }
    }

    func ensureEffectPreview(_ type: EffectType) {
        let first = project.assets.first(where: \.hasVideo)
        let key = first?.id.uuidString ?? ""
        if key != effectPreviewKey { effectPreviewKey = key; effectFrames = [:]; effectPending = [] }
        guard effectFrames[type] == nil, !effectPending.contains(type) else { return }
        effectPending.insert(type)
        let source = first.flatMap { thumbnails[$0.id] }
        Task.detached(priority: .utility) {
            let frames = EffectRenderer.previewFrames(type, source: source)
            await MainActor.run { [weak self] in
                guard let self, self.effectPreviewKey == key else { return }
                self.effectFrames[type] = frames
            }
        }
    }

    func addEffect(_ type: EffectType, to clipID: UUID) {
        perform(.addEffect(clipID, Effect(type)), quiet: true)
        selection = clipID
    }

    func setEffectAmount(_ effect: Effect, on clipID: UUID, amount: Double) {
        var changed = effect; changed.amount = amount
        perform(.addEffect(clipID, changed), quiet: true)
        effectDrafts[effect.id] = nil
    }

    func removeEffect(_ effect: Effect, from clipID: UUID) { perform(.removeEffect(clipID, effect: effect.id), quiet: true) }

    /// Plain click selects one clip; shift-click adds clips (for Group).
    /// Selecting a transition also opens Adjust, where its style and length are.
    func selectTransition(_ id: UUID) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedTransition = id
        rightTab = .adjust; showRight = true
    }

    func clickClip(_ id: UUID, shift: Bool) {
        NSApp.keyWindow?.makeFirstResponder(nil)   // a focused chat box would swallow Delete

        if shift, selection != nil, selection != id { multiSelection.formSymmetricDifference([id]) }
        else { multiSelection = []; selection = id }
    }

    func groupSelection() {
        let ids = Array(multiSelection.union(selection.map { [$0] } ?? []))
        guard ids.count >= 2 else { status("Shift-click a second clip, then press Group."); return }
        perform(.group(ids), quiet: true); multiSelection = []
    }

    func ungroupSelection() {
        guard let id = selection else { return }
        perform(.ungroup(id), quiet: true)
    }

    func setLocked(_ track: Track, _ locked: Bool) { perform(.setTrackLocked(track.id, locked), quiet: true) }
    func setDuck(_ track: Track, _ duck: Bool) {
        perform(.setTrackDuck(track.id, duck), quiet: true)
        if duck { status("Ducking on: this track's volume dips while other sound (speech, clip sound) plays.") }
    }

    /// Picture-in-picture: the file on a new top layer, small, in the upper right corner.
    func addOverlay(_ asset: Asset) {
        do {
            try editor.transaction {
                let track = try editor.addTrack(.video, onTop: true)
                let clip = try editor.addClip(asset: asset, start: playhead, track: track)
                try editor.apply(.setTransform(clip.id, opacity: 1, scale: 0.35, offsetX: 0.3, offsetY: 0.28))
                selection = clip.id
            }
        } catch { report(error, quiet: true) }
    }

    func addSticker(_ emoji: String, at start: Ms? = nil) {
        do { selection = try editor.addSticker(emoji, start: start ?? playhead).id } catch { report(error, quiet: true) }
    }

    /// Finds the file for a missing asset yourself.
    func relink(_ asset: Asset) {
        let panel = NSOpenPanel()
        panel.message = "Find \(asset.label)"
        panel.allowedContentTypes = asset.isStill ? [.image] : (asset.hasVideo ? [.movie] : [.audio])
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await relink(asset, to: url) }
    }

    private func relink(_ asset: Asset, to url: URL) async {
        do {
            let fresh = try await Asset.load(url: url)
            try editor.relink(asset.id, to: fresh)
            thumbnails[asset.id] = await fresh.thumbnail(); waveforms[asset.id] = await Waveform.levels(url: fresh.url)
        } catch { report(error, quiet: true) }
    }

    /// Pick a folder; every missing file found there (by name, also in sub-folders) is reconnected.
    func locateMissing() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose the folder where your media files are now"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let missing = project.assets.filter { isMissing($0) }
        Task {
            var found = 0
            let names = Dictionary(uniqueKeysWithValues: missing.map { ($0.name ?? $0.url.lastPathComponent, $0) })
            var matches: [(Asset, URL)] = []
            if let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                var seen = 0
                for case let file as URL in walker {
                    seen += 1; if seen > 50_000 { break }
                    if let asset = names[file.lastPathComponent] { matches.append((asset, file)) }
                }
            }
            for (asset, file) in matches { await relink(asset, to: file); found += 1 }
            status(found == 0 ? "None of the missing files were in that folder." : "Reconnected \(found) of \(missing.count) missing files.")
        }
    }

    func deleteSelection() {
        if let id = selection { perform(.removeClip(id)); selection = nil }
        else if let id = selectedTransition { perform(.removeTransition(id)); selectedTransition = nil }
    }

    /// Transition between a clip and the clip that starts exactly where it ends.
    func addTransition(_ type: TransitionType, after clipID: UUID) {
        do { try editor.addTransition(after: clipID, type: type) } catch { report(error, quiet: true) }
    }

    /// Handles something dropped on the timeline. `trackIndex` is nil below the last track.
    func handleDrop(_ payload: String, at time: Ms, trackIndex: Int?) -> Bool {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let track = trackIndex.flatMap { project.tracks.indices.contains($0) ? project.tracks[$0] : nil }
        let time = max(0, time)
        switch parts[0] {
        case "files":
            importDropped(parts[1]); return true
        case "asset":
            guard let id = UUID(uuidString: parts[1]), let asset = project.assets.first(where: { $0.id == id }) else { return false }
            let fits = track.map { $0.kind == (asset.hasVideo ? .video : .audio) } ?? false
            do { selection = try editor.addClip(asset: asset, start: time, track: fits ? track?.id : nil).id }
            catch { report(error, quiet: true) }
        case "music":
            addMusic(parts[1])
        case "sticker":
            addSticker(parts[1], at: time)
        case "overlay":
            guard let kind = GeneratorKind(rawValue: parts[1]) else { return false }
            addOverlayKind(kind, at: time)
        case "sfx":
            addSoundEffect(parts[1], at: time, track: track?.kind == .audio ? track?.id : nil)
        case "title":
            addTitle(TitlePreset(rawValue: parts[1]) ?? .center, at: time)
        case "effect":
            guard let type = EffectType(rawValue: parts[1]) else { return false }
            guard let track, track.kind == .video, let clip = track.clips.first(where: { $0.start <= time && time < $0.end }) else {
                status("Drop an effect on a video clip.")
                return false
            }
            addEffect(type, to: clip.id)
        case "transition":
            guard let type = TransitionType(rawValue: parts[1]) else { return false }
            guard let track, let clip = track.clips.first(where: { $0.start <= time && time < $0.end }) else {
                status("Drop a transition on a clip.")
                return false
            }
            if time >= clip.start + clip.duration / 2 {
                addTransition(type, after: clip.id)       // right half: transition into the next clip
            } else if let previous = track.clips.first(where: { $0.end == clip.start }) {
                addTransition(type, after: previous.id)   // left half: from the previous clip
            } else {
                status("There is no clip touching the start of this one.")
            }
        default: return false
        }
        return true
    }

    // MARK: Inspector drafts

    private func loadDraft() {
        if let c = selectedClip {
            draft.volume = c.volume; draft.fadeIn = Double(c.fadeIn) / 1000; draft.fadeOut = Double(c.fadeOut) / 1000
            draft.opacity = c.opacity; draft.scale = c.scale; draft.offsetX = c.offsetX; draft.offsetY = c.offsetY
            draft.style = c.style; draft.speed = c.speed; draft.look = c.look
            if let k = Keyframe.interpolate(c.keyframes, at: Double(playhead - c.start)) {   // animated: show the values at the playhead
                draft.opacity = k.opacity; draft.scale = k.scale; draft.offsetX = k.offsetX; draft.offsetY = k.offsetY; draft.keyRotation = k.rotation
            }
        }
        if let t = selectedTransitionValue { draft.transitionSeconds = Double(t.duration) / 1000; draft.transitionType = t.type }
    }

    func commitAudio() {
        guard let c = selectedClip else { return }
        let fadeIn = min(Ms(draft.fadeIn * 1000), c.duration)
        let fadeOut = min(Ms(draft.fadeOut * 1000), c.duration - fadeIn)
        perform(.setVolume(c.id, volume: draft.volume, fadeIn: fadeIn, fadeOut: fadeOut), quiet: true)
        loadDraft()
    }

    func commitSpeed() {
        guard let c = selectedClip else { return }
        perform(.setSpeed(c.id, draft.speed), quiet: true)
        loadDraft()
    }

    func commitLook() {
        guard let c = selectedClip else { return }
        perform(.setLook(c.id, draft.look), quiet: true)
        loadDraft()
    }

    func applyLookPreset(_ name: String) {
        guard var l = Look.preset(name) else { return }
        l.flipX = draft.look.flipX; l.flipY = draft.look.flipY; l.rotation = draft.look.rotation   // keep geometry
        draft.look = l
        commitLook()
    }

    /// Stores the current Picture values (opacity, size, position, rotation) as a keyframe at the playhead.
    func setKeyframeAtPlayhead() {
        guard let c = selectedClip else { return }
        let t = min(max(0, playhead - c.start), c.duration)
        var frames = c.keyframes.filter { $0.time != t }
        frames.append(Keyframe(time: t, opacity: draft.opacity, scale: draft.scale, offsetX: draft.offsetX, offsetY: draft.offsetY, rotation: draft.keyRotation))
        perform(.setKeyframes(c.id, frames), quiet: true)
    }

    func removeKeyframe(at time: Ms) {
        guard let c = selectedClip else { return }
        perform(.setKeyframes(c.id, c.keyframes.filter { $0.time != time }), quiet: true)
    }

    func toggleKeyframeSmooth(at time: Ms) {
        guard let c = selectedClip else { return }
        perform(.setKeyframes(c.id, c.keyframes.map { var k = $0; if k.time == time { k.smooth.toggle() }; return k }), quiet: true)
    }

    func jumpToKeyframe(_ k: Keyframe) {
        guard let c = selectedClip else { return }
        seek(c.start + k.time)
    }

    func removeSilenceOfSelection() {
        guard let c = selectedClip, let asset = project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { return }
        status("Looking for silences…")
        Task {
            do {
                let ranges = try await AudioTools.silences(of: asset, sourceIn: c.sourceIn, length: c.sourceLength)
                guard !ranges.isEmpty else { status("No silences found."); return }
                let removed = try editor.removeSilences(of: c.id, ranges: ranges)
                selection = nil
                status("Removed \(String(format: "%.1f", Double(removed) / 1000)) s of silence in \(ranges.count) places.")
            } catch { report(error, quiet: true) }
        }
    }

    func normalizeSelection() {
        guard let c = selectedClip, let asset = project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { return }
        Task {
            do {
                guard let gain = try await AudioTools.normalizedVolume(of: asset, sourceIn: c.sourceIn, length: c.sourceLength) else { status("No usable sound in this clip."); return }
                perform(.setVolume(c.id, volume: gain, fadeIn: c.fadeIn, fadeOut: c.fadeOut), quiet: true)
                loadDraft(); status("Volume set to \(String(format: "%.2f", gain)).")
            } catch { report(error, quiet: true) }
        }
    }

    func reduceNoiseOfSelection() {
        guard let c = selectedClip, let asset = project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { return }
        status("Cleaning the sound…")
        Task {
            do {
                let cleaned = try await importAsset(try await AudioTools.reduceNoise(of: asset))
                try editor.useCleanedAudio(of: c.id, cleaned: cleaned)
                status("Sound cleaned. The original file is untouched (undo to go back).")
            } catch { report(error) }
        }
    }

    func autoCaptionsOfSelection() {
        guard let c = selectedClip, let asset = project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { return }
        status("Listening to the speech…")
        Task {
            do {
                let count = try editor.addCaptions(for: c.id, phrases: try await Transcriber.phrases(url: asset.url))
                status(count == 0 ? "No speech found in this clip." : "Added \(count) subtitles on the Captions track.")
            } catch { report(error) }
        }
    }

    // MARK: Voice-over

    func toggleVoiceOver() { recording ? stopVoiceOver() : startVoiceOver() }

    private func startVoiceOver() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                errorMessage = "Microphone access is off. Turn it on for Lumacut in System Settings > Privacy & Security > Microphone."
                return
            }
            do {
                let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("MovieMaker/Recordings", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("Voice-over \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")).m4a")
                let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                                                                 AVEncoderBitRateKey: 128_000])
                guard r.record() else { throw EditError.invalid("The microphone could not start.") }
                recorder = r; recordingURL = url; recordingStart = playhead; recording = true
                play()   // you watch the movie while you speak
                status("Recording… press the microphone again to stop. Use headphones so the movie's sound isn't recorded.")
            } catch { report(error) }
        }
    }

    private func stopVoiceOver() {
        recorder?.stop(); recorder = nil; recording = false; pause()
        guard let url = recordingURL else { return }
        Task {
            do {
                let asset = try await importAsset(url)
                selection = try editor.addClip(asset: asset, start: recordingStart).id
                status("Voice-over added at \(formatTime(recordingStart)).")
            } catch { report(error) }
        }
    }

    // MARK: Export

    /// Exports one file with the chosen preset or quality.
    func startExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(title).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pause()
        let settings = exportPreset?.settings ?? ExportSettings.profile(project, shortSide: exportShortSide)
        runExport {
            try await Exporter.export(self.project, to: url, settings: settings) { p in Task { @MainActor in self.exportProgress = p } }
            self.exportMessage = "Saved \(url.lastPathComponent) (\(settings.width)×\(settings.height))."
        }
    }

    /// One file per ticked preset, in a folder you choose.
    func startBatchExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Choose the folder for the exported files"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        pause()
        let presets = ExportPreset.allCases.filter { batchPresets.contains($0) }
        guard !presets.isEmpty else { exportMessage = "Tick at least one format."; return }
        runExport {
            let files = try await Exporter.exportBatch(self.project, presets: presets, into: folder, name: self.title) { preset, p in
                Task { @MainActor in self.exportProgress = p; self.exportMessage = "Exporting \(preset.title)…" }
            }
            self.exportMessage = "Saved \(files.count) files in \(folder.lastPathComponent)."
        }
    }

    private func runExport(_ body: @escaping () async throws -> Void) {
        exportProgress = 0; exportMessage = nil
        exportTask = Task {
            do { try await body() }
            catch is CancellationError { exportMessage = "Export cancelled." }
            catch { exportMessage = "Export failed: \(error.localizedDescription)" }
            exportProgress = nil; exportTask = nil
        }
    }

    func cancelExport() { exportTask?.cancel() }

    func exportSubtitles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(title).srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = Subtitles.srt(project)
        guard !text.isEmpty else { exportMessage = "There are no titles or captions to export."; return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); exportMessage = "Saved \(url.lastPathComponent)." }
        catch { exportMessage = "Could not save: \(error.localizedDescription)" }
    }

    // MARK: Project settings and templates

    func setResolution(shortSide: Int) {
        let s = ExportSettings.profile(project, shortSide: shortSide)
        setFormat(width: s.width, height: s.height)
    }

    func duplicateProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [projectType]
        panel.nameFieldStringValue = "\(title) copy.\(Project.fileExtension)"
        panel.message = "Save a copy of this project"
        if panel.runModal() == .OK, let url = panel.url { do { try project.write(to: url); status("Saved a copy.") } catch { report(error) } }
    }

    static let builtInTemplates: [(name: String, width: Int, height: Int)] = [
        ("YouTube video (16:9)", 1920, 1080), ("Vertical short: TikTok, Reels, Shorts (9:16)", 1080, 1920),
        ("Instagram portrait (4:5)", 1080, 1350), ("Square (1:1)", 1080, 1080)]

    static var templatesFolder: URL? {
        let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/Templates", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    var userTemplates: [URL] {
        ((Self.templatesFolder.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }) ?? [])
            .filter { $0.pathExtension == Project.fileExtension }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func newProject(width: Int, height: Int) { confirmDiscard { resetProject(); setFormat(width: width, height: height); savedSnapshot = project } }

    func newProject(fromTemplate url: URL) {
        confirmDiscard {
            do { adopt(try Project.read(from: url)); documentURL = nil; savedSnapshot = nil } catch { report(error) }
        }
    }

    func saveAsTemplate() {
        guard let dir = Self.templatesFolder else { return }
        var url = dir.appendingPathComponent("\(title).\(Project.fileExtension)"), n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("\(title) \(n).\(Project.fileExtension)"); n += 1 }
        do { try project.write(to: url); status("Saved as template “\(url.deletingPathExtension().lastPathComponent)”. Find it under File > New from Template.") }
        catch { report(error) }
    }

    func commitTransform() {
        guard let c = selectedClip else { return }
        if c.keyframes.isEmpty {
            perform(.setTransform(c.id, opacity: draft.opacity, scale: draft.scale, offsetX: draft.offsetX, offsetY: draft.offsetY), quiet: true)
        } else {
            setKeyframeAtPlayhead()   // an animated clip: changing a slider sets the keyframe at the playhead
        }
        loadDraft()
    }

    func commitStyle() {
        guard let c = selectedClip else { return }
        perform(.setTextStyle(c.id, draft.style), quiet: true)
        loadDraft()
    }

    func commitTransition() {
        guard let t = selectedTransitionValue else { return }
        perform(.setTransition(t.id, type: draft.transitionType, duration: max(1, Ms(draft.transitionSeconds * 1000))), quiet: true)
        loadDraft()
    }

    /// Longest overlap the selected transition can have (just under the shorter clip).
    var maxTransitionSeconds: Double {
        guard let t = selectedTransitionValue else { return 1 }
        let clips = project.tracks.flatMap(\.clips)
        guard let f = clips.first(where: { $0.id == t.fromClip }), let to = clips.first(where: { $0.id == t.toClip }) else { return 1 }
        return Double(max(200, min(f.duration, to.duration) - 100)) / 1000
    }

    // MARK: Auto movie, export

    /// Highlight reel from every video in the bin; a long audio-only asset (> 20 s, so not an effect) is the music.
    func autoMovie(seconds: Int) {
        let videos = project.assets.filter(\.hasVideo)
        let music = project.assets.first { !$0.hasVideo && $0.duration > 20_000 }
        autoMaking = true
        Task {
            defer { autoMaking = false }
            do {
                let plan = try await AutoMovie.plan(videos: videos, options: AutoMovieOptions(targetMs: Ms(seconds) * 1000, music: music))
                try plan.apply(to: editor)
                seek(0)
            } catch { errorMessage = "Auto movie failed: \(error)" }
        }
    }

    // MARK: Keyboard, scrubbing, following the playhead

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleKey(event) ? nil : event }
        }
    }

    /// Plain keys (no command/option/control) work on the timeline unless you are typing in a field or a sheet is open.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !(NSApp.keyWindow?.firstResponder is NSText), NSApp.keyWindow?.attachedSheet == nil else { return false }
        let shift = e.modifierFlags.contains(.shift)
        switch e.keyCode {
        case 49: togglePlay()                                                      // space
        case 123: step(by: shift ? -1000 : -frameMs)                               // left: one frame, shift: one second
        case 124: step(by: shift ? 1000 : frameMs)
        case 126: jumpToEdit(forward: false)                                       // up / down: previous / next cut
        case 125: jumpToEdit(forward: true)
        case 51, 117: shift ? rippleDeleteSelection() : deleteSelection()          // delete
        case 115: seek(0)                                                          // home
        case 119: seek(playbackProject.duration)                                   // end
        default:
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "s": splitAtPlayhead()
            case "i": seek(max(0, playhead))
            default: return false
            }
        }
        return true
    }

    func step(by ms: Double) {
        if isPlaying { pause() }
        seek(Ms((Double(playhead) + ms).rounded()))
    }

    func jumpToEdit(forward: Bool) {
        let edges = Set(project.tracks.flatMap(\.clips).flatMap { [$0.start, $0.end] } + [0, project.duration])
        if let target = forward ? edges.filter({ $0 > playhead + 1 }).min() : edges.filter({ $0 < playhead - 1 }).max() { pause(); seek(target) }
    }

    /// Scroll wheel / trackpad over the preview scrubs through the movie.
    func scrub(by ms: Double) {
        if isPlaying { pause() }
        seek(Ms((Double(playhead) + ms).rounded()))
    }

    /// Keeps the playhead in view while the movie plays or you scrub.
    func followPlayhead() {
        let x = CGFloat(Double(playhead) * pxPerSec / 1000)
        if x > timelineOffsetX + timelineViewportWidth * 0.92 || x < timelineOffsetX {
            timelineScroll.scrollTo(x: max(0, x - timelineViewportWidth * 0.25))
        }
    }

    static func filmstrip(_ asset: Asset) async -> [CGImage] {
        guard asset.hasVideo, asset.duration > 0 else { return [] }
        let count = asset.isStill ? 1 : min(16, max(4, Int(asset.duration / 1_500)))
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 135)
        gen.requestedTimeToleranceBefore = CMTime(value: 400, timescale: 1000); gen.requestedTimeToleranceAfter = CMTime(value: 400, timescale: 1000)
        let times = Vision.evenTimes(start: 0, end: asset.isStill ? 1_000 : asset.duration, count: count)
        var frames: [Ms: CGImage] = [:]
        for await result in gen.images(for: times.map { CMTime(value: $0, timescale: 1000) }) {
            if let image = try? result.image { frames[Ms((result.requestedTime.seconds * 1000).rounded())] = image }
        }
        return times.compactMap { frames[$0] }
    }

    // MARK: Library actions

    func toggleFavorite(_ asset: Asset) { perform(.setAssetFavorite(asset.id, !asset.favorite), quiet: true) }

    func reveal(_ asset: Asset) { NSWorkspace.shared.activateFileViewerSelecting([asset.url]) }

    func rename(_ asset: Asset, to name: String) { perform(.renameAsset(asset.id, name), quiet: true); renameTarget = nil }

    func filteredAssets() -> [Asset] {
        let used = usedAssetIDs
        var list = visibleAssets
        switch mediaFilter {
        case .all: break
        case .favorites: list = list.filter(\.favorite)
        case .recent: list = Array(list.suffix(12).reversed())
        case .videos: list = list.filter { $0.hasVideo && !$0.isStill }
        case .photos: list = list.filter(\.isStill)
        case .audio: list = list.filter { !$0.hasVideo }
        case .unused: list = list.filter { !used.contains($0.id) }
        }
        return list
    }

    // MARK: Clip actions used by menus and buttons

    func resetSelection() {
        guard let id = selection else { return }
        do { try editor.resetClip(id); loadDraft(); status("Clip reset to plain.") } catch { report(error, quiet: true) }
    }

    func resetLook() {
        guard let c = selectedClip else { return }
        perform(.setLook(c.id, Look()), quiet: true); loadDraft()
    }

    func resetAudio() {
        guard let c = selectedClip else { return }
        perform(.setVolume(c.id, volume: 1, fadeIn: 0, fadeOut: 0), quiet: true); loadDraft()
    }

    func toggleMute(_ clip: Clip) { perform(.setMuted(clip.id, !clip.muted), quiet: true) }

    func splitClip(_ clip: Clip) {
        selection = clip.id
        splitAtPlayhead()
    }

    func addTransitionMenu(_ type: TransitionType, to clip: Clip) { addTransition(type, after: clip.id) }

    func setDuckLevel(_ track: Track, _ level: Double) { perform(.setTrackDuckLevel(track.id, level), quiet: true) }

    // MARK: Templates, looks, overlays (previews)

    private func previewSource() -> (key: String, image: CGImage?) {
        let first = project.assets.first(where: \.hasVideo)
        return (first?.id.uuidString ?? "demo", first.flatMap { thumbnails[$0.id] })
    }

    private var templateThumbsRunning = false
    private var titleThumbsRunning = false

    func ensureTemplateThumbs() {
        let (key, source) = previewSource()
        guard key != thumbsKey || (templateThumbs.isEmpty && !templateThumbsRunning) else { return }
        thumbsKey = key; templateThumbs = [:]; lookThumbs = [:]
        templateThumbsRunning = true
        Task.detached(priority: .utility) {
            for t in Templates.all {
                let image = TemplateRenderer.thumbnail(t, source: source)
                await MainActor.run { [weak self] in if self?.thumbsKey == key, let image { self?.templateThumbs[t.id] = image } }
            }
            let size = CGSize(width: 240, height: 135), rect = CGRect(origin: .zero, size: size)
            let base: CIImage = source.map { CIImage(cgImage: $0) } ?? EffectRenderer.demoScene(size, greenScreen: false)
            let scale = max(size.width / base.extent.width, size.height / base.extent.height)
            let scaled = base.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let fitted = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX, y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY)).cropped(to: rect)
            for name in Look.presetNames {
                guard let look = Look.preset(name) else { continue }
                let image = CIContext().createCGImage(LookRenderer.apply(look, to: fitted, size: size).cropped(to: rect), from: rect)
                await MainActor.run { [weak self] in if self?.thumbsKey == key, let image { self?.lookThumbs[name] = image } }
            }
            await MainActor.run { [weak self] in self?.templateThumbsRunning = false }
        }
    }

    func ensureTitleThumbs() {
        guard titleThumbs.isEmpty, !titleThumbsRunning else { return }   // every card calls this on appear
        titleThumbsRunning = true
        Task.detached(priority: .utility) {
            for preset in TitlePreset.allCases {
                let image = TitlePreviews.image(preset)
                await MainActor.run { [weak self] in if let image { self?.titleThumbs[preset] = image } }
            }
            await MainActor.run { [weak self] in self?.titleThumbsRunning = false }
        }
    }

    func addOverlayKind(_ kind: GeneratorKind, at start: Ms? = nil) {
        do { selection = try editor.addOverlay(kind, start: start ?? playhead, duration: 4_000, amount: 0.5).id } catch { report(error, quiet: true) }
    }

    func ensureOverlayPreview(_ kind: GeneratorKind) {
        guard overlayFrames[kind] == nil else { return }
        overlayFrames[kind] = []   // marks it as in progress
        let source = previewSource().image
        Task.detached(priority: .utility) {
            let frames = GeneratorRenderer.previewFrames(kind, source: source)
            await MainActor.run { [weak self] in self?.overlayFrames[kind] = frames }
        }
    }

    func applyLookToSelection(_ name: String) {
        guard var look = Look.preset(name) else { return }
        let targets = selectedClip.map { [$0.id] } ?? project.tracks.filter { $0.kind == .video }.flatMap(\.clips).filter { $0.assetID != nil }.map(\.id)
        guard !targets.isEmpty else { status("Add a clip first."); return }
        do {
            try editor.transaction {
                for id in targets {
                    guard let c = project.tracks.flatMap(\.clips).first(where: { $0.id == id }) else { continue }
                    look.flipX = c.look.flipX; look.flipY = c.look.flipY; look.rotation = c.look.rotation
                    look.cropLeft = c.look.cropLeft; look.cropRight = c.look.cropRight; look.cropTop = c.look.cropTop; look.cropBottom = c.look.cropBottom
                    try editor.apply(.setLook(id, look))
                }
            }
            loadDraft()
            status("\(name) applied to \(targets.count == 1 ? "the selected clip" : "all clips").")
        } catch { report(error, quiet: true) }
    }

    func applyTemplate(_ t: EditTemplate, selectedOnly: Bool, options: Editor.TemplateOptions, addMusic: Bool) {
        Task {
            do {
                var summary = try editor.applyTemplate(t, to: selectedOnly ? selection.map { [$0] } : nil, options: options)
                if addMusic, let bed = t.music {
                    let url = try await Task.detached { try MusicLibrary.url(for: bed) }.value
                    _ = try editor.addMusicBed(try await importAsset(url), start: 0)
                    summary += "; music \(bed) added"
                }
                templateToApply = nil
                status("\(t.name): \(summary).")
            } catch { report(error) }
        }
    }

    // MARK: Smart tools

    func rampSelection(_ points: [RampPoint], segments: Int = 20) {
        guard let id = selection else { return }
        do { try editor.apply(.rampSpeed(id, points, segments: segments)); selection = nil; rampSheet = false; status("Speed ramp applied. Undo (⌘Z) to go back.") }
        catch { report(error) }
    }

    func findMatchCuts() {
        let videos = project.assets.filter { $0.hasVideo && !isMissing($0) }
        guard videos.count >= 2 else { matchStatus = "Import at least two video clips or photos first."; return }
        matchStatus = "Comparing \(videos.count) clips…"; matchCuts = []
        Task {
            matchCuts = await MatchCuts.find(videos, limit: 6)
            matchStatus = matchCuts.isEmpty ? "No convincing matches. Try clips with similar colours or shapes." : "\(matchCuts.count) matches found."
        }
    }

    func applyMatchCut(_ m: MatchCut) {
        do { _ = try editor.addMatchCut(m); status("Match cut added at the end of the timeline.") } catch { report(error, quiet: true) }
    }

    func smartReframeSelection(aspect: (Int, Int)?) {
        guard let c = selectedClip, let asset = project.assets.first(where: { $0.id == c.assetID }), asset.hasVideo else { status("Select a video clip first."); return }
        status("Finding the subject…")
        Task {
            do {
                if let aspect { try editor.apply(.setFormat(width: aspect.0, height: aspect.1, fps: project.fps)) }
                let track = try await AVURLAsset(url: asset.url).loadTracks(withMediaType: .video).first
                let natural = (try await track?.load(.naturalSize))?.applying((try await track?.load(.preferredTransform)) ?? .identity) ?? CGSize(width: 16, height: 9)
                let followed = await SmartReframe.track(asset, sourceIn: c.sourceIn, length: c.sourceLength, speed: c.speed)
                let count = try editor.reframeClip(c.id, subjects: followed.subjects, sourceAspect: abs(natural.width) / max(1, abs(natural.height)))
                loadDraft()
                status("Reframed on the \(followed.method) with \(count) camera positions.")
            } catch { report(error, quiet: true) }
        }
    }

    // MARK: Ghost edit

    /// Claude works on a copy of the timeline. Nothing changes until you accept.
    func beginGhost() {
        let copy = Editor(project: project)
        ghost = copy
        ghostBag.removeAll()
        copy.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &ghostBag)
        copy.$project.dropFirst().debounce(for: 0.15, scheduler: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.ghostPreview else { return }
            self.rebuild(self.playbackProject)
        }.store(in: &ghostBag)
        let spans = project.tracks.flatMap(\.clips).filter { $0.id == selection || multiSelection.contains($0.id) }
        ghostRange = spans.isEmpty ? nil : (spans.map(\.start).min()!...spans.map(\.end).max()!)
    }

    var ghostDiffers: Bool { ghost.map { $0.project != project } ?? false }

    func acceptGhost() {
        guard let ghost else { return }
        do { try editor.replaceAsEdit(with: ghost.project); endGhost(); status("Ghost edit accepted. Undo (⌘Z) goes back to your version.") } catch { report(error) }
    }

    func endGhost() {
        ghost = nil; ghostRange = nil; ghostBag.removeAll()
        if ghostPreview { ghostPreview = false }
    }

    // MARK: Questions from Claude

    func ask(_ question: String, _ options: [AskOption], _ allowText: Bool) async -> String {
        await withCheckedContinuation { continuation in
            questionContinuation?.resume(returning: "(the user moved on to another question)")
            questionContinuation = continuation
            pendingQuestion = PendingQuestion(question: question, options: options, allowText: allowText)
            rightTab = .assistant; showRight = true
        }
    }

    /// Claude drafted a script: waits for the user to approve it or ask for changes.
    func reviewScript(_ draft: ScriptDraft) async -> String {
        await withCheckedContinuation { continuation in
            scriptContinuation?.resume(returning: "CHANGES REQUESTED: the user moved on to another script")
            scriptContinuation = continuation
            pendingScript = draft
            rightTab = .assistant; showRight = true
        }
    }

    func finishScript(_ draft: ScriptDraft?, feedback: String?) {
        pendingScript = nil
        guard let c = scriptContinuation else { return }
        scriptContinuation = nil
        if let draft, feedback == nil {
            c.resume(returning: "APPROVED. Build exactly this script with build_edit:\n" + draft.render { id in self.project.assets.first { $0.id == id }?.label })
        } else if let draft, let feedback {
            c.resume(returning: "CHANGES REQUESTED: \(feedback)\nThe user's current version of the script:\n" + draft.render { id in self.project.assets.first { $0.id == id }?.label })
        } else { c.resume(returning: "CHANGES REQUESTED: the user closed the script window without approving. Ask what they want changed.") }
    }

    // MARK: Folders (Files tab)

    func addWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.message = "Open a folder with your videos, photos and music"
        if panel.runModal() == .OK { for u in panel.urls where !workspaceRoots.contains(u) { workspaceRoots.append(u) } }
    }

    func importFolderMedia(_ folder: URL) {
        let files = Workspace.mediaFiles(in: folder)
        guard !files.isEmpty else { status("No videos, photos or audio in that folder."); return }
        importFiles(files)
    }

    /// Claude asked for it (offline mode): waits until the user presses Done.
    func pickRanges(_ reason: String, _ ids: [UUID]) async -> String {
        await withCheckedContinuation { continuation in
            selectionContinuation?.resume(returning: "(the user closed the viewer without finishing)")
            selectionContinuation = continuation; manualSelectionDone = nil
            pendingSelection = SelectionRequest(reason: reason, assetIDs: ids)
        }
    }

    /// The user opened the viewer themselves; `done` gets the summary text.
    func openSelection(reason: String, done: @escaping (String) -> Void) {
        selectionContinuation?.resume(returning: "(the user closed the viewer without finishing)"); selectionContinuation = nil
        manualSelectionDone = done
        pendingSelection = SelectionRequest(reason: reason, assetIDs: [])
    }

    func finishSelection(_ summary: String?) {
        pendingSelection = nil
        let text = summary ?? "(the user cancelled the selection)"
        if let c = selectionContinuation { c.resume(returning: text); selectionContinuation = nil }
        else if let done = manualSelectionDone, summary != nil { done(text) }
        manualSelectionDone = nil
    }

    func answerQuestion(_ text: String) {
        questionContinuation?.resume(returning: text)
        questionContinuation = nil; pendingQuestion = nil
    }

    // MARK: Playback

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        if playhead >= project.duration { seek(0) }
        isPlaying = true; player.play()
    }

    func pause() { isPlaying = false; player.pause() }

    func seek(_ ms: Ms) {
        let quantised = Ms((Double(ms) / frameMs).rounded() * frameMs)   // always on a frame
        playhead = max(0, min(quantised, playbackProject.duration))
        if selectedClip?.keyframes.isEmpty == false { loadDraft() }
        followPlayhead()
        player.seek(to: cm(playhead), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func cm(_ ms: Ms) -> CMTime { CMTime(value: ms, timescale: 1000) }

    private func rebuild(_ p: Project) {
        buildGeneration += 1
        let gen = buildGeneration
        guard p.duration > 0 else { player.replaceCurrentItem(with: nil); isPlaying = false; return }
        Task {
            do {
                let built = try await CompositionBuilder.build(p)
                guard gen == buildGeneration else { return }   // a newer edit superseded this build
                let item = AVPlayerItem(asset: built.composition)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                item.audioTimePitchAlgorithm = .spectral
                player.replaceCurrentItem(with: item)
                await player.seek(to: cm(min(playhead, p.duration)), toleranceBefore: .zero, toleranceAfter: .zero)
                if isPlaying { player.play() }
            } catch { errorMessage = "Preview failed: \(error)" }
        }
    }
}
