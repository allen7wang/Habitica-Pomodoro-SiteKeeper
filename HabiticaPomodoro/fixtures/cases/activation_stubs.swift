import Foundation

// The Mac activation body normally runs after startup has accepted its data.
enum FixtureMacDataStatus {
    case loading, ready
}

var dataStatus = FixtureMacDataStatus.ready

// Fixture compilation ONLY: activation-body adapters do not initialize the real
// iOS grant owner or call bookmark/security-scope APIs. All directory switches
// use the verified synthetic DEBUG isolatedDirectory seam, not a folder grant.
final class ICloudFolderGrant {
    static let shared = ICloudFolderGrant()
    func syncFromCloudIfNeeded() { PomodoroFileChanges.shared.syncFromDiskIfNeeded() }
    func refreshStatus() {}
}
