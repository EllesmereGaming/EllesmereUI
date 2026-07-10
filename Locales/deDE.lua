-- German (Germany) localization for EllesmereUI. Community-maintained.
-- Encoding: UTF-8 without BOM (see .gitattributes). ASCII-only does NOT apply
-- to locale files -- use proper accented characters here.
--
-- HOW TO TRANSLATE:
--   * Translate the RIGHT side of each line only. Keep the English key verbatim.
--   * Keep %1$s / %2$d placeholders; you may reorder them for grammar.
--   * Delete or omit any line to fall back to English silently.
--   * Use  L["Some Term"] = true  to deliberately keep the English text.
--
-- This is a seed/reference locale (the most common, highest-frequency strings).
-- Run /euiloc dump deDE in-game to generate the full remaining key list.

local L = EllesmereUI.RegisterLocale("deDE")
if not L then return end

-- == Common vocabulary (highest frequency) =================================
L["Enable"]            = "Aktivieren"
L["Disable"]           = "Deaktivieren"
L["Enabled"]           = "Aktiviert"
L["Disabled"]          = "Deaktiviert"
L["enabled"]           = "aktiviert"
L["disabled"]          = "deaktiviert"
L["Size"]              = "Größe"
L["Width"]             = "Breite"
L["Height"]            = "Höhe"
L["Scale"]             = "Skalierung"
L["Color"]             = "Farbe"
L["Opacity"]           = "Deckkraft"
L["Position"]          = "Position"
L["Offset"]            = "Versatz"
L["X Offset"]          = "X-Versatz"
L["Y Offset"]          = "Y-Versatz"
L["Spacing"]           = "Abstand"
L["Border"]            = "Rahmen"
L["Border Size"]       = "Rahmengröße"
L["Border Color"]      = "Rahmenfarbe"
L["Background"]        = "Hintergrund"
L["Font"]              = "Schriftart"
L["Font Size"]         = "Schriftgröße"
L["Anchor"]            = "Anker"
L["Anchor Point"]      = "Ankerpunkt"
L["Orientation"]       = "Ausrichtung"
L["Left"]              = "Links"
L["Right"]             = "Rechts"
L["Top"]               = "Oben"
L["Bottom"]            = "Unten"
L["Center"]            = "Mitte"
L["Horizontal"]        = "Horizontal"
L["Vertical"]          = "Vertikal"
L["None"]              = "Keine"
L["All"]               = "Alle"
L["Multiple"]          = "Mehrere"
L["Default"]           = "Standard"
L["Custom"]            = "Benutzerdefiniert"
L["Show"]              = "Anzeigen"
L["Hide"]              = "Verbergen"
L["Always"]            = "Immer"
L["Never"]             = "Nie"
L["Text Size"]         = "Textgröße"
L["Text Color"]        = "Textfarbe"
L["Border Style"]      = "Rahmenstil"
L["Fill Color"]        = "Füllfarbe"
L["Bar Color"]         = "Balkenfarbe"
L["Bar Texture"]       = "Balkentextur"
L["Icon Size"]         = "Symbolgröße"
L["Icon Spacing"]      = "Symbolabstand"
L["Class Color"]       = "Klassenfarbe"
L["Frame Strata"]      = "Fensterebene"
L["Growth Direction"]  = "Wachstumsrichtung"
L["Visibility"]        = "Sichtbarkeit"
L["Visibility Options"] = "Sichtbarkeitsoptionen"
L["Window Scale"]      = "Fensterskalierung"
L["Offset X"]          = "X-Versatz"
L["Offset Y"]          = "Y-Versatz"
L["Shift X"]           = "X-Versatz"
L["Shift Y"]           = "Y-Versatz"
L["Up"]                = "Hoch"
L["Down"]              = "Runter"
L["%1$s Settings"]     = "%1$s Einstellungen"
L["%1$s Options"]      = "%1$s Optionen"

