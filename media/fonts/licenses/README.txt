Every font in this folder comes from an open font project or is shared with its author's
permission. This table names the font each file holds and the license it is under.
Some file names are the ones EllesmereUI has always used, so saved settings keep working;
the font inside such a file is named here and in the file's own name table.

File                      Font inside                                     License file
------------------------  ----------------------------------------------  -------------------------------------
Arial Bold.TTF            Arimo Bold                                      Arimo-OFL.txt
Arial Narrow.ttf          Liberation Sans Narrow                          LiberationSansNarrow-LICENSE.txt
Avant Garde Naowh.ttf     TeX Gyre Adventor + Didact Gothic Cyrillic      AdventorMix-OFL-and-GUST.txt
Barlow Condensed.ttf      Barlow Condensed Medium                         BarlowCondensed-OFL.txt
Changa.ttf                Changa                                          Changa-OFL.txt
Cinzel Decorative.ttf     Cinzel Decorative                               CinzelDecorative-OFL.txt
Exo.otf                   Exo Medium                                      Exo-OFL.txt
Expressway.TTF            Roboto ExtraBold, semi-condensed width          Roboto-OFL.txt
Expressway Bold.ttf       Roboto Black, semi-condensed width              Roboto-OFL.txt
Expressway CAPS.ttf       Roboto ExtraBold, semi-condensed width          Roboto-OFL.txt
FiraSans Bold.ttf         Fira Sans Bold                                  FiraSans-OFL.txt
FiraSans Light.ttf        Fira Sans Regular                               FiraSans-OFL.txt
FiraSans Medium.ttf       Fira Sans Medium                                FiraSans-OFL.txt
Future X Black.otf        Gantari Black                                   Gantari-OFL.txt
Gotham Narrow.otf         TikTok Sans SemiBold, semi-condensed width      TikTokSans-OFL.txt
Gotham Narrow Ultra.otf   Blinker ExtraBold                               Blinker-OFL.txt
Homespun.ttf              Homespun TT BRK                                 Homespun-PERMISSION.txt
HWT Artz.ttf              Anek Latin ExtraBold, condensed width           AnekLatin-OFL.txt
KMT Kimberley.otf         Tektur ExtraBold, semi-condensed width          Tektur-OFL.txt
KMT Ninja Naruto.ttf      Sedgwick Ave Display                            SedgwickAveDisplay-OFL.txt
Poppins.ttf               Poppins Regular                                 Poppins-OFL.txt
Russo One.ttf             Russo One                                       RussoOne-OFL.txt
Ubuntu.ttf                Ubuntu Regular                                  Ubuntu-UFL.txt

Changes made to the fonts
-------------------------
Unchanged copies: Arial Narrow.ttf, Barlow Condensed.ttf, Changa.ttf, Cinzel
Decorative.ttf, Exo.otf, the three FiraSans files, Homespun.ttf, Poppins.ttf, Russo One.ttf
and Ubuntu.ttf. The source of Liberation Sans Narrow is at
https://github.com/liberationfonts/liberation-sans-narrow

Every other file is a modified version of the font named above, marked "EUI" in its own
name table. The changes are:
  - the em size, so capitals draw as tall as they did in the font the file held before
    (not in Arial Bold.TTF, which keeps its size)
  - the line metrics (ascender, descender, line gap), so text sits on the same baseline
    (not in Arial Bold.TTF)
  - Expressway.TTF, Expressway Bold.ttf, Gotham Narrow.otf, Gotham Narrow Ultra.otf,
    Future X Black.otf, KMT Kimberley.otf and Arial Bold.TTF: a 'kern' table that holds
    the font's own pair kerning, copied from its GPOS table, because the game reads
    kerning from the 'kern' table only
  - the room around punctuation marks, digits and the space: one that had more than 15
    percent more or less room than in the font the file held before sits between that
    font's side bearings (not in Avant Garde Naowh.ttf)
  - Expressway CAPS.ttf, HWT Artz.ttf and KMT Ninja Naruto.ttf: Latin lowercase letters
    draw the capital letters
  - Avant Garde Naowh.ttf: the digits and the marks . , : ; - are taken from TeX Gyre
    Adventor Bold, and the Cyrillic letters from Didact Gothic, at the capital height
    of the font they join (TeX Gyre Adventor has no Cyrillic letters)
No outline was redrawn.

Where the fonts come from
-------------------------
Anek Latin             https://github.com/EkType/Anek
Arimo                  https://github.com/googlefonts/arimo
Barlow                 https://github.com/jpt/barlow
Blinker                https://github.com/supertype-de/Blinker
Changa                 https://github.com/googlefonts/changa-vf
Cinzel Decorative      https://github.com/NDISCOVER/Cinzel
Didact Gothic          https://github.com/google/fonts/tree/main/ofl/didactgothic
Exo                    https://github.com/NDISCOVER/Exo-1.0
Fira Sans              https://github.com/mozilla/Fira
Gantari                https://github.com/Lafontype/Gantari
Homespun               AEnigma Fonts (Brian Kent)
Poppins                https://github.com/itfoundry/Poppins
Roboto                 https://github.com/googlefonts/roboto-classic
Russo One              https://github.com/google/fonts/tree/main/ofl/russoone
Sedgwick Ave Display   https://github.com/googlefonts/sedgwickave
Tektur                 https://github.com/hyvyys/Tektur
TeX Gyre Adventor      https://www.gust.org.pl/projects/e-foundry/tex-gyre/adventor
TikTok Sans            https://github.com/tiktok/TikTokSans
Ubuntu                 https://design.ubuntu.com/font
