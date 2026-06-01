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
        engine: CleaningEngine,
        onProgress: (@Sendable (CleaningEngine.Progress) -> Void)? = nil
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

        // Dedup ancestors/descendants before dispatch. Scanner emits both
        // a directory AND every file inside it as separate items. Without
        // this filter the engine trashes the directory in one move,
        // then loops through every descendant — each of which now
        // points at a path that no longer exists, producing
        // "no such file" errors per descendant (one user reported 49,918
        // of them on a single Smart Scan). Keep ancestors; drop anything
        // whose URL lives under one.
        let dedupedTrashItems = Self.prunedToParents(trashItems)
        let trashResult = await engine.clean(items: dedupedTrashItems, mode: .trash,
                                             onProgress: onProgress)
        let thinResult = await thinSelectedBinaries(thinItems)
        return CleaningEngine.CleanResult(
            removedCount: trashResult.removedCount + thinResult.removedCount,
            freedBytes: trashResult.freedBytes + thinResult.freedBytes,
            errors: trashResult.errors + thinResult.errors,
            skippedCount: trashResult.skippedCount + thinResult.skippedCount
        )
    }

    /// Runs `ThinAppBundleOperation` against each item (item.url = bundle
    /// path) and folds the per-bundle outcomes into a
    /// `CleaningEngine.CleanResult` so the caller's "X items, Y MB freed"
    /// UI summary keeps working uniformly.
    private static func thinSelectedBinaries(
        _ items: [FileItem]
    ) async -> CleaningEngine.CleanResult {
        guard !items.isEmpty else {
            return CleaningEngine.CleanResult(
                removedCount: 0, freedBytes: 0, errors: [], skippedCount: 0
            )
        }
        let op = ThinAppBundleOperation()
        let targetArch = BundleHostInfo.current.hostArch
        var bundleCount = 0
        var savedBytes: UInt64 = 0
        var errors: [CleaningEngine.CleanError] = []
        for item in items {
            do {
                let r = try await op.thin(bundle: item.url, to: targetArch)
                bundleCount += 1
                savedBytes += r.bytesSaved
                for (path, msg) in r.perBinaryErrors {
                    errors.append(CleaningEngine.CleanError(
                        path: path, error: "binary thin failed: \(msg)"
                    ))
                }
            } catch {
                errors.append(CleaningEngine.CleanError(
                    path: item.url.path(percentEncoded: false),
                    error: "bundle thin failed: \(error.localizedDescription)"
                ))
            }
        }
        return CleaningEngine.CleanResult(
            removedCount: bundleCount,
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
        engine: CleaningEngine,
        onProgress: (@Sendable (CleaningEngine.Progress) -> Void)? = nil
    ) async -> CleaningEngine.CleanResult {
        let filtered = items.filter { selectedItems.contains($0.url) }
        let deduped = Self.prunedToParents(filtered)
        return await engine.clean(items: deduped, mode: .trash,
                                  onProgress: onProgress)
    }

    /// Returns `items` with any FileItem whose URL is a strict descendant
    /// of another FileItem's URL removed. Trashing the ancestor takes
    /// the descendants with it; dispatching the descendants separately
    /// just produces "no such file" errors once the parent's gone.
    ///
    /// O(n log n): sort by path length ascending, then sweep — for each
    /// item, drop it iff any already-kept item's path is a prefix
    /// (ending at a `/` boundary).
    static func prunedToParents(_ items: [FileItem]) -> [FileItem] {
        guard items.count > 1 else { return items }
        let sorted = items.sorted {
            $0.url.path(percentEncoded: false).count < $1.url.path(percentEncoded: false).count
        }
        var keptPaths: [String] = []
        keptPaths.reserveCapacity(sorted.count)
        var kept: [FileItem] = []
        kept.reserveCapacity(sorted.count)
        for item in sorted {
            let path = item.url.path(percentEncoded: false)
            // Look for an ancestor among already-kept paths. Boundary
            // check on '/' prevents "/foo" matching "/foobar".
            let hasAncestor = keptPaths.contains { ancestor in
                path != ancestor &&
                path.hasPrefix(ancestor) &&
                (ancestor.hasSuffix("/") || path.dropFirst(ancestor.count).first == "/")
            }
            if !hasAncestor {
                kept.append(item)
                keptPaths.append(path)
            }
        }
        return kept
    }
}
