# Reprise

Een macOS-menubalkapp die YouTube-premières voor je opneemt. Reprise houdt de
première in de gaten, neemt de uitzending LIVE op vanaf het eerste moment en haalt
daarna de definitieve VOD binnen, in de beste kwaliteit die YouTube aanbiedt.
`Première → Live → Reprise`.

![Reprise](Artwork/Reprise.png)

## Versie 1.6.75

Nieuw in deze versie: een vernieuwd hoofdvenster met **Scheduled**, **Incoming** en
**Recordings**, een duidelijke kaart voor de eerstvolgende première met de stappen
Verified → Monitoring → Capture LIVE → Save VOD, en bevestiging van precies welke
VOD-versie is binnengehaald: resolutie, codec en beeldsnelheid, in de app én in de
pushmelding. Ook opgelost: een donkere balk die soms over de paginatitel lag.

Apple Silicon, macOS 14 of nieuwer. De app is lokaal ondertekend en niet bij Apple
genotariseerd. De interface is Engels. Reprise maakt gebruik van
[yt-dlp](https://github.com/yt-dlp/yt-dlp) en ffmpeg; die installeer je apart.

## Installeren

Download `Reprise.zip` via [Releases](https://github.com/reprise-labs/reprise/releases).

1. Installeer yt-dlp en ffmpeg met [Homebrew](https://brew.sh): `brew install yt-dlp ffmpeg`.
2. Pak de zip uit en verplaats `Reprise.app` naar je Apps-map.
3. Open Reprise de eerste keer met **rechtsklik → Open**. Omdat de app niet is
   genotariseerd, weigert een gewone dubbelklik; rechtsklik toont de knop *Open toch*.

Updates komen daarna vanzelf binnen via [Sparkle](https://sparkle-project.org):
Reprise kijkt dagelijks, toont de releasenotes en controleert elke download met een
EdDSA-handtekening voordat hij wordt geïnstalleerd.

## Eerste start

Reprise controleert bij het opstarten drie dingen en opent zijn venster als er iets
ontbreekt:

1. **Schrijfrechten op de downloadmap** (standaard `~/Downloads/Reprise`, aan te passen
   in Settings).
2. **Volledige schijftoegang**, nodig om de cookies van Chrome of Safari te lezen voor
   premières waarvoor je ingelogd moet zijn of Premium-kwaliteit:
   Systeeminstellingen → Privacy en beveiliging → Volledige schijftoegang → Reprise.
   Openbare video's lukken ook zonder.
3. **yt-dlp en ffmpeg.** Ontbreekt er een, dan toont Reprise het juiste
   `brew install`-commando.

Met *Check again* worden de controles opnieuw gedaan zonder herstart.

## Gebruik

- **Première toevoegen:** plak de YouTube-link via *Add premiere*. Reprise leest de
  geplande tijd uit en vraagt welke kwaliteit je wilt (Best of Premium).
- **Scheduled:** de eerstvolgende première met zijn voortgang, de rest eronder, en de
  laatst voltooide opname.
- **Incoming:** nieuwe premières die Reprise vindt op kanalen die je volgt. Kanalen
  voeg je toe in Settings; Reprise kijkt één keer per dag, of direct met *Check now*.
- **Recordings:** alle voltooide opnames, met per opname de binnengehaalde versie.
- **Menubalk:** rood betekent dat er iets aandacht nodig heeft, blauw dat er wordt
  gedownload, groen dat alles in orde is. Rechtsklik voor een snel statusmenu.
- **Opstarten bij inloggen:** Settings → General → *Start at login*.

## Wat Reprise precies doet

- Vlak voor de geplande tijd begint Reprise de status van de video te controleren.
- Zodra de première live gaat, start de opname direct, vanaf het begin van de uitzending.
- Daarna wacht Reprise tot YouTube de VOD in volledige kwaliteit aanbiedt, met losse
  beeld- en geluidssporen. Een noodversie in lage kwaliteit wordt niet bewaard; dan
  probeert Reprise het later opnieuw.
- De gedownloade versie wordt vergeleken met de hoogste kwaliteit die voor de video
  beschikbaar was. Alleen na een echte vergelijking staat er *confirmed best available*.
- 24 uur en 1 uur van tevoren volgt een controle: yt-dlp actueel, map- en cookietoegang
  in orde, genoeg schijfruimte en de link werkt nog. Zo zie je problemen terwijl er nog
  tijd is om ze op te lossen.
- Meldt yt-dlp aan het eind van een uitzending een fout terwijl de opname wel compleet
  is, dan herkent Reprise dat en gaat het gewoon verder.
- Tijdens een download gaat de Mac niet in slaap.

## Meldingen

Plak in Settings een Application Token en User Key van [Pushover](https://pushover.net)
voor pushmeldingen op je telefoon: première live, download klaar of mislukt, en de
controles van tevoren. Gewone macOS-meldingen werken zonder instellingen.

## Privacy en verbindingen

Reprise praat alleen met YouTube (via yt-dlp), met Pushover als je dat instelt, en met
GitHub voor updates. Cookies worden lokaal door yt-dlp gelezen en niet verstuurd naar
andere partijen. Er is geen account, geen analytics en geen server van Reprise zelf.

## Gegevens

- Lijst, instellingen en logboek: `~/Library/Application Support/Reprise/`
- Opnames: `~/Downloads/Reprise/` (aan te passen in Settings)

## Bouwen

Xcode Command Line Tools en een Apple Silicon Mac zijn nodig:

```sh
git clone https://github.com/reprise-labs/reprise.git
cd reprise
./install.sh
```

`install.sh` bouwt de app, plaatst hem in `/Applications/Reprise.app`, voegt Sparkle
toe, ondertekent hem en start hem (opnieuw). De eerste keer is internet nodig om
Sparkle op te halen.

### Volledige schijftoegang behouden na een nieuwe build

Een ad-hoc handtekening verandert bij elke build, waardoor macOS de Volledige
schijftoegang vergeet. `install.sh` gebruikt daarom het lokale certificaat
**Encore Local Signing** als dat bestaat. Maak het één keer aan:

```sh
WORKDIR=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/encore.key" -out "$WORKDIR/encore.crt" \
  -days 7300 -nodes -subj "/CN=Encore Local Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -out "$WORKDIR/encore.p12" \
  -inkey "$WORKDIR/encore.key" -in "$WORKDIR/encore.crt" -passout pass:encorebuild
security import "$WORKDIR/encore.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P encorebuild -T /usr/bin/codesign -A
rm -rf "$WORKDIR"
```

Kies bij de eerste vraag van `codesign` *Altijd toestaan*.

## Nieuwe versie uitbrengen

```sh
scripts/release.sh --dry-run 1.6.76 "Releasenotes"   # alle controles, niets publiceren
scripts/release.sh 1.6.76 "Releasenotes"             # echte release
```

Het script controleert eerst of alles klaar is en of er geen opname loopt. Daarna
bouwt het de app, maakt en ondertekent het de zip, maakt het de GitHub-release en
werkt het pas daarna `appcast.xml` bij, zodat bestaande installaties de update nooit
zien voordat het bestand er staat.

## Reprise Labs

Reprise is een apart project naast [Sleeve](https://github.com/reprise-labs/sleeve).
De twee apps hebben eigen versies en downloads.

## Licentie

[MIT](LICENSE)
