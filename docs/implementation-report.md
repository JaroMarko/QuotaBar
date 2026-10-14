# QuotaBar 1.1.0 — výsledok implementácie

Dátum: 2026-10-14. Projekt: `/Users/jaroslavmarko/Developer/03 hobby/QuotaBar`. Remote: `git@github.com:JaroMarko/QuotaBar.git`. Commity sú lokálne; push nebol zadaný.

## Hotové kroky

1. Existujúci projekt uložený do východiskového commitu, vytvorený plán, poznámky a kritériá overenia.
2. Poskytovatelia: obmedzené subprocess timeouty, priebežné čítanie stdout/stderr bez pipe deadlocku, inicializácia Codex RPC, validácia čísel, diagnostika siete/prihlásenia/expirácie/permissions a čas posledného merania.
3. Menu bar: iba dve grafické ikony s nezávislým prstencom spotreby. Prerušovaný prstenec označuje neaktuálne či neznáme dáta. Presné percentá, okná, zdroje a reset sú po kliknutí.
4. Natívny AppKit NSStatusItem nahradil SwiftUI MenuBarExtra, ktorý pri testovaní uviazol v image-update startup slučke. SwiftUI zostáva pre popover a nastavenia.
5. Adaptívna obnova 60–300 sekúnd, backoff po chybách do 900 sekúnd, 600-sekundový cooldown pri rate limite. Pridané sieťové a sleep/wake callbacks. Manuálny refresh neobchádza rate-limit cooldown.
6. Notifikácie: trvalá evidencia účtu/okna/resetného cyklu potláča opakované prekročenia. Reset vyžaduje nové meranie, posun resetného času a pokles využitia.
7. Lokálna história: najviac 30 dní a 10 000 záznamov v `~/Library/Application Support/QuotaBar/history.json`. Atómový zápis, private directory/file permissions, žiadne prompty ani obsah konverzácií. Vymazanie histórie má v menu potvrdenie.
8. Graf aktuálneho resetného okna, vodiaca čiara rovnomerného využívania a konzervatívna predikcia. Odhad potrebuje aspoň 3 čerstvé monotónne vzorky z rovnakého účtu/okna/resetu počas aspoň 10 minút. Staré alebo rozporné údaje odhad potlačia.
9. Prehľad kapacity jednotlivých poskytovateľov; bez automatického prepínania účtov alebo agentov.
10. Build/verify/package skripty, lokálne nainštalovaný QuotaBar 1.1.0 a `.pkg` inštalátor. Staršia QuotaBar verzia je odložená vo workspace `work/QuotaBar-before-improvements.app`.

## Čo bolo overené

- Release build pre Apple Silicon a lokálny ad-hoc codesign prešli.
- 47 regresných kontrol prešlo bez zlyhania.
- Integračná skúška celého UsageStore prešla: zachovanie stale merania, backoff, manuálna obnova, 429 cooldown a uloženie/vymazanie histórie. Fixture testy používajú oddelené dočasné preferences a súbory.
- Živé meranie cez oba provider testy prešlo. Skutočný app startup automaticky načítal Claude 2 okná a Codex 1 okno, bez erroru a bez stale flagu; históriu uložil.
- Ikony boli vykreslené z toho istého AppKit rendereru a vizuálne skontrolované.
- Inštalátor bol rozbalený, jeho app podpis overený a binárny SHA-256 zhodný s buildom. Nainštalovaná app podpis tiež prešla.
- Finálna nainštalovaná aplikácia beží. Jednorazový procesný snapshot ukázal 0,0 % CPU a približne 65 MiB RSS; nie je to dlhodobý benchmark ani porovnanie s konkurenciou.
- Shell syntax a git diff --check prešli. Projekt je commitnutý po samostatných krokoch.

## Obmedzenia a ďalšie overenie

- Na Macu nebol nájdený platný Developer ID certifikát. Balík nie je verejne notarizovaný; automatické vzdialené aktualizácie neboli pridané. Lokálne aktualizácie sú cez build/inštalátor.
- GUI nástroj nevie vybrať appku bez okna a Finder screenshot bol prázdny. Interaktívne otvorenie popoveru, nastavení a vizuálnu kontrolu grafov treba ešte manuálne potvrdiť. Statický renderer ikon a automatický štart aplikácie sú overené.
- Skutočné uspatie/prebudenie Macu, dlhší offline režim a doručenie systémových notifikácií neboli vyvolané, aby sa neprerušila Jarova práca. Callbacky sú implementované; modelové failure/recovery scenáre prešli.
- Claude endpoint neposkytuje potvrdenú identitu účtu. História preto používa nepriehľadný fingerprint aktuálnej session, nie uložený token. Rotácia tokenu začne novú vetvu histórie.
- Unknown nepriehľadné API polia sa nepovažujú za limit bez známeho kontraktu; rozšírené five-hour/seven-day modelové rodiny sú podporované.
- Pri balení sa objavujú platformové metadata write warnings. Overenie podpisu stagingu, rozbaleného payloadu a jeho obsahu prešlo; tieto warnings nie sú vydávané za úspešnú notarizáciu.
- Starý root-owned `/Applications/PlanMeter.app` môže naďalej zostať z pôvodnej inštalácie; jeho odstránenie vyžaduje admin oprávnenie.

## Commity implementácie

- `a818a2e` — východiskový QuotaBar projekt
- `55c3cf1` — plán a pracovné poznámky
- `966a0b9` — spúšťanie a provider probes
- `ac174d5` — grafické ikony
- `762d442` — adaptívna obnova a notifikácie
- `c1ad172` — história a tempo
- `f1661c8` — native status item, integračné overenie a balenie
- Finálny report je v nadväzujúcom dokumentačnom commite.

## Reprodukcia

`./scripts/verify.sh --live` spustí build, regresné a integračné kontroly, diff check aj reálne provider probes. `./scripts/package_pkg.sh` vytvorí balík v projektovom `dist/`. Netreba zadávať nové API keys ani prepisovať provider auth súbory.

Referenčná dokumentácia Codex RPC: https://learn.chatgpt.com/docs/app-server
