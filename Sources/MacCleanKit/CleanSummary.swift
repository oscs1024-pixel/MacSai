import Foundation

/// What happened during a Clean operation. Designed for the post-clean
/// UI to render an honest message — '0 bytes cleaned up' is ambiguous
/// across three different outcomes (nothing selected, everything errored,
/// or genuinely no junk found), and the field combinations here let the
/// view distinguish them.
public struct CleanSummary: Sendable, Equatable {
    /// How many items the user had checked when they clicked Clean.
    /// Zero means the action ran with an empty selection — likely because
    /// every result category had `autoSelect = false` (e.g. Universal
    /// Binaries) and the user clicked Clean without manually checking
    /// anything.
    public let selectedCount: Int

    /// How many items actually got cleaned (moved to Trash). Always
    /// `<= selectedCount` — the difference is rejections (SafetyGuard
    /// + per-binary errors).
    public let removedCount: Int

    public let freedBytes: UInt64
    public let errorCount: Int

    /// First error's human-readable message, when there is one. The UI
    /// shows this directly in the completion screen instead of a generic
    /// "Check Console for details" line — saves the user from having to
    /// open Console.app to find out it was a limit/permission issue.
    public let firstErrorMessage: String?

    public init(
        selectedCount: Int,
        removedCount: Int,
        freedBytes: UInt64,
        errorCount: Int,
        firstErrorMessage: String? = nil
    ) {
        self.selectedCount = selectedCount
        self.removedCount = removedCount
        self.freedBytes = freedBytes
        self.errorCount = errorCount
        self.firstErrorMessage = firstErrorMessage
    }
}
