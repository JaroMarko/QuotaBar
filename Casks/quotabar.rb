cask "quotabar" do
  version "1.7.1"
  sha256 "e4307af02b97c3390bbb7fd4183e6ebb305fdf37d77404cd732f5e8dda4f305c"

  url "https://github.com/JaroMarko/QuotaBar/releases/download/v#{version}/QuotaBar-#{version}-arm64.zip"
  name "QuotaBar"
  desc "Menu bar monitor for Claude, Codex and Gemini quotas"
  homepage "https://github.com/JaroMarko/QuotaBar"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "QuotaBar.app"
end
