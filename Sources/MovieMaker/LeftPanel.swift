import AppKit
import AVKit
import QuickLookThumbnailing
import SwiftUI
import MovieCore

// MARK: Navigation rail + content

struct LeftArea: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            NavRail()
            LeftContent().frame(width: model.leftWidth)
        }
        .frame(width: (model.navExpanded ? 150 : 72) + model.leftWidth)
        .background(Theme.panel).clipped()
    }
}

struct NavRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Button { model.navExpanded.toggle() } label: {
                Image(systemName: model.navExpanded ? "chevron.left.2" : "chevron.right.2").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity).frame(height: 18)
            }.buttonStyle(.plain).help(model.navExpanded ? "Icons only" : "Icons and names")
            GeometryReader { geo in
                // Items shrink to fit the window height, so the rail never needs to scroll.
                let count = CGFloat(LeftTab.allCases.count)
                let natural: CGFloat = model.navExpanded ? 38 : 50
                let row = min(natural, max(30, (geo.size.height - 12) / count - 4))
                VStack(spacing: 4) {
                    ForEach(LeftTab.allCases, id: \.self) { tab in
                        let selected = model.leftTab == tab
                        Button { model.leftTab = tab } label: {
                            Group {
                                if model.navExpanded {
                                    HStack(spacing: 10) {
                                        Image(systemName: tab.symbol).font(.system(size: 15)).frame(width: 22)
                                        Text(tab.rawValue).font(.system(size: 13, weight: .medium))
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 10).frame(height: row)
                                } else {
                                    VStack(spacing: 2) {
                                        Image(systemName: tab.symbol).font(.system(size: row < 44 ? 14 : 17))
                                        Text(tab.rawValue).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                                    }.frame(maxWidth: .infinity).frame(height: row)
                                }
                            }
                            .foregroundStyle(selected ? Color.white : Theme.dim)
                            .background(selected ? Theme.accent.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).help(tab.rawValue)
                    }
                }.padding(.horizontal, 6).padding(.top, 4)
            }
        }
        .frame(width: model.navExpanded ? 150 : 72)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }
}

struct LeftContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.leftTab {
            case .media: MediaPanel(full: true)
            case .files: FilesTab()
            case .titles: TitlesTab()
            case .overlays: OverlaysTab()
            case .audio: AudioTab()
            case .transitions: TransitionsTab()
            case .effects: EffectsTab()
            case .color: ColorTab()
            case .templates: TemplatesTab()
            case .smart: SmartTab()
            }
        }.id(model.leftTab)
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var modes = false
    @ViewBuilder var trailing: Trailing
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            trailing
            if modes {
                Menu {
                    Picker("View", selection: $model.viewMode) { ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }.pickerStyle(.inline)
                } label: { Image(systemName: model.viewMode.symbol).font(.system(size: 13)).foregroundStyle(Theme.dim) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Change how items are shown")
            }
        }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, modes: Bool = false) { self.title = title; self.subtitle = subtitle; self.modes = modes; self.trailing = EmptyView() }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim).font(.system(size: 12))
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12.5))
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }.buttonStyle(.plain) }
        }.padding(.horizontal, 10).frame(height: 32).card(radius: 9)
    }
}

// MARK: Media

struct MediaPanel: View {
    @EnvironmentObject var model: AppModel
    let full: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: full ? "Media" : "Project media", subtitle: "\(model.project.assets.count) items", modes: true) {
                Button { model.importing = true } label: { Label("Import", systemImage: "plus").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            VStack(spacing: 8) {
                SearchField(placeholder: "Search media…", text: $model.searchText)
                if full {
                    FlowLayout { ForEach(MediaFilter.allCases, id: \.self) { f in Chip(title: f.rawValue, selected: model.mediaFilter == f) { model.mediaFilter = f } } }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.anyMissing {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Some files moved").font(.system(size: 12))
                        Spacer()
                        Button("Find folder…") { model.locateMissing() }.controlSize(.small)
                    }.padding(8).card()
                }
                ImportSummary()
            }.padding(.horizontal, 14).padding(.bottom, 8)
            if model.filteredAssets().isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(Theme.dim)
                    Text(model.project.assets.isEmpty ? "Import videos, photos and audio, or drop files here." : "Nothing matches.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else {
                ScrollView {
                    LazyVGrid(columns: model.viewMode.columns, spacing: 12) { ForEach(model.filteredAssets()) { AssetCard(asset: $0) } }.padding(.horizontal, 14).padding(.bottom, 14)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in model.importFiles(urls); return true }
        .dropDestination(for: String.self) { items, _ in
            let files = items.filter { $0.hasPrefix("files:") }
            files.forEach { model.importDropped(String($0.dropFirst(6))) }
            return !files.isEmpty
        }
    }
}

/// One compact card for all running imports (a folder can bring hundreds of files).
struct ImportSummary: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.importTotal > 0 || !model.importFailures.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                if model.importTotal > 0 {
                    HStack {
                        Text("Importing \(min(model.importDone + 1, model.importTotal)) of \(model.importTotal)").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Cancel") { model.cancelImports() }.buttonStyle(.link).font(.system(size: 11.5))
                    }
                    ProgressView(value: Double(model.importDone), total: Double(max(1, model.importTotal))).tint(Theme.accent)
                    Text(model.importJobs.prefix(3).map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                }
                if !model.importFailures.isEmpty {
                    HStack {
                        Label("\(model.importFailures.count) could not be imported", systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5)).foregroundStyle(.orange)
                        Spacer()
                        Button("Dismiss") { model.importFailures = [] }.buttonStyle(.link).font(.system(size: 11.5))
                    }
                    ForEach(model.importFailures.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(.red).lineLimit(2) }
                }
            }.padding(8).card()
        }
    }
}

