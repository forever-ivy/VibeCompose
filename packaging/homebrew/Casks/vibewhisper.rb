cask "vibewhisper" do
  version "0.1.0"
  # Fail closed until scripts/update_homebrew_cask.sh records the exact
  # checksum of a notarized release artifact.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/forever-ivy/vibewhisper/releases/download/v#{version}/VibeWhisper-#{version}-macos-arm64.zip"
  name "VibeWhisper"
  desc "Native push-to-talk voice input for macOS"
  homepage "https://github.com/forever-ivy/vibewhisper"

  depends_on macos: ">= :ventura"

  app "VibeWhisper.app"
end
