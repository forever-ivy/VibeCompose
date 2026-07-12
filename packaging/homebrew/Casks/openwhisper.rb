cask "openwhisper" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/forever-ivy/openwhisper/releases/download/v#{version}/OpenWhisper-#{version}-macos-arm64.zip"
  name "OpenWhisper"
  desc "Native push-to-talk voice input for macOS"
  homepage "https://github.com/forever-ivy/openwhisper"

  depends_on macos: ">= :ventura"

  app "OpenWhisper.app"
end