struct ImportRow: View {
    let job: ImportJob
    private static let steps = ["Reading file…", "Making thumbnail…", "Reading audio…", "Done"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.name).lineLimit(1).font(.system(size: 12))
            if let failure = job.failure { Text(failure).font(.caption).foregroundStyle(.red) }
            else {
                ProgressView(value: Double(job.step + 1), total: 4).tint(Theme.accent)
                Text(Self.steps[min(job.step, 3)]).font(.caption).foregroundStyle(Theme.dim)
            }
        }.padding(8).card()
    }
}

struct MiniWave: View {
    let levels: [Float]
    var body: some View {
        Canvas { ctx, size in
            guard !levels.isEmpty else { return }
            let bars = 48, step = size.width / CGFloat(bars)
            for i in 0..<bars {
                let a = i * levels.count / bars, b = max(a + 1, (i + 1) * levels.count / bars)
                let peak = levels[a..<min(b, levels.count)].max() ?? 0
                let h = max(2, CGFloat(peak) * size.height * 0.8)
                ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * step + 1, y: (size.height - h) / 2, width: max(1, step - 2), height: h), cornerRadius: 1), with: .color(Theme.audio.opacity(0.9)))
            }
        }
    }
}

struct AssetCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    let asset: Asset

    private var thumb: some View {
        ZStack {
            if let image = model.thumbnails[asset.id] {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Theme.raised.overlay(Group { asset.hasVideo ? AnyView(Image(systemName: "film").foregroundStyle(Theme.dim)) : AnyView(MiniWave(levels: model.waveforms[asset.id] ?? []).padding(10)) })
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity).clipped().cornerRadius(9)
    }

    private var kind: String { asset.isStill ? "Photo" : asset.hasVideo ? "Video" : "Audio" }

    var body: some View {
        let used = model.usedAssetIDs.contains(asset.id), missing = model.isMissing(asset), mode = model.viewMode
        Group {
            if mode.isRow {
                HStack(spacing: 10) {
                    thumb.frame(width: mode == .detail ? 120 : 64)
                        .overlay(alignment: .topLeading) { if used { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 10)).padding(3) } }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.label).font(.system(size: 12.5, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
                        Text("\(kind) · \(formatTime(asset.duration))").font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                        if mode == .detail {
                            Text(used ? "Used in the timeline" : "Not used yet").font(.system(size: 10.5)).foregroundStyle(used ? Theme.accent : Theme.dim)
                            if asset.favorite { Label("Favorite", systemImage: "star.fill").font(.system(size: 10.5)).foregroundStyle(.yellow) }
                        }
                    }
                    Spacer(minLength: 0)
                    Menu { assetMenu } label: { Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(Theme.dim) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }.padding(6).card(radius: 9).opacity(used ? 0.7 : 1)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    thumb
                        .overlay(alignment: .bottomTrailing) {
                            Text(formatTime(asset.duration)).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.65), in: Capsule()).padding(5)
                        }
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 4) {
                                if asset.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                if used { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                            }.font(.system(size: 11)).padding(5).shadow(radius: 2)
                        }
                        .overlay { if missing { Color.black.opacity(0.55).overlay(VStack(spacing: 4) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Button("Relink…") { model.relink(asset) }.controlSize(.small) }) } }
                        .opacity(used ? 0.62 : 1)
                    HStack(spacing: 4) {
                        Image(systemName: asset.isStill ? "photo" : asset.hasVideo ? "video.fill" : "waveform").font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                        Text(asset.label).font(.system(size: mode == .small ? 10.5 : 11.5)).lineLimit(1).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        Menu { assetMenu } label: { Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(Theme.dim) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
            }
        }
        .draggable("asset:\(asset.id.uuidString)")
        .onTapGesture(count: 2) { model.addToTimeline(asset) }
        .contextMenu { assetMenu }
    }

    @ViewBuilder private var assetMenu: some View {
        Button("Mention in Assistant") {
            chat.mention("[file \"\(asset.label)\" asset_id=\(asset.id.uuidString), \(formatTime(asset.duration)) long]")
            model.rightTab = .assistant; model.showRight = true
        }
        Divider()
        Button("Add to timeline") { model.addToTimeline(asset) }
        if asset.hasVideo { Button("Add as overlay (picture in picture)") { model.addOverlay(asset) } }
        Divider()
        Button(asset.favorite ? "Remove from favorites" : "Add to favorites") { model.toggleFavorite(asset) }
        Button("Rename…") { model.renameTarget = asset }
        Button("Get info") { model.infoTarget = .asset(asset.id) }
        Button("Show in Finder") { model.reveal(asset) }
        if model.isMissing(asset) { Button("Relink…") { model.relink(asset) } }
        Divider()
        Button("Remove from library", role: .destructive) { model.requestRemove(asset) }
    }
}

