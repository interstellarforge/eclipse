import Foundation

/// Returns the target nearest to `t` within `threshold`, else `t`.
public func snap(_ t: Ms, to targets: [Ms], threshold: Ms) -> Ms {
    let best = targets.min { abs($0 - t) < abs($1 - t) }
    if let best, abs(best - t) <= threshold { return best }
    return t
}
