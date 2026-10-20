import AppKit
import SwiftUI
import MovieCore

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    @StateObject private var promptCategory = PromptCategory()
    @StateObject private var scriptPop = Flag()
    final class PromptCategory: ObservableObject { @Published var name = PromptLibrary.categories[0] }

    /// Consecutive identical tool rows collapse into one "×N" row.
    static func grouped(_ messages: [ChatMessage]) -> [(ChatMessage, Int)] {
        var out: [(ChatMessage, Int)] = []
        for m in messages {
            if m.role == .tool, let last = out.last, last.0.role == .tool, last.0.text == m.text, !m.failed, !last.0.failed {
                var merged = m; merged.done = m.done && last.0.done
                out[out.count - 1] = (ChatMessage(id: last.0.id, role: .tool, text: m.text, toolID: m.toolID, done: merged.done), last.1 + 1)
            } else { out.append((m, 1)) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.offlineMode { offlineBanner }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty { welcome }
                    ForEach(Self.grouped(chat.messages), id: \.0.id) { MessageRow(message: $0.0, count: $0.1) }
                    if let q = model.pendingQuestion { QuestionCard(question: q) }
                    if chat.running, chat.messages.last.map({ $0.role == .assistant && !$0.done }) != true { TypingDots() }
                }.padding(12)
            }
            .defaultScrollAnchor(.bottom)
            composer
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
            Text("Offline: Claude can't see your videos").font(.system(size: 11.5)).foregroundStyle(Theme.text)
            Spacer()
            Button("Select parts…") {
                model.openSelection(reason: "Mark the parts of your videos that matter") { text in chat.send(text, shown: "I marked the parts that matter.", using: model) }
            }.controlSize(.small).disabled(chat.running)
        }.padding(.horizontal, 12).padding(.vertical, 6).background(Theme.accentSoft)
    }

    private var scriptMenu: some View {
        Button { scriptPop.on.toggle() } label: {
            Image(systemName: model.scriptLevel == .off ? "text.book.closed" : "text.book.closed.fill").font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.scriptLevel == .off ? Theme.text : Theme.accent).frame(width: 30, height: 28)
                .background(model.scriptLevel == .off ? Color.clear : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help("Script mode: \(model.scriptLevel.rawValue)")
            .popover(isPresented: $scriptPop.on, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Script mode").font(.system(size: 13, weight: .semibold))
                    Text("How much the Assistant plans before it builds.").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                    ForEach(ScriptLevel.allCases, id: \.self) { level in
                        Button { model.scriptLevel = level; scriptPop.on = false } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: level == model.scriptLevel ? "checkmark.circle.fill" : "circle").foregroundStyle(level == model.scriptLevel ? Theme.accent : Theme.dim).padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.rawValue).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                                    Text(level.summary).font(.system(size: 11.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(level == model.scriptLevel ? Theme.accentSoft : Theme.raised, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(14).frame(width: 320)
            }
    }

    private var agentMenu: some View {
        Menu {
            Section("Agent") {
                ForEach(chat.agents) { a in
                    Button { chat.select(a) } label: { Label(a.name, systemImage: a.id == chat.agent?.id ? "checkmark" : "terminal") }
                }
            }
            Divider()
            Button("Choose another claude…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.message = "Choose a claude executable"
                if panel.runModal() == .OK, let url = panel.url { chat.addCustomAgent(url) }
            }
            Button("Rescan this Mac") { chat.refreshAgents() }
        } label: {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).frame(width: 30, height: 28)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(chat.agent.map { "Agent: \($0.name). \(chat.agentSkillCount) of its skills are available to the assistant." } ?? "No agent found")
            .onAppear { if chat.agents.isEmpty { chat.refreshAgents() } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            Text("AI Assistant").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text("BETA").font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            IconButton(symbol: model.offlineMode ? "lock.fill" : "lock.open", help: model.offlineMode ? "Offline is ON: Claude never sees your videos. Click to turn off." : "Offline mode: keep your videos private (Claude can't look at or analyse them)", active: model.offlineMode) { model.offlineMode.toggle() }
            scriptMenu
            agentMenu
            IconButton(symbol: "graduationcap", help: "Director skills Claude can use") { chat.showSkills = true }.popover(isPresented: $chat.showSkills) { SkillsPopover() }
            Menu {
                Button("New chat") { chat.newChat(); model.answerQuestion("(chat closed)") }.disabled(chat.messages.isEmpty)
                if !chat.history.isEmpty { Divider() }
                ForEach(chat.history.prefix(30)) { item in
                    Button("\(item.title)  ·  \(item.updated.formatted(.relative(presentation: .named)))") { chat.open(item.id) }.disabled(chat.running)
                }
                if !chat.history.isEmpty {
                    Divider()
                    Menu("Delete a chat") { ForEach(chat.history.prefix(30)) { item in Button(item.title, role: .destructive) { chat.delete(item.id) } } }
                }
            } label: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 15)).foregroundStyle(Theme.text).frame(width: 30, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Earlier conversations and new chat")
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn your ideas into a great edit.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Claude looks at your clips, plans the film like a director and edits the timeline for you. Everything can be undone with ⌘Z. It uses your installed Claude Code and can only use this editor's tools: no files, no shell.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
            HStack(spacing: 8) {
                modeButton("Guided edit", "list.bullet.clipboard", "Claude asks you step by step") { chat.startGuidedEdit(using: model) }
                modeButton("Ghost edit", "sparkles.rectangle.stack", "An alternative you can preview") { chat.ghostMode = true }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(PromptLibrary.categories, id: \.self) { c in Chip(title: c, selected: promptCategory.name == c) { promptCategory.name = c } } }
            }
            ForEach(PromptLibrary.ideas(in: promptCategory.name)) { idea in
                HStack(spacing: 10) {
                    Text(idea.emoji).font(.system(size: 22)).frame(width: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(idea.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(idea.subtitle).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    IconButton(symbol: "pencil", help: "Put it in the box to edit first") { chat.draft = idea.prompt }
                    IconButton(symbol: "paperplane.fill", help: "Send it now", size: 12) { chat.send(idea.prompt, shown: idea.title, using: model) }.opacity(model.mcpToken == nil ? 0.35 : 1)
                }
                .padding(.horizontal, 10).padding(.vertical, 8).card(radius: 11)
                .contentShape(Rectangle()).onTapGesture { chat.draft = idea.prompt }
            }
        }
    }

    private func modeButton(_ title: String, _ symbol: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: symbol).foregroundStyle(Theme.accent).font(.system(size: 16))
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10).card(radius: 11)
        }.buttonStyle(.plain).disabled(model.mcpToken == nil || chat.running)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chat.ghostMode {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack").foregroundStyle(Theme.accent)
                    Text(model.selectedClip != nil ? "Ghost edit of the selected part. Say what you want, e.g. “make this much more spectacular”." : "Ghost edit of the whole movie (select clips first to limit it).")
                        .font(.system(size: 11)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { chat.ghostMode = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }.buttonStyle(.plain)
                }.padding(8).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            }
            ForEach(Array(chat.queue.enumerated()), id: \.offset) { i, text in
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Theme.dim)
                    Text(text).font(.system(size: 11.5)).lineLimit(2).foregroundStyle(Theme.text)
                    Spacer(minLength: 4)
                    Button("Send now") { chat.sendNow(i, using: model) }.buttonStyle(.link).font(.system(size: 11.5, weight: .medium)).help("Interrupt Claude and send this right away")
                    Button { chat.removeQueued(i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }.buttonStyle(.plain).help("Remove from the queue")
                }.padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.ghostMode ? "Describe the ghost edit…" : "Describe what you'd like to create…", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...6).padding(10).card(radius: 11)
                    .onSubmit { chat.send(using: model) }
                if chat.running {
                    if !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { chat.send(using: model) } label: { Image(systemName: "text.append").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.accent.opacity(0.75), in: RoundedRectangle(cornerRadius: 11)) }
                            .buttonStyle(.plain).help("Add to the queue: sent when Claude is done (Return does the same)")
                    }
                    Button { chat.stop(); model.answerQuestion("(stopped)") } label: { Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.accent, in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain).help("Stop")
                } else {
                    Button { chat.send(using: model) } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.accent, in: RoundedRectangle(cornerRadius: 11)) }
                        .buttonStyle(.plain).help("Send")
                        .disabled(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.mcpToken == nil)
                        .opacity(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            }
            if !chat.messages.isEmpty && !chat.ghostMode {
                HStack(spacing: 6) {
                    Chip(title: "Guided edit") { chat.startGuidedEdit(using: model) }.disabled(chat.running)
                    Chip(title: "Ghost edit") { chat.ghostMode = true }.disabled(chat.running)
                    Chip(title: "Suggest improvements") { chat.send("Review my current edit and suggest three concrete improvements. Do not change anything yet.", using: model) }.disabled(chat.running)
                }
            }
        }.padding(12)
    }
}