// MARK: Card grids for transitions, effects, overlays, titles


/// Plays pre-rendered frames: only the image changes, so the card never re-lays out (no flicker).
struct AnimatedPreview: View {
    let frames: [CGImage]?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            if let frames, !frames.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    let i = Int(context.date.timeIntervalSinceReferenceDate * 18) % frames.count
                    Image(decorative: frames[i], scale: 1).resizable().scaledToFill()
                }
            } else { ProgressView().controlSize(.small) }
        }
        .aspectRatio(16 / 9, contentMode: .fit).clipped().cornerRadius(8)
    }
}

struct GridCard<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let title: String
    var subtitle: String?
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        switch model.viewMode {
        case .small:
            VStack(alignment: .leading, spacing: 3) {
                content
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
            }.padding(4).card(radius: 8)
        case .large:
            VStack(alignment: .leading, spacing: 5) {
                content
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1) }
            }.padding(6).card()
        case .list, .detail:
            let rich = model.viewMode == .detail
            HStack(alignment: .top, spacing: 10) {
                content.frame(width: rich ? 120 : 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
                    if let subtitle { Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1) }
                    if rich, let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(4).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading).card(radius: 9)
        }
    }
}

/// Chips that wrap onto extra lines instead of overflowing.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(proposal.width ?? 300, subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return (points, CGSize(width: maxX, height: y + row))
    }
}

struct TransitionsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Transitions", subtitle: "\(TransitionType.allCases.count) styles. Drag one onto a clip: the right half joins it to the next clip, the left half to the previous one. Double-click applies it to the selected clip.", modes: true)
            ScrollView {
                LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                    ForEach(TransitionType.allCases, id: \.self) { type in
                        GridCard(title: type.title) { AnimatedPreview(frames: model.transitionFrames[type]) }
                            .onAppear { model.ensurePreview(type) }
                            .draggable("transition:\(type.rawValue)")
                            .onTapGesture(count: 2) { if let id = model.selection { model.addTransition(type, after: id) } }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }
}

struct EffectsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Effects", subtitle: "Drag onto a video clip, or double-click to add to the selected clip. Adjust the strength in the Effects tab on the right.", modes: true)
            ScrollView {
                LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                    ForEach(EffectType.allCases, id: \.self) { type in
                        GridCard(title: type.title) { AnimatedPreview(frames: model.effectFrames[type]) }
                            .help(type.summary)
                            .onAppear { model.ensureEffectPreview(type) }
                            .draggable("effect:\(type.rawValue)")
                            .onTapGesture(count: 2) { if let id = model.selection { model.addEffect(type, to: id) } }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }
}

struct OverlaysTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Overlays", subtitle: "Drawn layers above your picture: confetti, snow, rain, light. Drag onto the timeline or double-click to add at the playhead.", modes: true)
            ScrollView {
                LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                    ForEach(GeneratorKind.allCases, id: \.self) { kind in
                        GridCard(title: kind.title) { AnimatedPreview(frames: model.overlayFrames[kind]) }
                            .help(kind.summary)
                            .onAppear { model.ensureOverlayPreview(kind) }
                            .draggable("overlay:\(kind.rawValue)")
                            .onTapGesture(count: 2) { model.addOverlayKind(kind) }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }
}

struct TitlesTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Titles", subtitle: "Drag onto the timeline, or double-click to add at the playhead. Select a title to change the text, size, colour and animation.", modes: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                        ForEach(TitlePreset.allCases, id: \.self) { preset in
                            GridCard(title: preset.rawValue) {
                                ZStack {
                                    Color.black.opacity(0.35)
                                    if let image = model.titleThumbs[preset] { Image(decorative: image, scale: 1).resizable().scaledToFill() } else { ProgressView().controlSize(.small) }
                                }.aspectRatio(16 / 9, contentMode: .fit).clipped().cornerRadius(8)
                            }
                            .onAppear { model.ensureTitleThumbs() }
                            .draggable("title:\(preset.rawValue)")
                            .onTapGesture(count: 2) { model.addTitle(preset) }
                        }
                    }
                    SectionTitle(text: "Stickers")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(["🔥", "❤️", "😂", "😎", "🎉", "👏", "⭐️", "✨", "🚀", "💯", "👍", "😍", "🌴", "☀️", "🏆", "🎵", "📍", "⚡️"], id: \.self) { emoji in
                            Text(emoji).font(.system(size: 26)).frame(maxWidth: .infinity).padding(.vertical, 4).card(radius: 8)
                                .draggable("sticker:\(emoji)").onTapGesture { model.addSticker(emoji) }
                        }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }
}

