cask "airkwotes" do
  version "0.1.0"
  sha256 "6eeb2e6c02a9774712edc96a495c87a191fe77fe1a6471987e486ff7fdc55a3c"

  url "https://github.com/funkchi/AirKwotes/releases/download/v#{version}/AirKwotes-#{version}.dmg",
      verified: "github.com/funkchi/AirKwotes/"
  name "AirKwotes"
  desc "Menu-bar tracker for AI subscription quotas with a local relay"
  homepage "https://github.com/funkchi/AirKwotes"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  # NOTE: 0.1.x releases are unsigned. The postflight strips the Gatekeeper
  # quarantine flag so the first launch doesn't need a manual right-click → Open.
  app "AirKwotes.app"

  postflight do
    system_command("xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/AirKwotes.app"])
  end

  zap trash: [
    "~/Library/Preferences/ai.airkwotes.app.plist",
    "~/Library/Cookies/ai.airkwotes.app.binarycookies",
  ]
end