/// A question from Claude with answer buttons and a text box.
/// One answer of a question from Claude; the info icon explains what it means and what Claude will do (also on hover over the whole row).
struct OptionRow: View {
    let option: AskOption
    let pick: () -> Void
    @StateObject private var hover = Flag()
    @StateObject private var tip = Flag()

    var body: some View {
        HStack(spacing: 8) {
            Button(action: pick) {
                Text(option.label).font(.system(size: 12.5)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !option.info.isEmpty {
                Button { tip.on.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(tip.on ? Theme.accent : Theme.dim).frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help(option.info)   // tooltip on hover over the icon only; click for a larger note
                    .popover(isPresented: $tip.on, arrowEdge: .leading) {
                        Text(option.info).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).padding(12).frame(width: 260, alignment: .leading)
                    }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accent.opacity(hover.on ? 0.8 : 0.35)))
        .onHover { hover.on = $0 }
    }
}

struct QuestionCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    let question: PendingQuestion
    @StateObject private var typed = Typed()
    final class Typed: ObservableObject { @Published var text = "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.accent); Text("Claude asks").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                Spacer()
                Button { chat.stop(); model.answerQuestion("(the user dismissed the question and stopped the task)") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
                    .buttonStyle(.plain).help("Dismiss this question and stop")
            }
            Text(question.question).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            ForEach(question.options, id: \.label) { option in OptionRow(option: option) { chat.answer(option.label, using: model) } }
            if question.allowText {
                HStack {
                    TextField("Or type your own answer…", text: $typed.text).textFieldStyle(.roundedBorder).onSubmit { send() }
                    Button("Send") { send() }.disabled(typed.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.padding(12).card(Theme.accentSoft)
    }

    private func send() {
        let text = typed.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        chat.answer(text, using: model)
    }
}

/// Animated "…" shown while Claude works, like a chat app's typing indicator.
struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (sin(t * 5 - Double(i) * 0.9) + 1) / 2
                    Circle().fill(Theme.dim).frame(width: 7, height: 7).opacity(0.35 + 0.65 * phase).offset(y: -3 * phase)
                }
            }.padding(.horizontal, 14).padding(.vertical, 12).background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("Claude is typing")
    }
}