// MARK: Audio

struct AudioTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var search: SoundSearchModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Audio", subtitle: "Free music and sounds. Press + to add at the playhead or drag onto a track.")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Music · \(MusicLibrary.tracks.count) songs")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(["All"] + MusicLibrary.categories, id: \.self) { c in Chip(title: c, selected: model.musicCategory == c) { model.musicCategory = c } } }
                    }
                    ForEach(MusicLibrary.tracks.filter { model.musicCategory == "All" || $0.category == model.musicCategory }, id: \.name) { track in
                        SoundRow(title: track.name, subtitle: "\(Int(track.bpm)) BPM · \(track.mood)", previewID: "music:\(track.name)",
                                 preview: { try await Task.detached { try MusicLibrary.url(for: track.name) }.value },
                                 add: { model.addMusic(track.name) }, drag: "music:\(track.name)")
                    }
                    SectionTitle(text: "Sound effects").padding(.top, 8)
                    ForEach(SoundEffects.names, id: \.self) { name in
                        SoundRow(title: name, subtitle: nil, previewID: "sfx:\(name)", preview: { try SoundEffects.url(for: name) }, add: { model.addSoundEffect(name) }, drag: "sfx:\(name)")
                    }
                    Divider().overlay(Theme.stroke).padding(.vertical, 6)
                    SectionTitle(text: "Search online")
                    HStack {
                        SearchField(placeholder: "e.g. upbeat acoustic, door slam", text: $search.query).onSubmit { search.run() }
                        Button("Search") { search.run() }.disabled(search.query.trimmingCharacters(in: .whitespaces).isEmpty || search.searching)
                    }
                    Picker("", selection: $search.kind) { Text("Music").tag(OnlineLibrary.Kind.music); Text("Effects").tag(OnlineLibrary.Kind.effects) }.pickerStyle(.segmented).labelsHidden()
                    Toggle("Include CC BY (needs a credit)", isOn: $search.allowAttribution).font(.system(size: 12))
                    if search.searching { ProgressView().controlSize(.small) }
                    if let message = search.message { Text(message).font(.system(size: 12)).foregroundStyle(Theme.dim) }
                    ForEach(search.results) { sound in
                        SoundRow(title: sound.title, subtitle: "\(sound.creator) · \(sound.license == "by" ? "CC BY" : sound.license == "cc0" ? "CC0" : "Public domain") · \(sound.durationMs / 1000) s",
                                 previewID: "online:\(sound.id)", preview: { URL(string: sound.fileURL)! }, add: { search.add(sound, model: model) }, drag: nil, busy: search.busy.contains(sound.id))
                    }
                    Text("Results come from Openverse (freesound, Jamendo and others).").font(.system(size: 10.5)).foregroundStyle(Theme.dim.opacity(0.7))
                    Button("Copy credits for this project") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.creditsText(), forType: .string); model.status("Credits copied.")
                    }.controlSize(.small)
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }
}

