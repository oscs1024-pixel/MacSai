import Foundation
import MacCleanKit

/// Single source of truth for "user clicked Clean."
///
/// Every view that has a Clean button MUST route through here. By centralizing
/// the call to `CleaningEngine` we guarantee:
///   1. The mode is always `.trash` (files recoverable from Trash, never silently
///      `.dryRun` which would report success without deleting anything).
///   2. Item-filtering logic (intersect scan results with user selection) is
///      identical across every module, so behavior can't drift per-view.
///   3. There's exactly one place to audit when reviewing the deletion path.
///
/// This existed to fix the regression where every view was passing `.dryRun`
/// — see `CleanIsNotDryRunRegressionTests` for the static guard that prevents
/// the bug from coming back, and `CleanActionsTests` for the behavioral
/// verification that the engine actually moves files.
public enum CleanActions {

    /// Execute a user-initiated Clean operation against the given engine.
    /// Used by views that display `[ScanResult]` with per-item selection.
    ///
    /// Routes by category: most items go through `engine.clean(..., .trash)`,
    /// but `.universalBinaries` items are thinned in place via
    /// `ThinBinaryOperation` instead — trashing an app's executable would
    /// break the app.
    @discardableResult
    public static func executeUserClean(
        results: [ScanResult],
        selectedItems: Set<URL>,
        engine: CleaningEngine
    ) async -> CleaningEngine.CleanResult {
        var trashItems: [FileItem] = []
        var thinItems: [FileItem] = []
        for result in results {
            for item in result.items where selectedItems.contains(item.url) {
                if result.category == .universalBinaries {
                    thinItems.append(item)
                } else {
                    trashItems.append(item)
                }
            }
        }

        let trashResult = await engine.clean(items: trashItems, mode: .trash)
        let thinResult = await thinSelectedBinaries(thinItems)
        return CleaningEngine.CleanResult(
            removedCount: trashResult.removedCount + thinResult.removedCount,
            freedBytes: trashResult.freedBytes + thinResult.freedBytes,
            errors: trashResult.errors + thinResult.errors,
            skippedCount: trashResult.skippedCount + thinResult.skippedCount
        )
    }

    /// Runs `ThinBinaryOperation` against each item and folds the per-binary
    /// outcomes into a `CleaningEngine.CleanResult` shape so the caller's
    /// "X items, Y MB freed" UI summary works uniformly.
    private static func thinSelectedBinaries(
        _ items: [FileItem]
    ) async -> CleaningEngine.CleanResult {
        guard !items.isEmpty else {
            return CleaningEngine.CleanResult(
                removedCount: 0, freedBytes: 0, errors: [], skippedCount: 0
            )
        }
        let op = ThinBinaryOperation()
        let targetArch = BundleHostInfo.current.hostArch
        var savedCount = 0
        var savedBytes: UInt64 = 0
        var errors: [CleaningEngine.CleanError] = []
        for item in items {
            do {
                let r = try await op.thin(binary: item.url, to: targetArch)
                savedCount += 1
                savedBytes += r.bytesSaved
            } catch {
                errors.append(CleaningEngine.CleanError(
                    path: item.url.path(percentEncoded: false),
                    error: "thin failed: \(error)"
                ))
            }
        }
        return CleaningEngine.CleanResult(
            removedCount: savedCount,
            freedBytes: savedBytes,
            errors: errors,
            skippedCount: 0
        )
    }

    /// Execute a user-initiated Clean operation against a flat list of items.
    /// Used by the Uninstaller, which surfaces `[FileItem]` (associated files
    /// for a single app) rather than `[ScanResult]`.
    @discardableResult
    public static func executeUserClean(
        items: [FileItem],
        selectedItems: Set<URL>,
        engine: CleaningEngine
    ) async -> CleaningEngine.CleanResult {
        let filtered = items.filter { selectedItems.contains($0.url) }
        return await engine.clean(items: filtered, mode: .trash)
    }
}