struct MessageRow: View {
    let message: ChatMessage
    var count = 1

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text).font(.system(size: 12.5)).padding(10).foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled)
        case .assistant:
            Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                .font(.system(size: 12.5)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        case .tool:
            HStack(spacing: 6) {
                if !message.done { ProgressView().controlSize(.mini) }
                else { Image(systemName: message.failed ? "xmark.circle.fill" : "checkmark.circle.fill").foregroundStyle(message.failed ? .red : .green).font(.system(size: 11)) }
                Text(count > 1 ? "\(message.text) ×\(count)" : message.text).font(.system(size: 11.5)).lineLimit(1).foregroundStyle(Theme.dim)
            }.frame(maxWidth: .infinity, alignment: .leading)
        case .notice:
            Text(message.text).font(.system(size: 12)).foregroundStyle(message.failed ? .red : Theme.dim).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
    }
}

struct SkillsPopover: View {
    private let skills = Skills.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Director skills").font(.headline)
            Text("Craft guides Claude reads before it edits. Add your own as .md files; the first line `description: …` is the summary. A file with a built-in's name replaces it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(skills, id: \.name) { skill in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack { Text(skill.name).font(.callout.weight(.semibold)); if skill.fromAgent { Text("agent").font(.caption2).foregroundStyle(Theme.accent) } else if !skill.isBuiltIn { Text("yours").font(.caption2).foregroundStyle(.orange) } }
                            Text(skill.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxHeight: 280)
            HStack {
                Button("Open skills folder") { if let dir = Skills.userFolder() { NSWorkspace.shared.open(dir) } }
                Button("New skill…") {
                    guard let dir = Skills.userFolder() else { return }
                    var url = dir.appendingPathComponent("my-skill.md"), n = 2
                    while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("my-skill-\(n).md"); n += 1 }
                    try? "description: What this skill is for\n\n# My skill\n\nWrite instructions for Claude here.\n".write(to: url, atomically: true, encoding: .utf8)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }.padding(12).frame(width: 340)
    }
}
