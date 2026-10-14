# QuotaBar: zdroje kvót (overené 2026-10-14)

## Súčasná implementácia

Codex: lokálny `codex app-server --stdio`, handshake initialize/initialized, potom account/read s refreshToken:false a account/rateLimits/read. Číta JSON percentá, dĺžku okna a reset; negeneruje modelové odpovede. Zdroj: [OpenAI App Server](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

Claude: GET https://api.anthropic.com/api/oauth/usage s existujúcim Claude Code OAuth tokenom z lokálneho credential súboru alebo Keychain. QuotaBar token nezapisuje ani neobnovuje. Číta utilization a reset dátumy; negeneruje modelové odpovede. Verejný kontrakt tohto konkrétneho endpointu ani povolená polling frekvencia sa v prehľadaných oficiálnych docs nenašli. Nie je to ekvivalent Console Admin/Usage API.

[Claude Code authentication](https://code.claude.com/docs/en/authentication) dokumentuje prihlasovanie. [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) obmedzuje third-party využitie subscription OAuth a sprostredkovanie credentialov; preto súčasný priamy provider neoznačujeme za verejne podporovanú integráciu. Samotná429 nepreukazuje vymáhanie týchto pravidiel.

## Zdokumentovaná alternatíva pre Claude — návrh, ešte neimplementovaný

[Status line rate limit usage](https://code.claude.com/docs/en/statusline#rate-limit-usage) odovzdáva `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` a `resets_at`. Dáta pre Pro/Max sú dostupné až po prvej API odpovedi a okná môžu chýbať. Návrh: lokálny bridge z existujúcej status line uloží iba kvóty/timestamp; QuotaBar číta cache bez vlastných sieťových požiadaviek. Zachovať existujúci status line command; neukladať prompt/session/transcript údaje. Mimo aktívnej CLI relácie údaje nemusia byť čerstvé. Časté čítanie cache nie je garantovaná čerstvá serverová kvóta.

Codex docs tiež uvádzajú account/rateLimits/updated. Návrh na dlhšie otvorené spojenie treba overiť; nemožno automaticky predpokladať udalosti zo všetkých ostatných Codex relácií.

## Pauzy a vysvetlenia1.3.1

HTTP429 z Claude usage endpointu sa mapuje na dočasné obmedzenie quota checkov, nie na potvrdenie vyčerpanej subscription kvóty. QuotaBar má vlastnú600s pauzu (nie garanciu Anthropic); manuálny refresh ani reštart ju neobíde. Pauza sa ukladá lokálne. Pri chybe je ? hover/click vysvetlenie a čas ďalšieho pokusu. [Anthropic API rate limits](https://platform.claude.com/docs/en/api/rate-limits) dokumentujú429 a Retry-After pre verejné API; tieto Messages API limity nemožno preniesť na nedokumentovaný OAuth usage endpoint.
