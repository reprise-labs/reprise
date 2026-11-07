# Reprise — instructies voor AI-agents (Claude Code én Codex)

Dit bestand is de enige bron; `CLAUDE.md` verwijst hiernaar. Houd het actueel.

## Werkwijze
- De gebruiker spreekt **Nederlands**. Antwoord in het Nederlands.
- Er wordt **alleen op de Mac mini (Media Server)** aan Reprise gewerkt, in deze map.
  Reprise draait hier ook echt en neemt premieres op.
- **Niet pushen, geen release maken en `scripts/publish_release.sh` niet draaien zonder
  uitdrukkelijke toestemming** van de gebruiker. Lokaal committen mag.
- Pushen naar `reprise-labs/reprise` kan alleen met het gh-account `reprise-labs` (het actieve
  account `andrevanos` heeft geen schrijfrechten). Zonder het actieve account te wisselen:
  `git -c credential.helper= -c credential.helper='!f(){ echo username=x-access-token; echo "password=$(gh auth token --user reprise-labs)"; }; f' push`
  en voor `gh`: `GH_TOKEN=$(gh auth token --user reprise-labs) gh …`.
- `./install.sh` herstart de draaiende app. Kijk eerst in `premieres.log` (en `pgrep yt-dlp`)
  of er geen opname bezig is.
- Bugs: eerst de oorzaak aantonen, dan pas fixen (zie "Debuggen" hieronder).

## Project
- Swift package (`Package.swift`, target `Reprise`, bron in `Sources/PremiereMonitor/`),
  menubalk-app in AppKit + SwiftUI, updates via Sparkle.
- Bouwen: `swift build -c release --build-system native` (native build system: werkt met
  alleen de Command Line Tools).
- Installeren op deze Mac: `./install.sh` → `/Applications/Reprise.app`, gesigneerd met het
  certificaat **"Encore Local Signing"** (login-keychain). Die vaste identiteit zorgt dat
  Volledige schijftoegang na een rebuild blijft gelden. Bundle-ID: `com.media.reprise`.
- Versie: `Resources/VERSION` (enige bron, `install.sh` zet hem in Info.plist).

## Paden
- Data: `~/Library/Application Support/Reprise/` (`videos.json`, `settings.json`,
  `channels.json`, `discovered.json`, `premieres.log`).
- Downloads: `~/Downloads/Reprise/` (de map "Anouk Pinkpop — Keep" daarin niet aanraken).
- Oude installaties (1.6.64 en de tijdelijke `reprise_new`-build) staan opzij in
  `~/Reprise-oud-1.6.64/`.

## Release (alleen op verzoek)
Volledig automatisch, geen handwerk van de gebruiker:

    scripts/release.sh --dry-run <versie> "<release notes>"   # alle checks + proefsignering
    scripts/release.sh <versie> "<release notes>"             # echte release

Het script controleert eerst alles (account `reprise-labs`, schrijfrechten, versie nog vrij,
geen download bezig, Sparkle-signering werkt zonder Keychain-vraag), en doet dan: VERSION
ophogen + commit, `install.sh`, zip, `sign_update` + verificatie, push, `gh release create`,
en pas daarna de appcast (`publish_release.sh`). Commits van het script staan op naam van
het no-reply-adres van `reprise-labs`.

## Debuggen van de draaiende app
- Vensters: `CGWindowListCopyWindowInfo` (Swift-script) → `screencapture -x -o -l <windowid>`.
- Accessibility-boom (frames van knoppen/tekst): `AXUIElementCreateApplication(pid)` recursief.
- View-hiërarchie live: `lldb -p <pid> --batch -o 'expr -l objc -O -- [[[(NSWindow*)[[NSApplication
  sharedApplication] windowWithWindowNumber:<id>] contentView] superview] _subtreeDescription]' -o detach`
  (Ontwikkelaarstoegang moet zijn toegestaan; de app pauzeert kort).
- Voorbeeld (7-11-2026): de donkere balk over de paginatitel was een `NSTitlebarBackgroundView`
  van de NavigationSplitView; oorzaak was een hoofdvenster zonder `.fullSizeContentView`.
  Dat venster moet die vlag houden (zie `StatusItemController.swift`).
