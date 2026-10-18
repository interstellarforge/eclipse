import Foundation
import MovieCore

// New checks (separate from CoreChecks, whose single huge file takes minutes to compile):
//   swift build --product NewChecks && .build/debug/NewChecks
setvbuf(stdout, nil, _IONBF, 0)   // progress lines appear immediately, even if a check crashes
CreativeGuard.enabled = false   // the guard has its own checks; the other checks build plain edits
let fixtures = try await Fixtures.make()
defer { fixtures.cleanUp() }
try await runPhase1Checks(fixtures)
try await runTransitionChecks()
try await runOverlayTitleChecks(fixtures)
try await runMusicChecks()
try await runToolChecks(fixtures)
try await runTemplateChecks(fixtures)
try await runRampMatchReframeChecks(fixtures)
try await runAskGhostChecks(fixtures)
print("new checks passed")
