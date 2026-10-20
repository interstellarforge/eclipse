import AVFoundation
import AppKit
import Foundation
import ImageIO
import MovieCore
import UniformTypeIdentifiers

/// One real assistant session: the installed `claude` drives a real Editor through the real MCP server.
/// `swift run ReadmeMedia <folder> assistant "<prompt>"` records the events and the movie it built; `... assistant-render` makes the video from the recording.
struct Step: Codable { var kind: String; var text: String; var tool: String?; var error: Bool?; var frame: String?; var clips: Int?; var ms: Int? }

@MainActor
func recordAssistant(out: URL, prompt: String) async throws {
    let footage = out.appendingPathComponent("footage")
    let editor = Editor()
    try editor.apply(.setFormat(width: 1280, height: 720, fps: 30))
    for s in Scene.allCases { try editor.apply(.addAsset(try await Asset.load(url: footage.appendingPathComponent("\(s.rawValue).mp4")))) }
    let host = MCPHost(importMedia: { try await Asset.load(url: $0) }, playhead: { 0 })
    let token = "readme-demo"
    let server = MCPServer(editor: editor, host: host, token: token)
    try await server.start()
    let frames = out.appendingPathComponent("assistant-frames"); try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    var steps: [Step] = [Step(kind: "user", text: prompt)]
    var names: [String: String] = [:], text = "", n = 0
    func flush() { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { steps.append(Step(kind: "text", text: t)) }; text = "" }
    let (events, _) = ClaudeRunner.run(prompt: prompt, sessionID: nil, port: server.port, token: token)
    for await ev in events {
        switch ev {
        case .textDelta(let d): text += d
        case .toolUse(let id, let name, let input):
            flush(); names[id] = name
            steps.append(Step(kind: "tool", text: input, tool: name))
        case .toolResult(let id, let isError):
            if var last = steps.last(where: { $0.kind == "tool" && $0.tool == names[id] && $0.frame == nil && $0.error == nil }), let i = steps.lastIndex(where: { $0.kind == "tool" && $0.tool == last.tool && $0.error == nil }) {
                last.error = isError
                let p = editor.project
                last.clips = p.tracks.flatMap(\.clips).count; last.ms = Int(p.duration)
                if p.duration > 0, !isError, ["build_edit", "add_clip", "add_transition", "set_look", "add_effect", "add_overlay", "add_title", "apply_template", "add_music"].contains(last.tool ?? "") {
                    n += 1
                    if let png = try? await FrameRenderer.png(p, atMs: Ms(Double(p.duration) * 0.3), maxSize: 960) { let name = String(format: "f%03d.png", n); try png.write(to: frames.appendingPathComponent(name)); last.frame = name }
                }
                steps[i] = last
            }
        case .finished(_, let result, let cost): flush(); print("finished, cost \(cost ?? 0)"); _ = result
        case .failed(let m): print("FAILED: \(m)"); flush()
        default: break
        }
    }
    server.stop()
    let final = out.appendingPathComponent("assistant-result.mp4")
    try await Exporter.export(editor.project, to: final)
    try JSONEncoder().encode(steps).write(to: out.appendingPathComponent("assistant-session.json"))
    try? editor.project.write(to: out.appendingPathComponent("assistant-project.moviemaker"))
    print("steps: \(steps.count), movie \(editor.project.duration) ms")
}
