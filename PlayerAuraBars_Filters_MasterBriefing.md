# PlayerAuraBars — Offene Punkte

Rest der ursprünglichen Filters/Buff-Manager-Import-Briefing ist erledigt und
wurde entfernt (siehe Commit-Historie auf `feature/player-aura-bars` für
Details, u.a. `bb714423` ff.). Nur noch offene Punkte:

1. **In-Game noch nicht vollständig durchgetestet:** kompletter aktueller
   Stand (Redesign + Filters + Import + Presets-Schutz + Extra-Spells-
   Presets-Gruppe + alle Claude-Code-Session-Ergänzungen). Joel macht den
   vollständigen Durchlauf bewusst erst **gegen Ende**, nicht jetzt — bislang
   wurden nur die jeweils neu gebauten Features gezielt gegengetestet, kein
   kompletter Durchlauf.

2. **Border-Style- und Duration-Format-Lücken in `BuildStyle`**
   (`EllesmereUIUnitFrames_PlayerAuraBars.lua`): fehlen aktuell
   `borderTexture`, `borderTextureOffset(Y)`, `borderTextureShiftX/Y`,
   `borderBehind` — obwohl AKs Engine-Border-Call
   (`EllesmereUI.ApplySecretSafeBorderStyle`, verdrahtet über
   `EllesmereUI_AuraKit.lua`s `ApplyStyleToRegions`) das bereits über
   `style.border.texture/offsetX/offsetY/shiftX/shiftY` und
   `style.border.behind` unterstützt. Andere Unit-Frame-Aura-Displays
   (z.B. `EUI_UnitFrames_AuraContainers.lua`) exponieren das bereits.
   Zusätzlich PAB-weit fehlend: `durationFormat`-Kompaktvarianten
   (Doppelpunkt/Sekunden) — AK hat aktuell nur eine gemeinsame
   Duration-Formatter-Instanz, das würde eine Erweiterung von AuraKit
   selbst erfordern, nicht nur von PAB.
   Joel hat entschieden (2026-08-02), beide Lücken zurückzustellen statt die
   External-Defensives-Migration darauf zu blocken — will sie aber später
   **über alle PAB-Bars hinweg** (Default Buffs/Debuffs/External Defensives
   + jede Custom Bar) nachziehen, nicht nur für eine Bar.

