# Overdracht — reprise_new (7 nov 2026)

Voortzetting van een Claude-sessie op de MacBook Pro. Lees dit eerst.

## Situatie
- reprise_new draait op **deze Mac mini (Media Server)**, macOS 27 "Golden Gate", donker thema, meestal bekeken via Schermdeling.
- Broncode: deze map (Swift package, `swift build -c release --build-system native`).
  Git is lokaal; remote = GitHub `reprise-labs/reprise` — **niet pushen / `scripts/publish_release.sh` draaien zonder toestemming van de gebruiker.**
- Geïnstalleerd: `/Applications/reprise_new.app` = **1.6.74**. `install.sh` bouwt, installeert, signeert en herstart de app op déze Mac.
- Data: `~/Library/Application Support/reprise_new/` (videos.json, settings.json, premieres.log).

## Gedaan in vorige sessie (commits)
- `c5d0afb` snapshot van het Codex-werk (1.6.65–1.6.72 stond niet in git).
- `0fb7065` 1.6.73: **VOD-versiebevestiging** — `DownloadedVersion` (Models.swift) wordt na de VOD-download opgeslagen
  (`MonitoredVideo.vodVersion`): kwaliteit, resolutie, codec, fps, format id, verwachte max-hoogte. Getoond in
  Recordings/Recently completed (`CompletedVideoRow`) en in de pushmelding. Oude opnames: label uit bestandsnaam.
  Ook: hoofdvenster via `NSHostingController` i.p.v. kale `NSHostingView` (StatusItemController.swift).
- `0ac76c2` 1.6.74: `scrollEdgeEffectHidden(true, for: .top)` op alle pagina's; versieregel niet meer afkappen.

## Open bug — daarom zit je hier
**Soms** verdwijnt de bovenkant van het hoofdvenster: titel "Scheduled" + knop "Add premiere" liggen onder een
wazige/donkere balk (~even hoog als de werkbalk) direct onder de werkbalk. De titel staat op de juiste plek,
er ligt alleen iets overheen. Gebruiker: het gebeurt "ineens", terwijl het venster open is.

Al geprobeerd, **hielp niet**: (1) NSHostingController, (2) scrollEdgeEffectHidden top.
Op de MacBook (macOS 27.2, licht thema, geïsoleerde test met `CFFIXED_USER_HOME`) **niet** te reproduceren —
ook niet door `isCheckingAll` of het permissie-scherm ↔ hoofdscherm te laten wisselen.

Verschillen met de Media Server om te onderzoeken: donker thema, Schermdeling/virtueel scherm (schaal), lange
looptijd, echte downloads/voortgang.

Aanpak (systematic debugging — geen fix zonder oorzaak):
1. Als de balk zichtbaar is: screenshot van het venster (`screencapture -l <windowid>`; Terminal heeft
   Schermopname-toestemming nodig) en de view-hiërarchie dumpen (bv. tijdelijk debugcode die
   `mainWindow.contentView` recursief logt met frames/klassen, of `NSWindow` titlebar/toolbar-info).
2. Vraag de gebruiker: verdwijnt de balk bij venster verslepen? Bij Recordings → Scheduled? Op het fysieke scherm?
   (Verdwijnt bij verslepen/fysiek scherm ⇒ redraw-probleem, niet layout.)
3. Pas daarna fixen, testen hier, en via `install.sh` installeren (app herstart — check eerst dat er geen
   download loopt in premieres.log).

## Overig
- Log op de MacBook meldde herhaaldelijk LOW DISK SPACE (~4,4 GB vrij); check hier ook de schijfruimte.
- Gebruiker spreekt Nederlands.