-- == Buttons / popups / framework ==========================================
L["Color Picker"]      = "Farbwähler"
L["New"]               = "Neu"
L["Prev"]              = "Vorher"
L["cancel"]            = "abbrechen"
L["Cancel"]            = "Abbrechen"
L["Confirm"]           = "Bestätigen"
L["Save"]              = "Speichern"
L["Saved"]             = "Gespeichert"
L["Apply"]             = "Anwenden"
L["Apply to:"]         = "Anwenden auf:"
L["Okay"]              = "Okay"
L["Later"]             = "Später"
L["Reset"]            = "Zurücksetzen"
L["Reset & Reload"]    = "Zurücksetzen & Neu laden"
L["Reload Required"]   = "Neuladen erforderlich"
L["Reload Now"]        = "Jetzt neu laden"
L["Are you sure?"]     = "Bist du sicher?"
L["Information"]       = "Information"
L["Enter Name"]        = "Name eingeben"
L["Search..."]         = "Suchen..."
L["Search Module Settings..."] = "Moduleinstellungen durchsuchen..."

-- == Unlock mode ===========================================================
L["Unlock Mode"]                 = "Entsperrmodus"
L["Reposition freely with"]      = "Frei verschieben mit"
L["Move in Unlock Mode"]         = "Im Entsperrmodus verschieben"
L["(Applies on Window Close)"]   = "(Wird beim Schließen angewendet)"

-- == Format templates (keep %1$s / %2$s; reorder freely) ===================
L["This option requires %1$s to be %2$s"] = "Diese Option erfordert, dass %1$s %2$s ist"
L["Reset %1$s"]        = "%1$s zurücksetzen"
L["%1$s Sync"]         = "%1$s synchronisieren"
L["Changing the language requires a UI reload."] = "Das Ändern der Sprache erfordert ein Neuladen der Oberfläche."

-- == Language section (this is the visible "Language" row label) ===========
L["Language"]          = "Sprache"

-- == Font section ==========================================================
L["GLOBAL FONT"]       = "GLOBALE SCHRIFTART"
L["LANGUAGE"]          = "SPRACHE"
L["PER ADDON FONTS"]   = "SCHRIFTARTEN PRO ADDON"
L["Global Font"]       = "Globale Schriftart"
L["Outline Mode"]      = "Umriss-Modus"
L["Drop Shadow"]       = "Schlagschatten"
L["Outline"]           = "Umriss"
L["Thick Outline"]     = "Dicker Umriss"
L["Blizzard Default"]  = "Blizzard-Standard"

-- == Section headers (rendered upper-case as written; EnKey reverse-maps
--    these back to English for the inline cog/swatch detection) ============
L["HEALTH BAR"]        = "LEBENSBALKEN"
L["POWER BAR"]         = "RESSOURCENBALKEN"
L["INDICATORS"]        = "INDIKATOREN"
L["DISPELS"]           = "REINIGUNGEN"
L["DEFENSIVES & EXTERNALS"] = "DEFENSIVE & EXTERNE"
L["PRIVATE AURAS"]     = "PRIVATE AUREN"
L["DEBUFF DISPLAY"]    = "DEBUFF-ANZEIGE"
L["CORE POSITIONS"]    = "KERNPOSITIONEN"
L["CORE TEXT POSITIONS"] = "KERN-TEXTPOSITIONEN"
L["DISPLAY"]           = "ANZEIGE"

-- == Module names (left sidebar) ===========================================
L["Action Bars"]       = "Aktionsleisten"
L["Nameplates"]        = "Namensplaketten"
L["Unit Frames"]       = "Einheitenfenster"
L["Raid Frames"]       = "Schlachtzugsfenster"
L["Cooldown Manager"]  = "Abklingzeit-Manager"
L["Resource & Cast Bars"] = "Ressourcen- & Zauberleisten"
L["AuraBuff Reminders"] = "Aura-Erinnerungen"
L["Quality of Life"]   = "Komfortfunktionen"
L["Blizz UI Enhanced"] = "Blizz-UI verbessert"
L["Friends List"]      = "Freundesliste"
L["Mythic+ Timer"]     = "Mythisch+ Timer"
L["Quest Tracker"]     = "Questverfolgung"
L["Minimap"]           = "Minikarte"
L["Chat"]              = true
L["Damage Meters"]     = "Schadensmesser"
L["Brackets"] = "Klammern"
L["Chat Color (timestamp matches the message color)"] = "Chatfarbe (Zeitstempel in Nachrichtenfarbe)"
