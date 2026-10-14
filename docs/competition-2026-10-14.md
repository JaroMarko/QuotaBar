# QuotaBar: konkurencia a návrh priorít

Overené 14. októbra 2026. Ide o porovnanie primárnej dokumentácie a produktových stránok; aplikácie neboli nainštalované ani otestované na rovnakých účtoch. Funkcie a ceny sú deklarované výrobcami. Praktickú spoľahlivosť, spotrebu RAM/CPU a kvalitu predikcií zatiaľ nevieme porovnať. Hodnotenia a priority sú návrhy, nie schválené produktové rozhodnutia.

## Záver

Percentá, reset timer a upozornenia už predstavujú bežný základ. Pre QuotaBar odporúčam najprv opraviť získavanie dát a pridať zrozumiteľnú diagnostiku. Jaro následne spresnil: v lište žiadny text ani číselné percentá; ideálne ikony s integrovanou grafickou indikáciou už spotrebovaného percenta. Presné čísla, reset a čerstvosť údajov patria do rozbaleného menu. Veľa konkurenčných funkcií už existuje; jednoduchšie ovládanie a spoľahlivosť sú hypotéza odlíšenia, ktorú treba overiť praktickým testom.

## Porovnanie

| Aplikácia | Overené silné stránky | Obmedzenia a naše hodnotenie | Inšpirácia pre QuotaBar |
|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar) | MIT, macOS 14+, veľa poskytovateľov, widgety, lokálna história a náklady, adaptívny refresh, stav služieb. | Široký rozsah a viac autentifikačných ciest zvyšujú zložitosť údržby. Niektoré zdroje potrebujú cookies alebo Keychain; prístup k Safari môže potrebovať Full Disk Access. Nie je to povinné pre všetky konfigurácie. | Stav zdroja, fallback, označenie starých údajov, adaptívna obnova. |
| [ClaudeBar](https://github.com/tddworks/ClaudeBar) | Apache-2.0, viac poskytovateľov, spoločný prehľad, viac Codex účtov, farby podľa tempa, notifikácie, podpísaný a notarizovaný DMG. | Vyžaduje macOS 15+. Notch, témy, Touch Bar, mobilné funkcie a leaderboard rozširujú produkt výrazne nad náš dnešný cieľ; hodnotíme ich ako nižšiu prioritu pre nás. | Prehľad najtesnejších limitov, dostupnosť a jednoduchá inštalácia. |
| [Coco Usage Bar](https://adrientaravant.github.io/coco-usage-bar/) | MIT, native Swift, macOS 14+, Claude a Codex, čas resetu, tempo využívania, 30-dňové tokenové detaily, Sparkle aktualizácie. | Číta existujúce credentials na limity. Odhad nákladov z tokenových logov nie je faktúra. Stránka pri prvom spustení uvádza ručné Right-click Open. | Upozornenia podľa tempa, kompaktné zobrazenie oboch služieb, jasný pôvod nákladov. |
| [Tokease](https://tpatrouillat.github.io/tokease/) | Zadarmo, MIT, Claude 5h/týždeň; podľa autora bez čítania OAuth tokenov, Keychain a vlastných API volaní. Číta lokálne údaje oficiálnych Claude appiek. | Iba Claude. Desktop zdroj sa obnovuje počas behu Claude Desktop; statusline integrácia dodáva reset údaje. Čerstvosť závisí od oficiálnych aplikácií, pasívny režim nedokáže sám vynútiť novú informáciu. | Voliteľný pasívny zdroj s viditeľným časom merania a stavom dostupnosti. |
| [SessionWatcher](https://sessionwatcher.com/) | História, graf tempa, notifikácie, viac účtov a widgety vo vyššej edícii; podpísaná/notarizovaná Mac appka. | Funkcie sú rozdelené do platených edícií. K dátumu kontroly Bundle Claude/Codex/Cursor $14.99 jednorazovo; Pro $59 jednorazovo alebo $24/rok. Výrobca uvádza zvýšenie jednorazových cien od 1. novembra. | História a orientácia pri prepnutí poskytovateľa; viac účtov až pri potrebe. |
| [AIUsageBar](https://www.aiusagebar.com/) | Native Swift, viac poskytovateľov, onboarding, reset timer a upozornenia. Free pre Claude; Pro $9.99 jednorazovo pre dva Macy. | Codex a ďalšie služby sú v platenej edícii. Marketingové tvrdenia o živých dátach a nákladoch nepreukazujú presnosť; porovnateľný praktický test chýba. | Krátky setup, zostávajúce percentá a upozornenie pred vyčerpaním. |

Cena nie je rozhodujúci dôvod robiť vlastnú aplikáciu: existujú rozsiahle open-source alternatívy. Najbližší produktový vzor nášmu rozsahu je Coco, technický referenčný bod je CodexBar, pasívny prístup predstavuje Tokease.

## Čo rozhoduje o správnosti čísel

Claude chat, Desktop a Claude Code čerpajú zo spoločného account limitu. Nemajú sa sčítať ako tri nezávislé zásoby. Lokálne tokenové logy jedného CLI nepokrývajú celú aktivitu účtu. [Oficiálne vysvetlenie Claude limitov](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)

Oficiálna Claude Code statusline obsahuje `rate_limits.five_hour` a `rate_limits.seven_day`, percentá a reset timestampy. Polia sa nemusia objaviť pred prvou odpoveďou ani pri každom spôsobe prihlásenia. To umožňuje pasívny zdroj, nie zaručené nepretržité meranie. [Oficiálna statusline dokumentácia](https://code.claude.com/docs/en/statusline)

CodexBar dokumentuje viac ciest pre Claude vrátane OAuth, CLI a webu, aj prípady, keď fungujúce prihlásenie neznamená fungujúci refresh trackera. Starý úspešný snapshot musí ponechať pôvodný timestamp. [Claude dátové zdroje a diagnostika](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)

Pre každý QuotaBar údaj odporúčam ukladať poskytovateľa, účet, typ limitu, zdroj, čas merania a stav dostupnosti. Neznáma hodnota musí zostať neznáma; nikdy sa nesmie zmeniť na 0 % využitia či 100 % voľnej kapacity. Odhad tempa a prípadné API-ekvivalentné náklady musia byť vizuálne oddelené od poskytovateľom reportovanej kvóty.

## Navrhované poradie implementácie

### P0 — obnoviť dôveryhodné dáta

- Skutočne overiť refresh Claude a Codex na Jarových účtoch; samotných 18 decoder/notifikačných kontrol to nedokazuje.
- Diagnostika CLI, prihlásenia, zvoleného zdroja a posledného úspechu. Rozlíšiť chýbajúce CLI, odhlásenie, expirované credentials, timeout, sieť, odmietnutý prístup a zmenený formát odpovede.
- Označiť cached/stale údaje a neúspešný refresh. Chýbajúce okno nesmie znamenať vyčerpanie ani reset.
- Skúška obnovy po sleep/wake a sieťovom výpadku; refresh nesmie blokovať UI.
- Použiť podporované a overené cesty, rešpektovať aktuálne pravidlá poskytovateľa; neupravovať cudzie auth súbory pri monitorovaní.

### P1 — čitateľné každodenné používanie

- **Potvrdená požiadavka Jara (2026-10-14):** v lište bez textu a číselných percent, iba grafické ikony; preferované je integrované vizuálne zobrazenie už spotrebovaného podielu. Konkrétny tvar ikon, výplne a spôsob zobrazenia 5h/týždenného okna ešte nebol zvolený. Presné údaje budú po kliknutí.
- V menu obe okná 5h/týždeň a prípadné ďalšie reportované limity, presný reset aj odpočet, čas merania, účet a zdroj.
- Jasne označiť najobmedzujúcejšie relevantné okno každého poskytovateľa. Nespriemerovať nesúvisiace limity a nezakryť jedného poskytovateľa spoločným percentom.
- Manuálny refresh a adaptívna obnova s backoffom; nevykonávať agresívny polling. Žiadne opakované hlásenia rovnakého prahu.
- Upozornenia nastaviť používateľsky; reset potvrdiť novým meraním.
- Pred distribúciou stabilný build, podpis, notarizácia a jednoduché aktualizácie.

### P2 — história a pomoc s tempom

- Lokálna história percent a resetov s limitom uchovávania; bez promptov a obsahu konverzácií.
- Graf spotreby oproti uplynutému času okna. Modelový príklad: 80 % využitých tesne pred resetom má iný význam než 80 % na začiatku okna.
- Predikcia vyčerpania len pri dostatku čerstvých meraní, jasne označená ako odhad. Zmeny modelu, práce a limitov ju môžu znehodnotiť.
- Prehľad alternatívnej kapacity bez automatického prepínania účtov či agentov.

### Neskôr podľa potreby

Viac účtov, ďalší poskytovatelia a desktop widget. Zatiaľ by som odložil mobilný sync, leaderboard, veľký analytický dashboard a automatické ovládanie agentov. Sú to návrhy rozsahu, nie už prijaté rozhodnutia.

## Praktické porovnanie pred ďalším rozšírením

Po oprave skúsiť QuotaBar, CodexBar a Coco na rovnakých účtoch. Porovnať s oficiálnou Usage obrazovkou: správnosť okien, reset timestampov, latenciu, chyby pri výpadku siete a obnovu po prebudení. Zmerať CPU/RAM a počet refreshov rovnakou metódou. Až tento test dovolí tvrdiť, že naše riešenie je spoľahlivejšie alebo ľahšie.
