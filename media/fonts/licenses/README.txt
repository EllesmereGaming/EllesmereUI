Every font in this folder comes from an open font project or is shared under its author's own
terms or permission. This table names the font each file holds (for a modified file, the
font it was made from) and the license it is under. A modified file is named after the name
it carries itself; see "Changes made to the fonts".

File                      Font inside                                     License file
------------------------  ----------------------------------------------  -------------------------------------
Arial Narrow.ttf          Liberation Sans Narrow                          LiberationSansNarrow-LICENSE.txt
Barlow Condensed.ttf      Barlow Condensed Medium                         BarlowCondensed-OFL.txt
Changa.ttf                Changa                                          Changa-OFL.txt
Cinzel Decorative.ttf     Cinzel Decorative                               CinzelDecorative-OFL.txt
EUI Geometric Black.ttf   Gantari Black                                   Gantari-OFL.txt
EUI Geometric.ttf         TeX Gyre Adventor + Didact Gothic Cyrillic      AdventorMix-OFL-and-GUST.txt
EUI Grotesk Bold.ttf      Arimo Bold                                      Arimo-OFL.txt
EUI Highway Black.ttf     Blue Highway Bold + Roboto Black                BlueHighwayMix-OFL-and-CC0.txt
EUI Highway Caps.ttf      Blue Highway Bold + Roboto ExtraBold            BlueHighwayMix-OFL-and-CC0.txt
EUI Highway.ttf           Blue Highway Bold + Roboto ExtraBold            BlueHighwayMix-OFL-and-CC0.txt
EUI Narrow Heavy.ttf      Blinker ExtraBold                               Blinker-OFL.txt
EUI Narrow Sans.ttf       TikTok Sans SemiBold, semi-condensed width      TikTokSans-OFL.txt
EUI Poster Caps.ttf       Anek Latin ExtraBold, condensed width           AnekLatin-OFL.txt
EUI Rounded Block.ttf     Russo One, redrawn                              RussoOne-OFL.txt
Exo.otf                   Exo Medium                                      Exo-OFL.txt
FiraSans Bold.ttf         Fira Sans Bold                                  FiraSans-OFL.txt
FiraSans Light.ttf        Fira Sans Regular                               FiraSans-OFL.txt
FiraSans Medium.ttf       Fira Sans Medium                                FiraSans-OFL.txt
Homespun.ttf              Homespun TT BRK                                 Homespun-PERMISSION.txt
KMT Ninja Naruto.ttf      Ninja Naruto (sk89q)                            NinjaNaruto-LICENSE.txt
Poppins.ttf               Poppins Regular                                 Poppins-OFL.txt
Russo One.ttf             Russo One                                       RussoOne-OFL.txt
Ubuntu.ttf                Ubuntu Regular                                  Ubuntu-UFL.txt

Changes made to the fonts
-------------------------
Unchanged copies: Arial Narrow.ttf, Barlow Condensed.ttf, Changa.ttf, Cinzel
Decorative.ttf, Exo.otf, the three FiraSans files, Homespun.ttf, KMT Ninja Naruto.ttf,
Poppins.ttf, Russo One.ttf and Ubuntu.ttf. The source of Liberation Sans Narrow is at
https://github.com/liberationfonts/liberation-sans-narrow

Every other file is a modified version of the font named above, made to match the font
EllesmereUI shipped before under the file's earlier name ("the font the file held before"
below). Each file is named after the name it carries in its own name table, so none goes by
the name of the font it was made from or of the font it matches:
  File                      Earlier file name
  EUI Geometric Black.ttf   Future X Black.otf
  EUI Geometric.ttf         Avant Garde Naowh.ttf
  EUI Grotesk Bold.ttf      Arial Bold.TTF
  EUI Highway Black.ttf     Expressway Bold.ttf
  EUI Highway Caps.ttf      Expressway CAPS.ttf
  EUI Highway.ttf           Expressway.TTF
  EUI Narrow Heavy.ttf      Gotham Narrow Ultra.otf
  EUI Narrow Sans.ttf       Gotham Narrow.otf
  EUI Poster Caps.ttf       HWT Artz.ttf
  EUI Rounded Block.ttf     KMT Kimberley.otf