struct SoundRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let subtitle: String?
    let previewID: String
    let preview: @Sendable () async throws -> URL
    let add: () -> Void
    let drag: String?
    var busy = false

    var body: some View {
        HStack(spacing: 10) {
            Button { model.togglePreview(id: previewID, url: preview) } label: {
                Image(systemName: model.previewingID == previewID ? "stop.fill" : "play.fill").font(.system(size: 11)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(model.previewingID == previewID ? Theme.accent : Theme.hover, in: Circle())
            }.buttonStyle(.plain).help("Listen")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
            else { IconButton(symbol: "plus.circle", help: "Add at the playhead", action: add) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6).card(radius: 10)
        .modifier(DragIf(payload: drag))
    }
}

private struct DragIf: ViewModifier {
    let payload: String?
    func body(content: Content) -> some View { if let payload { content.draggable(payload) } else { content } }
}

// MARK: Color

struct ColorTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Color", subtitle: "Looks and grades. They apply to the selected clip, or to every clip when nothing is selected. Fine-tune in Adjust on the right.", modes: true)
            ScrollView {
                LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                    ForEach(Look.presetNames, id: \.self) { name in
                        GridCard(title: name) {
                            ZStack {
                                Color.black.opacity(0.35)
                                if let image = model.lookThumbs[name] { Image(decorative: image, scale: 1).resizable().scaledToFill() } else { ProgressView().controlSize(.small) }
                            }.aspectRatio(16 / 9, contentMode: .fit).clipped().cornerRadius(8)
                        }
                        .onTapGesture { model.applyLookToSelection(name) }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .onAppear { model.ensureTemplateThumbs() }
    }
}

// MARK: Templates

struct TemplatesTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel

    var body: some View {
        let selected = model.templateCategory
        VStack(spacing: 0) {
            PanelHeader(title: "Templates", subtitle: "\(Templates.all.count) complete film styles: colour, effects, joins, titles and overlay in one click. Click one to apply it.", modes: true)
            FlowLayout {
                ForEach(["All"] + Templates.categories, id: \.self) { c in Chip(title: c, selected: selected == c) { model.templateCategory = c } }
            }.padding(.horizontal, 14).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVGrid(columns: model.viewMode.columns, spacing: 10) {
                    ForEach(Templates.all.filter { selected == "All" || $0.category == selected }) { t in
                        GridCard(title: t.name, subtitle: t.category, detail: t.summary) {
                            ZStack {
                                Color.black.opacity(0.35)
                                if let image = model.templateThumbs[t.id] { Image(decorative: image, scale: 1).resizable().scaledToFill() } else { ProgressView().controlSize(.small) }
                            }.aspectRatio(16 / 9, contentMode: .fit).clipped().cornerRadius(8)
                        }
                        .help(t.summary)
                        .onTapGesture { model.templateToApply = t }
                        .contextMenu {
                            Button("Apply to all clips…") { model.templateToApply = t }
                            Button("Ask the Assistant to apply it") { model.rightTab = .assistant; model.showRight = true; chat.draft = "Apply the \(t.name) template to my film."; chat.send(using: model) }
                        }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .onAppear { model.ensureTemplateThumbs() }
    }
}

// MARK: Smart tools

struct SmartTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Smart tools", subtitle: "Automatic helpers. Everything they do can be undone.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    toolCard("Smart match cuts", "Finds two clips that match in colour, brightness and where the bright shape sits, so a cut feels like one move.", symbol: "link.circle") {
                        Button("Find matches") { model.findMatchCuts() }.buttonStyle(.borderedProminent).controlSize(.small)
                        if let status = model.matchStatus { Text(status).font(.system(size: 11.5)).foregroundStyle(Theme.dim) }
                        ForEach(Array(model.matchCuts.enumerated()), id: \.offset) { _, m in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("\(Int(m.score * 100)) % match").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                                    Spacer()
                                    Button("Add") { model.applyMatchCut(m) }.controlSize(.small)
                                }
                                Text("\(name(m.assetA)) at \(formatTime(m.timeA)) → \(name(m.assetB)) at \(formatTime(m.timeB))").font(.system(size: 11.5)).foregroundStyle(Theme.text)
                                Text(m.reason).font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }.padding(8).card(Theme.panel, radius: 9)
                        }
                    }
                    toolCard("Smart reframe", "Turns a landscape clip into a vertical or square one and keeps the main person or subject in view. Select a clip first.", symbol: "rectangle.portrait.on.rectangle.portrait") {
                        HStack {
                            Button("Vertical 9:16") { model.smartReframeSelection(aspect: (1080, 1920)) }
                            Button("Portrait 4:5") { model.smartReframeSelection(aspect: (1080, 1350)) }
                            Button("Square") { model.smartReframeSelection(aspect: (1080, 1080)) }
                        }.controlSize(.small)
                        Button("Keep the current movie size") { model.smartReframeSelection(aspect: nil) }.controlSize(.small)
                    }
                    toolCard("Speed ramp studio", "Smooth slow motion into normal into fast, from a preset or your own curve. Select a clip first.", symbol: "speedometer") {
                        Button("Open the studio…") { if model.selectedClip == nil { model.status("Select a clip first.") } else { model.rampSheet = true } }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    toolCard("Ghost edit", "Select part of the timeline and ask Claude for something more spectacular. You get an alternative to preview over your own edit, and accept it or throw it away.", symbol: "sparkles.rectangle.stack") {
                        Button("Start a ghost edit…") { model.rightTab = .assistant; model.showRight = true; chat.ghostMode = true }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    toolCard("Guided edit", "Claude asks you step by step: analyse the clips? what theme? how long? which music? Then it builds the film.", symbol: "list.bullet.clipboard") {
                        Button("Start a guided edit") { model.rightTab = .assistant; model.showRight = true; chat.startGuidedEdit(using: model) }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    toolCard("Quick automatic edit", "A fast mechanical cut of the busiest moments. For a real film use the Assistant.", symbol: "wand.and.stars") {
                        HStack { ForEach([15, 30, 60], id: \.self) { s in Button("\(s) s") { model.autoMovie(seconds: s) }.controlSize(.small) } }
                            .disabled(model.autoMaking || !model.project.assets.contains { $0.hasVideo })
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
    }

    private func name(_ id: UUID) -> String { model.project.assets.first { $0.id == id }?.label ?? "?" }

    private func toolCard<Content: View>(_ title: String, _ text: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Theme.accent).font(.system(size: 15))
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).card()
    }
}

// MARK: Files (folders on disk)

enum FileSort: String, CaseIterable { case name = "Name", kind = "Kind", size = "Size", date = "Date modified" }

/// Everything the Files tab remembers: what is expanded and selected, the filter and sort, and cached thumbnails.
final class FilesState: ObservableObject {
    @Published var expanded = Set<URL>()
    @Published var selected = Set<URL>()
    @Published var anchor: URL?
    @Published var filter = ""
    @Published var kind = "All"
    @Published var sort = FileSort.name
    @Published var ascending = true
    @Published var thumbs: [URL: NSImage] = [:]
    @Published var counts: [URL: (items: Int, video: Int, image: Int, audio: Int)] = [:]
    private var requested = Set<URL>()
    private var counting = Set<URL>()

    /// How many files a folder holds (direct items and media files anywhere inside), counted once in the background.
    /// The folder's count line, following the kind filter (All, Video, Photos, Audio).
    func countText(_ folder: URL) -> String? {
        guard let c = counts[folder] else { return nil }
        func n(_ v: Int, _ one: String, _ many: String) -> String { "\(v) \(v == 1 ? one : many)" }
        switch kind {
        case "Video": return n(c.video, "video", "videos")
        case "Photos": return n(c.image, "photo", "photos")
        case "Audio": return n(c.audio, "audio file", "audio files")
        default: return "\(n(c.items, "item", "items")) · \(n(c.video + c.image + c.audio, "media file", "media files"))"
        }
    }

    func count(_ folder: URL) {
        guard counts[folder] == nil, counting.insert(folder).inserted else { return }
        DispatchQueue.global(qos: .utility).async {
            let items = Workspace.children(of: folder).count, media = Workspace.mediaFiles(in: folder, limit: 5_000).compactMap(Workspace.kind)
            let c = (items, media.filter { $0 == "video" }.count, media.filter { $0 == "image" }.count, media.filter { $0 == "audio" }.count)
            DispatchQueue.main.async { self.counts[folder] = c }
        }
    }

    struct Row: Identifiable { let url: URL; let depth: Int; let isRoot: Bool; var id: URL { url } }

    private func key(_ u: URL) -> (String, Int, Date, String) {
        let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (Workspace.kind(u) ?? "z", v?.fileSize ?? 0, v?.contentModificationDate ?? .distantPast, u.lastPathComponent)
    }

    func sorted(_ urls: [URL]) -> [URL] {
        let folders = urls.filter(Workspace.isFolder).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let files = urls.filter { !Workspace.isFolder($0) }.sorted { a, b in
            let ka = key(a), kb = key(b)
            let less: Bool
            switch sort {
            case .name: less = ka.3.localizedStandardCompare(kb.3) == .orderedAscending
            case .kind: less = ka.0 == kb.0 ? ka.3.localizedStandardCompare(kb.3) == .orderedAscending : ka.0 < kb.0
            case .size: less = ka.1 < kb.1
            case .date: less = ka.2 < kb.2
            }
            return ascending ? less : !less
        }
        return folders + files
    }

    private func shown(_ file: URL) -> Bool { kind == "All" || Workspace.kind(file) == kind.lowercased() || (kind == "Photos" && Workspace.kind(file) == "image") }

    func rows(_ roots: [URL]) -> [Row] {
        var out: [Row] = []
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            for root in roots { for f in Workspace.mediaFiles(in: root, limit: 2_000) where f.lastPathComponent.lowercased().contains(needle) && shown(f) { out.append(Row(url: f, depth: 0, isRoot: false)) } }
            return out
        }
        func walk(_ dir: URL, _ depth: Int) {
            for u in sorted(Workspace.children(of: dir)) {
                if Workspace.isFolder(u) { out.append(Row(url: u, depth: depth, isRoot: false)); if expanded.contains(u) { walk(u, depth + 1) } }
                else if shown(u) { out.append(Row(url: u, depth: depth, isRoot: false)) }
            }
        }
        for root in roots { out.append(Row(url: root, depth: 0, isRoot: true)); if expanded.contains(root) { walk(root, 1) } }
        return out
    }

    func click(_ url: URL, rows: [Row], shift: Bool, command: Bool) {
        if shift, let anchor, let a = rows.firstIndex(where: { $0.url == anchor }), let b = rows.firstIndex(where: { $0.url == url }) {
            selected = Set(rows[min(a, b)...max(a, b)].map(\.url))
        } else if command {
            if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
            anchor = url
        } else {
            selected = [url]; anchor = url
            if Workspace.isFolder(url) { if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) } }
        }
    }

    func thumbnail(_ url: URL) {
        guard Workspace.kind(url) != nil, Workspace.kind(url) != "audio", !requested.contains(url) else { return }
        requested.insert(url)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 120), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { self.thumbs[url] = image }
        }
    }
}

