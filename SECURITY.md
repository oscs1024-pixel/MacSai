# Security Policy

Mac Sai deletes files on your Mac and runs a privileged XPC helper, so security matters more here than for most apps.

## Reporting a vulnerability

**Please do not open public GitHub issues for security vulnerabilities.**

Report them privately via [GitHub's Private Vulnerability Reporting](https://github.com/iliyami/MacSai/security/advisories/new):

1. Open the [Security tab](https://github.com/iliyami/MacSai/security) on the repository
2. Click **Report a vulnerability**
3. Include: the affected file or feature, reproduction steps, expected vs actual behavior, and a suggested fix if you have one

Expect an initial response within **72 hours**. Issues that risk data loss get same-day attention.

## Supported versions

Only the latest release on `main` is supported. Please upgrade rather than asking for backports.

| Version | Supported |
|---------|-----------|
| `main` (latest release) | ✅ |
| Older releases | ❌ |

## In scope

Reports about the following areas get priority:

- **`Sources/MacClean/Core/Cleaner/SafetyGuard.swift`** — bypasses of the protected-paths blocklist, the 10,000-file cap, or the symlink TOCTOU re-resolution
- **`Sources/MacClean/Core/Cleaner/CleaningEngine.swift`** — anything that causes data loss outside the intended scan results
- **`Sources/MacCleanHelper/`** — unauthorized callers reaching the privileged XPC helper, privilege escalation, or arbitrary command execution via the helper
- **`Sources/MacClean/Services/XPCClient.swift`** — code-signature validation bypass on either side of the XPC connection
- **Network exfiltration** — Mac Sai makes zero network calls by design; report any network activity you observe
- **TCC / Full Disk Access** — any path to silently gain or abuse FDA

## Out of scope

- Mac Sai not being Apple-notarized — intentional design choice, see the README
- Gatekeeper warnings on first launch via DMG — expected behavior
- General macOS bugs not specific to Mac Sai

## What we ask of you

- Give us a reasonable window to fix before public disclosure: **14 days for non-critical issues**, **immediate coordination for anything that risks user data**
- Don't test against other people's machines
- Don't pivot from a found vulnerability to access user data

## What you get

- Credit in the release notes (or stay anonymous if you prefer)
- Acknowledgment in this file for significant findings
- Our genuine thanks — Mac Sai is safer because of you

## Verifying a release matches the source

Mac Sai is ad-hoc signed (not Apple-notarized — see the README for why). To verify a release DMG corresponds to the source you reviewed, build it yourself:

```bash
git clone https://github.com/iliyami/MacSai.git
cd MacClean
git checkout v1.0.0   # or whichever release
bash scripts/build-dmg.sh
```

The DMG isn't bit-reproducible (ad-hoc signatures embed random nonces), but the source-to-binary build is straightforward and the behavior should match.

## Past advisories

None yet. Will be linked here when applicable.
