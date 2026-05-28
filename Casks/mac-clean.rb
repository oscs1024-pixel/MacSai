cask "mac-clean" do
  version "1.0.0"
  sha256 "fd53a44c0928e1f2b7e3c14949bacb80cb18018b7451ebd4d0526d5a9f8c4729"

  url "https://github.com/iliyami/MacClean/releases/download/v#{version}/MacClean-#{version}.dmg",
      verified: "github.com/iliyami/MacClean/"
  name "Mac Clean"
  desc "Open-source Mac cleaner, optimizer, and malware scanner"
  homepage "https://github.com/iliyami/MacClean"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Mac Clean.app"

  zap trash: [
    "~/Library/Application Support/Mac Clean",
    "~/Library/Caches/com.macclean.app",
    "~/Library/Logs/MacClean",
    "~/Library/Preferences/com.macclean.app.plist",
    "~/Library/Saved Application State/com.macclean.app.savedState",
  ]

  caveats <<~EOS
    Mac Clean is not notarized by Apple (it's an open-source project without a paid
    Developer ID). To launch it the first time:

      sudo xattr -dr com.apple.quarantine "/Applications/Mac Clean.app"

    Or right-click the app in Finder and choose "Open" to bypass Gatekeeper.

    Some features (Mail, Safari, Privacy scans) require Full Disk Access:
      System Settings → Privacy & Security → Full Disk Access
  EOS
end