struct FilesTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    @StateObject private var st = FilesState()

    var body: some View {
        let rows = st.rows(model.workspaceRoots)
        VStack(spacing: 0) {
            PanelHeader(title: "Files", subtitle: nil) {
                Button { model.addWorkspaceFolder() } label: { Label("Open", systemImage: "folder.badge.plus").font(.system(size: 12, weight: .semibold)) }.buttonStyle(.bordered).controlSize(.small)
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SearchField(placeholder: "Filter files…", text: $st.filter)
                    Menu {
                        Picker("Sort by", selection: $st.sort) { ForEach(FileSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
                        Divider()
                        Button(st.ascending ? "Ascending ✓" : "Ascending") { st.ascending = true }
                        Button(st.ascending ? "Descending" : "Descending ✓") { st.ascending = false }
                    } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort")
                    Button { st.selected = Set(rows.filter { !Workspace.isFolder($0.url) }.map(\.url)) } label: { Image(systemName: "checkmark.circle").font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 28, height: 28) }.buttonStyle(.plain).help("Select all files shown")
                }
                FlowLayout { ForEach(["All", "Video", "Photos", "Audio"], id: \.self) { k in Chip(title: k, selected: st.kind == k) { st.kind = k } } }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 14).padding(.bottom, 8)
            if model.workspaceRoots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 30)).foregroundStyle(Theme.dim)
                    Text("Open a folder to browse it here.").font(.system(size: 12.5)).foregroundStyle(Theme.dim)
                    Button("Open folder…") { model.addWorkspaceFolder() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { row in FileRow(row: row, rows: rows).environmentObject(st) }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }
                PanelHandle(edge: .aboveBottom, value: $model.filesPreviewHeight, range: 120...620)
                FilePreview().environmentObject(st).frame(height: model.filesPreviewHeight)
            }
        }
        .onAppear { for r in model.workspaceRoots where st.expanded.isEmpty { st.expanded.insert(r) } }
        .dropDestination(for: URL.self) { urls, _ in
            var added = false
            for u in urls where Workspace.isFolder(u) && !model.workspaceRoots.contains(u) { model.workspaceRoots.append(u); st.expanded.insert(u); added = true }
            return added
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    @EnvironmentObject var st: FilesState
    let row: FilesState.Row
    let rows: [FilesState.Row]

    private var url: URL { row.url }
    private var isFolder: Bool { Workspace.isFolder(url) }
    private var kind: String? { Workspace.kind(url) }
    private var isSelected: Bool { st.selected.contains(url) }
    private var targets: [URL] { isSelected ? rows.map(\.url).filter { st.selected.contains($0) } : [url] }

    var body: some View {
        HStack(spacing: 7) {
            if isFolder { Image(systemName: st.expanded.contains(url) ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 12) }
            else { Color.clear.frame(width: 12) }
            thumb.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 12.5, weight: row.isRoot ? .semibold : .regular)).lineLimit(1).foregroundStyle(kind == nil && !isFolder ? Theme.dim.opacity(0.6) : Theme.text)
                if isFolder, let line = st.countText(url) {
                    Text(line).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                } else if !isFolder, let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(v.fileSize ?? 0), countStyle: .file)) · \((v.contentModificationDate ?? .now).formatted(date: .abbreviated, time: .omitted))").font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 14 + 4).padding(.vertical, 3).padding(.trailing, 6)
        .background(isSelected ? Theme.accent.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .overlay(RowInteraction(
            click: { shift, command in st.click(url, rows: rows, shift: shift, command: command) },
            double: { if !isFolder, kind != nil { model.importFiles(targets.filter { Workspace.kind($0) != nil }) } },
            isSelected: { st.selected.contains(url) },
            targets: { targets },
            image: { st.thumbs[url] ?? NSWorkspace.shared.icon(forFile: url.path) }))
        .contextMenu {
            let media = targets.filter { Workspace.kind($0) != nil }
            if !media.isEmpty { Button("Import \(media.count == 1 ? "this file" : "\(media.count) files")") { model.importFiles(media) } }
            ForEach(targets.filter(Workspace.isFolder).prefix(1), id: \.self) { folder in
                Button("Import all media in this folder") { model.importFolderMedia(folder) }
                Button("Ask the Assistant what is in here") {
                    chat.draft = "Look at the folder \(folder.path) with browse_folder (two levels deep) and tell me what it contains, what looks usable for a film, and what you would import. Do not import anything yet."
                    model.rightTab = .assistant; model.showRight = true; chat.send(using: model)
                }
            }
            Button("Mention in Assistant") {
                chat.mention(targets.map { "[\(Workspace.isFolder($0) ? "folder" : "file") \($0.path)]" }.joined(separator: " "))
                model.rightTab = .assistant; model.showRight = true
            }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets) }
            if row.isRoot { Button("Close folder") { model.workspaceRoots.removeAll { $0 == url } } }
        }
        .onAppear { st.thumbnail(url); if isFolder { st.count(url) } }
    }

    @ViewBuilder private var thumb: some View {
        if let image = st.thumbs[url] { Image(nsImage: image).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 5)) }
        else {
            Image(systemName: isFolder ? (st.expanded.contains(url) ? "folder.fill" : "folder") : kind == "video" ? "film" : kind == "audio" ? "music.note" : kind == "image" ? "photo" : "doc")
                .font(.system(size: 14)).foregroundStyle(isFolder ? Theme.accent : Theme.dim)
        }
    }
}

