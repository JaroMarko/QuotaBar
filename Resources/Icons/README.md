# Provider artwork

`openai-blossom.svg` is the unmodified black Blossom from OpenAI's official logo archive: https://cdn.openai.com/brand/OpenAI-Logos-2025.zip . Artwork belongs to OpenAI; it identifies the OpenAI/Codex provider, not QuotaBar's own branding. Guidelines: https://openai.com/brand/ .

`claude-spark.svg` preserves the 24pt Claude spark path from the installed official Claude desktop application's ClaudeLogo component (shared-1-7J3IM-U8.js, jp path). It is rendered in monochrome as a provider identifier. Artwork belongs to Anthropic. The custom pixel mascot was removed after feedback that it was too dominant and insufficiently recognisable.

`quotabar.svg` is QuotaBar's own Q-shaped quota ring: ivory circle with a cyan consumed segment on a navy rounded square. `QuotaBar.icns` contains all macOS standard1x/2x sizes from16px through1024px. Rebuild with `swift scripts/generate_app_icon.swift Resources/Icons/quotabar.svg /tmp/QuotaBar.iconset` and `iconutil -c icns /tmp/QuotaBar.iconset -o Resources/Icons/QuotaBar.icns`.