3. ~~Sortierung fehlt komplett~~ — **implementiert (2026-08-03), noch nicht
   in-game gegengetestet.** Enum-Werte in-game verifiziert per `/dump`:
   `AuraContainerSortMethod = {Default=0, BigDefensive=1, UnitFrameDebuff=2,
   ImportantOnly=3, Expiration=4, ExpirationOnly=5, Name=6, NameOnly=7,
   AuraInstanceIDOnly=8}`, `AuraContainerSortDirection = {Normal=0,
   Reverse=1}`. Dropdown kuratiert auf 4 Werte: **Default, Expiration, Name,
   Important** (Anzeigelabel für `ImportantOnly`) — die übrigen 5 (BigDefensive/
   UnitFrameDebuff/ExpirationOnly/NameOnly/AuraInstanceIDOnly) bewusst
   ausgeblendet, da ihre Bedeutung nirgends dokumentiert ist und die Namen
   nach engerem, anderweitigem Blizzard-UI-Zweck klingen.
   **"Important" ist nur bei Debuff-Bars im Dropdown sichtbar** — bei Buffs
   gibt es kein Dispel-Konzept, daher ist es dort ein No-Op (verhält sich
   wie Default) und wird konsequent ausgeblendet statt als toter Eintrag
   gezeigt (`SORT_METHOD_VALUES_BUFF` vs. `_DEBUFF` in den ManagerPages,
   `BuildCoreFields` bekommt jetzt einen `isBuff`-Parameter).
   - Neue Cfg-Felder `sortMethod`/`sortDirection` (String-Keys) auf jeder
     Bar-Cfg-Tabelle (Default Buffs/Debuffs, External Defensives, jede
     Custom Buff-/Debuff-Bar) — Default `"Default"`/`"Normal"`.
   - Engine (`EllesmereUIUnitFrames_PlayerAuraBars.lua`): neue Resolver
     `ResolveSortMethod(cfg)`/`ResolveSortDirection(cfg)`. `ApplyGroupConfig`
     nimmt jetzt einen `cfg`-Parameter, setzt `sortMethod`/`sortDirection`
     beim initialen `AK.AddGroupToContainer` UND re-appliziert live per
     `container:SetAuraGroupSortMethod(key, method, direction)` (die direkte
     Setter-API braucht laut Nameplates-Modul explizit beide Werte, `nil`-
     Guard via `~= nil`, da `Default`/`Normal` = 0 sind, nicht "unset").
     Gilt für alle Chain-Gruppen (Default-Debuffs, Buffs-Catchall, Custom-
     Bar-Chains) sowie die einzeln deklarierten "spells"- (Buffs-Filter) und
     "extdef"-Gruppen — PAB nutzt nirgends `AddAuraSlot`, Sortierung ist
     also durchgängig gruppenbasiert.
   - UI (`EUI_PlayerAuraBars_ManagerPages.lua`): zwei neue Dropdowns ("Sort
     Method"/"Sort Direction") in `BuildCoreFields` — dieser Helper ist
     bereits von allen 5 Bar-Typ-Detailseiten gemeinsam genutzt, daher
     automatisch für Default+Custom+ExtDef verfügbar, keine Duplizierung
     nötig.
   - **Preview-Simulation** (`SortPreviewList` in
     `EllesmereUIUnitFrames_PlayerAuraBars.lua`): die eingebettete Options-
     Preview nutzt keine echten AuraContainer-Gruppen (nur Fake-Icons in
     einem selbstgebauten Grid), daher wurde Sortierung dort separat
     nachgebildet — **Annahme, nicht verifiziert**, da Blizzard die
     tatsächliche Sortierlogik nirgends dokumentiert:
     - `Expiration` → aufsteigend nach zugewiesener Fake-Dauer (kürzeste
       Restdauer zuerst)
     - `Name` → alphabetisch nach Spell-Name
     - `ImportantOnly` → nur bei Debuffs: entzauberbare (dispel≠nil) zuerst;
       bei Buffs No-Op (siehe oben)
     - `Reverse` dreht den Vergleich um — **auch bei `Default`**: dort gibt
       es kein definiertes Sortierkriterium, also wird die Pool-Reihenfolge
       schlicht umgedreht, damit der Direction-Toggle sichtbar bleibt (Bug
       gefixt 2026-08-03: `Default` ignorierte `Reverse` vorher komplett,
       wodurch ein reiner Direction-Wechsel ohne Method-Wechsel in der
       Preview unsichtbar blieb).
     Die Preview zeigt also plausibel, was die Option grob bewirken
     *könnte* — ob das 1:1 der echten Engine-Sortierung entspricht, ist
     ungeklärt.
   - `luac5.1 -p` sauber gegen beide Dateien. **Noch offen:** In-Game-Test,
     ob die echte Bar-Sortierung sichtbar/korrekt greift und ob sie sich
     mit der Preview-Simulation deckt (Teil von Punkt 1 oben, dem
     vollständigen Durchlauf).

4. ~~Click-Through für Buffs~~ — **verworfen, technische Limitation
   bestätigt (2026-08-03).** `SetCancelAuraButtons` (native Rechtsklick-
   Cancel-API) funktioniert nur, wenn der Button Mausklicks empfängt —
   `SetMouseClickEnabled` ist alles-oder-nichts, keine selektive
   Pro-Maustaste-Passthrough-API in diesem Repo gefunden (siehe Kommentar
   `EllesmereUI_AuraKit.lua` Z. 612–622: "Styles that wire a click action
   ... keep their clicks — those buttons overlay nothing clickable").
   Echtes Click-Through UND funktionierendes Rechtsklick-Cancel
   gleichzeitig sind mit der aktuellen Engine-Mechanik nicht kombinierbar.
   Joel: aktuelles Verhalten akzeptiert (Linksklick wird geschluckt aber
   wirkungslos, Rechtsklick cancelt weiterhin) — kein weiterer
   Handlungsbedarf.

## Weitere Ideen (Brainstorm, nicht priorisiert)

- **Glow/Flash bei bald ablaufenden oder neuen Auras** — aktuell nur
  `durationColor`, kein Puls/Glow-Threshold.
- **Desaturate-Option** — PAB nutzt aktuell nirgends `SetDesaturated` auf
  Icons, anders als manche andere Unit-Frame-Aura-Displays im Repo.
- **Unabhängige Icon-Skalierung Buffs vs. Debuffs** — aktuell treibt ein
  gemeinsamer `iconSize` direkt die Layout-Mathematik.
- **Mindest-Dauer-Schwelle** (Auren mit Restdauer < N Sekunden ausblenden) —
  nützlich gegen Raid-Buff-Rauschen.
- **Alignment/Justify bei nicht vollen Reihen** (links/zentriert/rechts
  gepackt statt Standard-Flow).
- **Eigenständiges Backdrop/Hintergrund-Styling** pro Buff-/Debuff-Bar
  (separat von den bereits oben getrackten Border-Lücken).
- Bewusst NICHT hier: Own-Only-Tracking — explizit gestrichen, siehe
  Commit-Historie, kein Re-Add geplant.