/// Bottom pane: plays or shows the selected file and offers to import it.
struct FilePreview: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var st: FilesState
    @StateObject private var player = RangePlayer()
    final class Meta: ObservableObject { @Published var text = ""; @Published var durationMs: Ms = 1 }
    @StateObject private var meta = Meta()
    private var text: String { get { meta.text } nonmutating set { meta.text = newValue } }
    private var durationMs: Ms { get { meta.durationMs } nonmutating set { meta.durationMs = newValue } }

    private var files: [URL] { st.selected.filter { !Workspace.isFolder($0) }.sorted { $0.path < $1.path } }
    private var current: URL? { st.anchor.flatMap { st.selected.contains($0) && !Workspace.isFolder($0) ? $0 : nil } ?? files.first }

    var body: some View {
        VStack(spacing: 8) {
            if st.selected.count > 1 {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 26)).foregroundStyle(Theme.accent)
                    Text("\(st.selected.count) items selected").font(.system(size: 13, weight: .semibold))
                    Button("Import \(files.count) file\(files.count == 1 ? "" : "s")") { model.importFiles(files.filter { Workspace.kind($0) != nil }) }.buttonStyle(.borderedProminent).disabled(files.isEmpty)
                    Text("Drag them onto Media or the timeline to import.").font(.system(size: 11)).foregroundStyle(Theme.dim)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = current, let kind = Workspace.kind(url) {
                Group {
                    if kind == "image" { PreviewImage(url: url) }
                    else if kind == "video" { RawPlayerView(player: player.player).clipShape(RoundedRectangle(cornerRadius: 8)).background(Color.black, in: RoundedRectangle(cornerRadius: 8)) }
                    else { Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(Theme.audio).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxHeight: .infinity)
                if kind != "image" {
                    HStack(spacing: 8) {
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                        Slider(value: Binding(get: { Double(player.currentMs) }, set: { player.seek(Ms($0)) }), in: 0...max(1, Double(durationMs)))
                        Text(formatTime(player.currentMs)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                }
                HStack {
                    Text(text).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    Spacer()
                    Button("Import") { model.importFiles([url]) }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            } else if let folder = st.selected.first, Workspace.isFolder(folder) {
                VStack(spacing: 8) {
                    Image(systemName: "folder.fill").font(.system(size: 28)).foregroundStyle(Theme.accent)
                    Text(folder.lastPathComponent).font(.system(size: 13, weight: .semibold))
                    Text("\(Workspace.mediaFiles(in: folder).count) media files inside").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                    Button("Import all media") { model.importFolderMedia(folder) }.buttonStyle(.borderedProminent).controlSize(.small)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a file to preview it.").font(.system(size: 12)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .task(id: current) { await load() }
        .onDisappear { player.player.pause() }
    }

    private func load() async {
        player.player.pause()
        guard st.selected.count <= 1, let url = current, let kind = Workspace.kind(url) else { text = ""; return }
        let size = ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0), countStyle: .file)
        text = "\(url.lastPathComponent) · \(size)"
        if kind == "video" || kind == "audio" {
            player.load(url)
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration), d.seconds.isFinite { durationMs = Ms(d.seconds * 1000); text += " · " + formatTime(durationMs) }
            if kind == "video", let t = try? await asset.loadTracks(withMediaType: .video).first, let s = try? await t.load(.naturalSize) { text += " · \(Int(abs(s.width)))×\(Int(abs(s.height)))" }
        } else if let image = NSImage(contentsOf: url) { text += " · \(Int(image.size.width))×\(Int(image.size.height))" }
    }
}

struct PreviewImage: View {
    let url: URL
    var body: some View {
        if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(Theme.dim) }
    }
}

/// Mouse handling for a file row: click, shift/⌘-click, double-click and a real drag of every selected file (Finder-style, as file URLs).
struct RowInteraction: NSViewRepresentable {
    var click: (_ shift: Bool, _ command: Bool) -> Void
    var double: () -> Void
    var isSelected: () -> Bool
    var targets: () -> [URL]
    var image: () -> NSImage

    final class V: NSView, NSDraggingSource {
        var owner: RowInteraction!
        private var pending: (Bool, Bool)?
        private var start = NSPoint.zero
        private var dragging = false

        // Right-clicks and ctrl-clicks fall through to the row's context menu.
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let e = NSApp.currentEvent, e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control)) { return nil }
            return super.hitTest(point)
        }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 { owner.double(); return }
            let shift = event.modifierFlags.contains(.shift), command = event.modifierFlags.contains(.command)
            start = event.locationInWindow; dragging = false; pending = nil
            // Pressing an already selected row keeps the selection so all of it can be dragged; a plain click then narrows it on mouse-up.
            if owner.isSelected() && !shift && !command { pending = (false, false) } else { owner.click(shift, command) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
            dragging = true; pending = nil
            let urls = owner.targets()
            let icon = owner.image()
            let items = urls.enumerated().map { i, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(NSRect(x: CGFloat(i % 6) * 4, y: -CGFloat(i % 6) * 4, width: 48, height: 48), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if let p = pending, !dragging { owner.click(p.0, p.1) }
            pending = nil
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.owner = self; return v }
    func updateNSView(_ v: V, context: Context) { v.owner = self }
}
