# Translating EllesmereUI

EllesmereUI's options panel, unlock mode, and popups can be translated into any
of the languages World of Warcraft supports. Translations are community-driven
and live in plain Lua files inside the `EllesmereUILocales` addon (a
LoadOnDemand sibling of the main addon). Missing translations fall back to
English automatically, so a partial translation is completely fine and ships
without breaking anything.

## How it works

- English **is** the key. There are no symbolic IDs: you translate
  `L["Enable"] = "..."`, not `L["OPTIONS_ENABLE"]`.
- English clients never load the `EllesmereUILocales` addon at all. On a
  non-English client it loads at startup, and only the file whose language
  matches builds entries; every other file returns immediately.
- Any key you leave out (or any string not yet wrapped) renders in English.

## Add or improve a language

1. **Find your locale code** (what `GetLocale()` returns):
   `deDE` German, `frFR` French, `esES` Spanish (EU), `esMX` Spanish (LatAm),
   `itIT` Italian, `ptBR` Portuguese (Brazil), `ruRU` Russian, `koKR` Korean,
   `zhCN` Chinese (Simplified), `zhTW` Chinese (Traditional).

2. **Create `EllesmereUILocales/<code>.lua`** (copy `EllesmereUILocales/deDE.lua`
   as a starting point), beginning with:
   ```lua
   local L = EllesmereUI.RegisterLocale("frFR")   -- your code
   if not L then return end
   ```

3. **Add a line in `EllesmereUILocales/EllesmereUILocales.toc`** next to the
   other locales:
   ```
   frFR.lua
   ```

4. **Translate the right-hand side only.** Keep the English key exactly as it is:
   ```lua
   L["Enable"] = "Activer"
   ```

5. **Open a pull request.**

## Rules

- **Encoding: UTF-8 without a BOM.** Use real accented / CJK / Cyrillic
  characters (`Größe`, not `Groesse`). `.gitattributes` pins this; do not edit
  locale files with a tool that rewrites them as UTF-16.
- **Keep `%1$s` / `%2$d` placeholders.** You may reorder them for grammar:
  `L["Reset %1$s"] = "%1$s zurücksetzen"`. Never split a sentence into
  concatenated fragments.
- **Keep English on purpose** with the `true` sentinel when a term shouldn't
  change: `L["Mythic+"] = true`.
- **Don't translate** numbers, color codes, or proper nouns Blizzard already
  localizes (class/spec names come from the game directly).

## Generating the full key list

You don't have to find every string by hand. In-game:

```
/reload
/euiloc on            -- start recording (before opening the options)
... open every options page, cog popup, and tooltip ...
/euiloc dump frFR     -- writes a paste-ready L["..."] = "" block
/euiloc off
```

The block is saved to `EllesmereUIDB._localeDump` in
`WTF\Account\<account>\SavedVariables\EllesmereUI.lua` (after a `/reload` or
logout). Paste it into your locale file and fill in the translations.

`EllesmereUILocales/_keys.txt` is a committed, static list of the literal keys (regenerated
by `.tools/extract-locale-keys.sh`; CI keeps it current). It is a quick offline
reference, but the in-game `/euiloc` harvester above is the complete source of
truth because it also captures strings passed to `L()` as variables.
