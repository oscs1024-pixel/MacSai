import XCTest
@testable import MacCleanKit
import Security

/// Proves the XPC helper's signature-validation layer actually rejects
/// callers whose signature doesn't match a required identifier. The
/// production stub in HelperTool.swift (before this work) returned
/// `pid > 0`, i.e. true for every local process — a clean local
/// privilege-escalation vector.
///
/// These tests assert the validator's contract directly. The end-to-end
/// XPC plumbing (listener.setCodeSigningRequirement, audit token
/// extraction) is exercised by macOS itself at connect time; here we
/// focus on the requirement-string + SecCode round-trip we ship.
final class XPCSignatureGuardTests: XCTestCase {

    private func selfCode() throws -> SecCode {
        let code = try XCTUnwrap(XPCSignatureGuard.currentProcessCode())
        return code
    }

    // MARK: - The bug: must REJECT non-matching identifier

    /// SPEC: a caller whose identifier doesn't match the requirement must
    /// be rejected. The legacy stub returned true unconditionally — this
    /// test fails until the real SecRequirement validation lands.
    func testRejects_wrongIdentifier() throws {
        let code = try selfCode()
        let requirement = "identifier \"com.zztop.absolutely.not.macclean\""
        let ok = XPCSignatureGuard.validate(
            callerCode: code, requirement: requirement
        )
        XCTAssertFalse(ok,
            "validator MUST reject a caller whose identifier doesn't match — " +
            "a true return here is the local privilege escalation hole the " +
            "audit found in HelperTool.verifyCallerSignature."
        )
    }

    // MARK: - Defense in depth: must REJECT malformed requirement

    /// SPEC: a malformed requirement string is fail-closed (returns false),
    /// not silently accepted. A future config typo shouldn't open the door.
    func testRejects_malformedRequirement() throws {
        let code = try selfCode()
        let ok = XPCSignatureGuard.validate(
            callerCode: code, requirement: "this is not a valid requirement"
        )
        XCTAssertFalse(ok,
            "malformed requirement strings must fail closed (false), not open")
    }

    func testRejects_emptyRequirement() throws {
        let code = try selfCode()
        let ok = XPCSignatureGuard.validate(callerCode: code, requirement: "")
        XCTAssertFalse(ok, "empty requirement string must not be a free pass")
    }

    // MARK: - Sanity: must ACCEPT a matching identifier

    /// SPEC: when the requirement does match the caller's identifier, the
    /// validator returns true. We don't know exactly what xctest's
    /// identifier is across CI/local, so convert the running-code reference
    /// to a static-code reference, read its signing identifier, then feed
    /// that back into the requirement.
    func testAccepts_matchingIdentifierFromOwnSigningInfo() throws {
        let code = try selfCode()

        // SecCode and SecStaticCode are sibling CFTypes, not subclasses —
        // `as!` between them is undefined and SIGTRAPs on macOS 15.
        // Convert properly via SecCodeCopyStaticCode.
        var staticCode: SecStaticCode?
        let convertStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        try XCTSkipUnless(
            convertStatus == errSecSuccess && staticCode != nil,
            "SecCodeCopyStaticCode failed (status \(convertStatus))"
        )

        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode!,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        try XCTSkipUnless(
            status == errSecSuccess && info != nil,
            "test process has no extractable signing info on this build"
        )
        let dict = info! as NSDictionary
        guard let identifier = dict["identifier"] as? String else {
            throw XCTSkip("test process's SecCode has no identifier field")
        }

        let requirement = "identifier \"\(identifier)\""
        let ok = XPCSignatureGuard.validate(
            callerCode: code, requirement: requirement
        )
        XCTAssertTrue(ok,
            "validator must ACCEPT when the requirement's identifier matches " +
            "the caller's actual signing identifier (got: \(identifier))")
    }

    // MARK: - currentProcessCode sanity

    func testCurrentProcessCode_returnsValidReference() {
        XCTAssertNotNil(XPCSignatureGuard.currentProcessCode(),
            "every running process has a SecCode for itself — getter shouldn't return nil")
    }

    // MARK: - Production requirement strings parse cleanly

    /// SPEC: the requirement strings the helper + client ship in production
    /// must be syntactically valid. A typo (missing quote, bad operator)
    /// would make the requirement unparseable, which would either crash
    /// HelperTool.run() at startup or silently fall closed and refuse
    /// everything. Lock the syntax in here.
    func testProductionRequirementStrings_areWellFormed() throws {
        let helperListenerRequirement =
            MCConstants.codeSigningRequirement(for: MCConstants.bundleIdentifier)
        let clientConnectionRequirement =
            MCConstants.codeSigningRequirement(for: MCConstants.helperBundleIdentifier)

        for req in [helperListenerRequirement, clientConnectionRequirement] {
            var parsed: SecRequirement?
            let status = SecRequirementCreateWithString(
                req as CFString, [], &parsed
            )
            XCTAssertEqual(status, errSecSuccess,
                "production requirement \(req) must parse; got status \(status)")
            XCTAssertNotNil(parsed)
        }
    }

    // MARK: - The requirement must pin the Apple anchor + Team ID

    /// SPEC: an `identifier`-only requirement is forgeable — any local process
    /// can ad-hoc sign itself with our bundle id and satisfy it, then drive the
    /// root helper's RPCs (local privilege escalation). The shipped requirement
    /// MUST additionally pin `anchor apple generic` and our Developer ID Team
    /// ID. This test fails loudly if anyone weakens it back to identifier-only.
    func testProductionRequirement_pinsAppleAnchorAndTeamID() {
        let req = MCConstants.codeSigningRequirement(for: MCConstants.bundleIdentifier)
        XCTAssertTrue(req.contains("anchor apple generic"),
            "requirement must pin the Apple anchor so an ad-hoc signature can't satisfy it")
        XCTAssertTrue(
            req.contains("certificate leaf[subject.OU] = \"\(MCConstants.teamIdentifier)\""),
            "requirement must pin our Developer ID Team ID (\(MCConstants.teamIdentifier))")
    }
}
