import SwiftUI
import UniformTypeIdentifiers
import MovieCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)   // needed when launched as a bare executable
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MovieMakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var chat = ChatModel()
    @StateObject private var search = SoundSearchModel()

    init() {
        // Development aid: `MovieMaker --snapshot /some/folder` draws the interface with a sample project into PNG files and quits.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.async { Task { @MainActor in await Snapshot.run(to: folder); exit(0) } }
        }
    }
    var body: some Scene {
        WindowGroup("Eclipse") {
            ContentView().environmentObject(model).environmentObject(chat).environmentObject(search)
                .navigationTitle(model.title)
                .onOpenURL { model.load($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newProject() }.keyboardShortcut("n")
                Button("Open…") { model.open() }.keyboardShortcut("o")
                Button("Save") { model.save() }.keyboardShortcut("s")
                Button("Save As…") { model.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Duplicate (save a copy)…") { model.duplicateProject() }
                Divider()
                Menu("New from Template") {
                    ForEach(AppModel.builtInTemplates, id: \.name) { t in Button(t.name) { model.newProject(width: t.width, height: t.height) } }
                    if !model.userTemplates.isEmpty {
                        Divider()
                        ForEach(model.userTemplates, id: \.self) { url in Button(url.deletingPathExtension().lastPathComponent) { model.newProject(fromTemplate: url) } }
                    }
                }
                Button("Save as Template") { model.saveAsTemplate() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.editor.undo() }.keyboardShortcut("z").disabled(!model.editor.canUndo)
                Button("Redo") { model.editor.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.editor.canRedo)
            }
            CommandMenu("Clip") {
                Button("Split at Playhead") { model.splitAtPlayhead() }.keyboardShortcut("b")
                Button("Duplicate") { model.duplicateSelection() }.keyboardShortcut("d")
                Button("Group") { model.groupSelection() }.keyboardShortcut("g")
                Button("Ungroup") { model.ungroupSelection() }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
