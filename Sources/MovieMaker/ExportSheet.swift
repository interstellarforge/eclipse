import SwiftUI
import MovieCore

struct ExportSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Export").font(.title2.bold())
                Spacer()
                Button("Close") { model.showExport = false }.disabled(model.exporting)
            }
            GroupBox("One file") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Size", selection: $model.exportPreset) {
                        Text("Movie size (\(model.project.width)×\(model.project.height))").tag(ExportPreset?.none)
                        ForEach(ExportPreset.allCases, id: \.self) { Text($0.title).tag(ExportPreset?.some($0)) }
                    }.disabled(model.exporting)
                    if model.exportPreset == nil {
                        Picker("Quality", selection: $model.exportShortSide) {
                            Text("720p").tag(720); Text("1080p").tag(1080); Text("4K").tag(2160)
                        }.pickerStyle(.segmented).disabled(model.exporting)
                    } else {
                        Text("Clips are fitted inside this frame; empty space is black. Use Picture size and position on a clip to fill it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("H.264 video and AAC sound in an MP4 file.").font(.caption).foregroundStyle(.secondary)
                    Button("Export…") { model.startExport() }.disabled(model.exporting)
                }.padding(6)
            }
            GroupBox("Several formats at once") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ExportPreset.allCases, id: \.self) { preset in
                        Toggle(preset.title, isOn: Binding(get: { model.batchPresets.contains(preset) },
                                                           set: { if $0 { model.batchPresets.insert(preset) } else { model.batchPresets.remove(preset) } }))
                            .disabled(model.exporting)
                    }
                    Button("Export all ticked to a folder…") { model.startBatchExport() }.disabled(model.exporting || model.batchPresets.isEmpty)
                }.padding(6)
            }
            GroupBox("Subtitles") {
                HStack {
                    Text("Titles on the Captions track (or all titles) as an .srt file.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save .srt…") { model.exportSubtitles() }
                }.padding(6)
            }
            if let progress = model.exportProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    HStack {
                        Text(model.exportMessage ?? "Exporting… \(Int(progress * 100))%").font(.caption)
                        Spacer()
                        Button("Cancel") { model.cancelExport() }
                    }
                }
            } else if let message = model.exportMessage {
                Text(message).font(.callout)
            }
        }
        .padding(18).frame(width: 440)
    }
}
