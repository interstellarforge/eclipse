import AVFoundation
import Vision

/// Turns landscape footage into vertical (or square) footage and keeps the person or subject in view.
public enum SmartReframe {
    public struct Subject {
        public var time: Ms        // from the start of the clip, timeline time
        public var x: Double       // 0...1 across the source picture
        public var y: Double       // 0...1 from the bottom of the source picture
        public init(time: Ms, x: Double, y: Double) { self.time = time; self.x = x; self.y = y }
    }

    /// Finds the main subject over time: faces first, then people, then whatever draws the eye.
    public static func track(_ asset: Asset, sourceIn: Ms, length: Ms, speed: Double = 1, step: Ms = 700) async -> (subjects: [Subject], method: String) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = CMTime(value: 150, timescale: 1000); gen.requestedTimeToleranceAfter = CMTime(value: 150, timescale: 1000)
        let sourceTimes = stride(from: Ms(0), to: max(1, length), by: Int(step)).map { sourceIn + $0 }
        var subjects: [Subject] = []
        var methods: [String: Int] = [:]
        for await result in gen.images(for: sourceTimes.map { cm($0) }) {
            guard let image = try? result.image else { continue }
            let sourceTime = Ms((result.requestedTime.seconds * 1000).rounded())
            let (point, method) = subject(in: image)
            methods[method, default: 0] += 1
            subjects.append(Subject(time: Ms(Double(sourceTime - sourceIn) / speed), x: point.x, y: point.y))
        }
        subjects.sort { $0.time < $1.time }
        return (subjects, methods.max { $0.value < $1.value }?.key ?? "centre")
    }

    private static func subject(in image: CGImage) -> (CGPoint, String) {
        let faces = VNDetectFaceRectanglesRequest(), people = VNDetectHumanRectanglesRequest()
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest(), attention = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([faces, people, objects, attention])
        func biggest(_ boxes: [CGRect]) -> CGRect? { boxes.max { $0.width * $0.height < $1.width * $1.height } }
        if let box = biggest(faces.results?.map(\.boundingBox) ?? []) { return (CGPoint(x: box.midX, y: box.midY), "face") }
        if let box = biggest(people.results?.map(\.boundingBox) ?? []) { return (CGPoint(x: box.midX, y: box.midY), "person") }
        // No faces or people: an object that stands out (compact), else where the eye goes.
        if let box = biggest(objects.results?.first?.salientObjects?.map(\.boundingBox).filter { $0.width * $0.height < 0.6 } ?? []) { return (CGPoint(x: box.midX, y: box.midY), "most prominent object") }
        if let box = biggest(attention.results?.first?.salientObjects?.map(\.boundingBox) ?? []) { return (CGPoint(x: box.midX, y: box.midY), "most eye-catching area") }
        return (CGPoint(x: 0.5, y: 0.5), "centre")
    }

    /// Scale and keyframes that crop the fitted source to the canvas around the subject. Moves only when the subject moves.
    /// `sourceAspect` is width / height of the source picture; `canvas` the movie size.
    public static func keyframes(subjects: [Subject], sourceAspect: Double, canvas: CGSize, clipDuration: Ms) -> (scale: Double, frames: [Keyframe]) {
        let canvasAspect = canvas.width / canvas.height
        // Fitted source = the picture scaled to touch the canvas edges. To fill the canvas it is scaled up further.
        let horizontal = sourceAspect > canvasAspect
        let fill = horizontal ? sourceAspect / canvasAspect : canvasAspect / sourceAspect
        guard fill > 1.001 else { return (1, []) }
        let maxShift = (fill - 1) / 2
        func offset(_ subject: Subject) -> (Double, Double) {
            horizontal ? (max(-maxShift, min(maxShift, -(subject.x - 0.5) * fill)), 0) : (0, max(-maxShift, min(maxShift, -(subject.y - 0.5) * fill)))
        }
        // Smooth the subject path, then keep a keyframe only where the camera really needs to move.
        var smoothed: [(Ms, Double, Double)] = []
        var sx = 0.0, sy = 0.0
        for (i, s) in subjects.enumerated() {
            let (ox, oy) = offset(s)
            if i == 0 { sx = ox; sy = oy } else { sx += (ox - sx) * 0.8; sy += (oy - sy) * 0.8 }
            smoothed.append((s.time, sx, sy))
        }
        var frames: [Keyframe] = []
        for (time, ox, oy) in smoothed {
            let t = max(0, min(clipDuration, time))
            if let last = frames.last, abs(last.offsetX - ox) < 0.02 * fill, abs(last.offsetY - oy) < 0.02 * fill, t - last.time < 3_000 { continue }
            if frames.contains(where: { $0.time == t }) { continue }
            frames.append(Keyframe(time: t, scale: fill, offsetX: ox, offsetY: oy))
        }
        if frames.count == 1, let only = frames.first { frames = [Keyframe(time: 0, scale: fill, offsetX: only.offsetX, offsetY: only.offsetY)] }
        return (fill, frames)
    }
}

extension Editor {
    /// Frames the clip on its subject for the current canvas (set the canvas first, e.g. 9:16).
    @discardableResult
    public func reframeClip(_ clipID: UUID, subjects: [SmartReframe.Subject], sourceAspect: Double) throws -> Int {
        guard let clip = project.tracks.flatMap(\.clips).first(where: { $0.id == clipID }) else { throw EditError.notFound }
        let result = SmartReframe.keyframes(subjects: subjects, sourceAspect: sourceAspect, canvas: CGSize(width: project.width, height: project.height), clipDuration: clip.duration)
        guard !result.frames.isEmpty else { throw EditError.invalid("The picture already fills this canvas shape: nothing to reframe.") }
        try transaction {
            try apply(.setTransform(clipID, opacity: clip.opacity, scale: result.scale, offsetX: result.frames[0].offsetX, offsetY: result.frames[0].offsetY))
            try apply(.setKeyframes(clipID, result.frames.count > 1 ? result.frames : []))
        }
        return result.frames.count
    }
}
