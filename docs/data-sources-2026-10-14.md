# QuotaBar: zdroje kvót (overené2026-10-14)

## Aktuálna implementácia1.5.0

Claude: lokálny mod číta oficiálne `$.session.usage()` a zapisuje iba `rateLimits` (kind,percentUsed,resetsAt) a capturedAt. QuotaBar číta súbor každých20s; lokálny zdroj nečíta OAuth;pri nedostupných/starších údajoch má autorizovaný experimentálny OAuth fallback. Hook `session.measure` reaguje po turne a pri zmene planusage; `/quotabar-sync` je lokálny command bez LLM. Desktop embeddedCode2.1.295 aj CLI2.1.299 overené; obe plugin validation/test prešli. Chat/Cowork-only nie sú zdrojom. Cloud/SSH mod beží na vzdialenom stroji,kde miestny /Applications/QuotaBar.app nie je prítomný. Meranie po10min bez update je označené ako last-known;Claude ring zostáva do svojho známeho resetu. Resetané okno alebo staré okno bez resettime sa skryje,nie0%. Account identity API neposkytuje,preto Claudeautoalerts/forecast withheld; prvý údaj pri migrácii nevytvorí falošný reset.

Primárne docs: [Mods overview](https://code.claude.com/docs/en/plugins/mods/overview), [session.usage a session.measure](https://code.claude.com/docs/en/plugins/mods/reference), [Create/validate a mod](https://code.claude.com/docs/en/plugins/mods/create).

Codex ostáva lokálny app-server s account/read refreshToken:false a account/rateLimits/read,adaptive refresh60–300s a chybovépauzy. [OpenAI App Server](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

## Historické preverenie pred1.4.0

### Pôvodná implementácia

Codex: lokálny `codex app-server --stdio`, handshake initialize/initialized, potom account/read s refreshToken:false a account/rateLimits/read. Číta JSON percentá, dĺžku okna a reset; negeneruje modelové odpovede. Zdroj: [OpenAI App Server](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

Claude: GET https://api.anthropic.com/api/oauth/usage s existujúcim Claude Code OAuth tokenom z lokálneho credential súboru alebo Keychain. QuotaBar token nezapisuje ani neobnovuje. Číta utilization a reset dátumy; negeneruje modelové odpovede. Verejný kontrakt tohto konkrétneho endpointu ani povolená polling frekvencia sa v prehľadaných oficiálnych docs nenašli. Nie je to ekvivalent Console Admin/Usage API.

[Claude Code authentication](https://code.claude.com/docs/en/authentication) dokumentuje prihlasovanie. [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) obmedzuje third-party využitie subscription OAuth a sprostredkovanie credentialov; preto súčasný priamy provider neoznačujeme za verejne podporovanú integráciu. Samotná429 nepreukazuje vymáhanie týchto pravidiel.

## Zdokumentovaná alternatíva pre Claude — návrh, ešte neimplementovaný

[Status line rate limit usage](https://code.claude.com/docs/en/statusline#rate-limit-usage) odovzdáva `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` a `resets_at`. Dáta pre Pro/Max sú dostupné až po prvej API odpovedi a okná môžu chýbať. Návrh: lokálny bridge z existujúcej status line uloží iba kvóty/timestamp; QuotaBar číta cache bez vlastných sieťových požiadaviek. Zachovať existujúci status line command; neukladať prompt/session/transcript údaje. Mimo aktívnej CLI relácie údaje nemusia byť čerstvé. Časté čítanie cache nie je garantovaná čerstvá serverová kvóta.

Codex docs tiež uvádzajú account/rateLimits/updated. Návrh na dlhšie otvorené spojenie treba overiť; nemožno automaticky predpokladať udalosti zo všetkých ostatných Codex relácií.

## Pauzy a vysvetlenia1.3.1

HTTP429 z Claude usage endpointu sa mapuje na dočasné obmedzenie quota checkov, nie na potvrdenie vyčerpanej subscription kvóty. QuotaBar má vlastnú600s pauzu (nie garanciu Anthropic); manuálny refresh ani reštart ju neobíde. Pauza sa ukladá lokálne. Pri chybe je ? hover/click vysvetlenie a čas ďalšieho pokusu. [Anthropic API rate limits](https://platform.claude.com/docs/en/api/rate-limits) dokumentujú429 a Retry-After pre verejné API; tieto Messages API limity nemožno preniesť na nedokumentovaný OAuth usage endpoint.

## OAuth fallback1.5.0 — výslovne schválený Jarom
GET https://api.anthropic.com/api/oauth/usage s existujúcim ClaudeCodeOAuth tokenom iba v pamäti. Odpoveď poskytuje `five_hour.utilization`, `seven_day.utilization`, prípadne modelové okná a `resets_at`. Percentá sú serverové,nie odvodené z lokálnych tokenlogs/správ;remaining je100 mínusused. Interný váhový výpočet Anthropic tento nedokumentovaný endpoint nevysvetľuje. QuotaBar neprihlasuje,neobnovuje ani neukladá credential.
Freshlocal<=300s má prednosť;APIrequestminimumspacing300s,cachedAPI<=600s.429backoff900/1800/3600s a väčšíRetry-After(deadlinepersist). Lokálny read20s stálefungujepriAPIpause;fallbackerrorneprepíševalidlastknownako0%. Statusnotice vpopup/Details/tooltip. Ak obe okná chýbajú/resetli,APIpause sa ukáže ako unavailable. OAuthfingerprintnieverifiedaccountidentity,Claudeautoalerts/forecastsnaďalejwithheld.
Toto je experimentálne opätovné zapojenie pôvodného nedokumentovaného endpointu na výslovný pokyn používateľa; nie garantovane podporovaná verejná integrácia. PredHomebrew/publicrelease prehodnotiť súlad s [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).
