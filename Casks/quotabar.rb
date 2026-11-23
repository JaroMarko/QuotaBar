cask "quotabar" do
  version "1.7.0"
  sha256 "d25726272ddf5d9e10c47387162cde555f408523f978dd057e8becf68b82d4c9"

  url "https://github.com/JaroMarko/QuotaBar/releases/download/v#{version}/QuotaBar-#{version}-arm64.zip"
  name "QuotaBar"
  desc "Menu bar monitor for Claude, Codex and Gemini quotas"
  homepage "https://github.com/JaroMarko/QuotaBar"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "QuotaBar.app"
end
