cask "quotabar" do
  version "1.6.0"
  sha256 "d402b563a6997719438349215a3b902c37f680fc3275511c39d692dc8d94c3b3"

  url "https://github.com/JaroMarko/QuotaBar/releases/download/v#{version}/QuotaBar-#{version}-arm64.zip"
  name "QuotaBar"
  desc "Menu bar monitor for Claude, Codex and Gemini quotas"
  homepage "https://github.com/JaroMarko/QuotaBar"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "QuotaBar.app"
end
