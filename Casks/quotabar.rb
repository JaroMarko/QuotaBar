cask "quotabar" do
  version "1.7.2"
  sha256 "6ccbac630fd2a2cef06df565ec967997c5616d1cd040e501dcb225e9fc04f5de"

  url "https://github.com/JaroMarko/QuotaBar/releases/download/v#{version}/QuotaBar-#{version}-arm64.zip"
  name "QuotaBar"
  desc "Menu bar monitor for Claude, Codex and Gemini quotas"
  homepage "https://github.com/JaroMarko/QuotaBar"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "QuotaBar.app"
end
