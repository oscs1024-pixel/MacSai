cask "mac-clean" do
  version "1.0.0"
  sha256 "bc064e7808f7451b556e9d37cba241216f602f3c9d6c71cccc53a989678d9313"

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