The changes are:
  - the em size, so capitals draw as tall as they did in the font the file held before
    (not in EUI Grotesk Bold.ttf, which keeps its size)
  - the line metrics (ascender, descender, line gap), so text sits on the same baseline
  - EUI Highway Caps.ttf and EUI Poster Caps.ttf: Latin lowercase letters draw the capital
    letters
  - EUI Rounded Block.ttf: only the characters the font the file held before had are kept;
    A I J M P Q R Y a i j l t u w y 2 4 % & ( ) $ @, their Cyrillic twins (A, Em, Er, a, u,
    je, I, Je), the Cyrillic i, short i and be, the dotless and accented i and the Ukrainian
    i and yi are redrawn by hand to that font's shapes, on Russo One's own outline points and
    with new strokes drawn for them; the Cyrillic Ze, E reversed (capital and small) and Yu,
    round in that font, are drawn new from round strokes
  - EUI Highway.ttf, EUI Highway Black.ttf and EUI Highway Caps.ttf: Blue Highway Bold's CFF
    outlines are turned into TrueType outlines; the Cyrillic letters the font the file
    held before draws exactly as Latin ones are copies of Blue Highway's own letters (Ya
    and I as its R and N mirrored, Ze as its 3, E reversed as its C mirrored with a bar),
    and the other characters it does not have are taken from Roboto, which is changed
    the same way
  - EUI Geometric.ttf: the digits and the marks . , : ; - are taken from TeX Gyre
    Adventor Bold, and the Cyrillic letters from Didact Gothic, at the capital height
    of the font they join (TeX Gyre Adventor has no Cyrillic letters)
  - every modified file: the strokes are made thicker or thinner (the outline moved out or
    in along its edges) to the stroke widths of the font the file held before; the
    heights of the letters (baseline, x-height, capital height, ascender, descender, digit
    height) are set to that font's; and each character that font had takes its advance
    width, and is widened or narrowed sideways (letters by at most a fifth) and moved to
    the place that font gave it, a mark also to its top and bottom
  - characters redrawn by hand to the shapes of the font the file held before, on the
    open font's own outline points and with new strokes drawn for them (measured on that
    font, never traced), with their accented forms:
      EUI Highway.ttf, EUI Highway Black.ttf, EUI Highway Caps.ttf: J G 3 4 6 7 9 S a c g t
        % $ , ; and the hyphen (EUI Highway Caps.ttf also the small yi, its dots as its
        capital's)
      EUI Narrow Sans.ttf: A C G J M N P Q S c j t u y 1 3 4 5 6 9 % / ( ) . , : ; ! ?
      EUI Narrow Heavy.ttf: C J Q S Z c g j r t y 2 3 4 5 ( ) , : ; & ! @ *
      EUI Geometric Black.ttf: G J M Q a f j $ % / ( ) (its a single-story, from Gantari's d)
      EUI Poster Caps.ttf: M N 2 3 5 6 7 9 * and the A dieresis (the A's top cut upright beside its dots)
      EUI Grotesk Bold.ttf: E F J Q a t 1 % ! and the Cyrillic Ka and Zhe (capital and small)
      EUI Geometric.ttf: [ ]
  - every modified file: the outline points of each character are then moved one by one
    until the character covers the same area on screen as in the font the file held
    before (fitted to how that font draws, never to its outline data); a parenthesis or
    bracket is drawn as its partner mirrored where that matches better; and where a
    character's outlines overlap or cross themselves, they are merged into one clean
    outline (the area they fill stays the same)
  - EUI Poster Caps.ttf and EUI Rounded Block.ttf: corners are rounded as the font the file
    held before rounds them
  - EUI Highway.ttf, EUI Highway Black.ttf, EUI Narrow Sans.ttf, EUI Narrow Heavy.ttf,
    EUI Geometric Black.ttf, EUI Rounded Block.ttf and EUI Grotesk Bold.ttf: a 'kern' table
    that holds the pair kerning of the font the file held before, because the game reads kerning
    from the 'kern' table only and the characters now sit where that font placed them
Apart from the characters named above, no outline was redrawn: every outline is built on
the open font's own points, changed only as listed.

Where the fonts come from
-------------------------
Anek Latin             https://github.com/EkType/Anek
Arimo                  https://github.com/googlefonts/arimo
Barlow                 https://github.com/jpt/barlow
Blinker                https://github.com/supertype-de/Blinker
Blue Highway           https://typodermicfonts.com (Typodermic, CC0)
Changa                 https://github.com/googlefonts/changa-vf
Cinzel Decorative      https://github.com/NDISCOVER/Cinzel
Didact Gothic          https://github.com/google/fonts/tree/main/ofl/didactgothic
Exo                    https://github.com/NDISCOVER/Exo-1.0
Fira Sans              https://github.com/mozilla/Fira
Gantari                https://github.com/Lafontype/Gantari
Homespun               AEnigma Fonts (Brian Kent)
Ninja Naruto           http://www.therisenrealm.com (sk89q, 2004)
Poppins                https://github.com/itfoundry/Poppins
Roboto                 https://github.com/googlefonts/roboto-classic (inside the EUI Highway files)
Russo One              https://github.com/google/fonts/tree/main/ofl/russoone
TeX Gyre Adventor      https://www.gust.org.pl/projects/e-foundry/tex-gyre/adventor
TikTok Sans            https://github.com/tiktok/TikTokSans
Ubuntu                 https://design.ubuntu.com/font
