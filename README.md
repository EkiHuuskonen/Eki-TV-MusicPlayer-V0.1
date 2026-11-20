# Eki-TV MusicPlayer V0.1

Yksinkertainen macOS-musiikkisoitin (SwiftUI), joka hakee ja soittaa **laillisesti ilmaista** musiikkia avoimista lähteistä.

## Ominaisuudet
- Haku usealta lähteeltä: Internet Archive, Audius, ccMixter, Openverse (sis. Jamendon CC-musiikkia) ja nettiradiot (Radio Browser)
- Albumit listataan haussa ensin ALBUMI-merkillä
- Soittolistat, suosikit ja oma kirjasto hakemistopuuna (artisti → albumi → kappale)
- "Nyt soi" -näkymä ja äänenvoimakkuuden säätö (⌘↑ / ⌘↓)
- Sivupalkissa kappaleen **sävellaji ja soinnut** (automaattinen arvio kromagrammista)

## Versiot samassa repossa

| Kansio | Alusta | Tekniikka |
|---|---|---|
| `Shared/`, `macOS/` | macOS 14+ | SwiftUI (natiivi) |
| `Shared/`, `iOS/` | iPhone ja iPad (iOS 18+) | SwiftUI |
| `Shared/`, `tvOS/` | Apple TV (tvOS 18+) | SwiftUI |
| `electron/` | Windows, macOS, Linux | Electron + React + TypeScript |

Apple-versiot jakavat kansion `Shared/` koodin (mallit, hakulähteet, soitin, kirjasto, sointuanalyysi). Kaikilla versioilla on samat ominaisuudet ja sama `library.json`-tiedostomuoto (suosikit ja soittolistat).

## Apple-versiot (macOS, iPhone, iPad, Apple TV)
Vaatii täyden Xcoden ja XcodeGenin (`brew install xcodegen`).

```bash
xcodegen generate                 # luo EkiTVMusicPlayer.xcodeproj tiedostosta project.yml
open EkiTVMusicPlayer.xcodeproj   # kohteet: MusicPlayer-macOS / -iOS / -tvOS
./build_app.sh                    # rakentaa macOS-sovelluksen komentoriviltä
```

Omat allekirjoitusasetukset: kopioi `Config/Local.xcconfig.example` nimellä `Config/Local.xcconfig` ja täytä `DEVELOPMENT_TEAM` (tiedostoa ei viedä gitiin).

## Electron-versio (Windows ym.)
Vaatii Node.js 22+.

```bash
cd electron
npm install
npm run dev        # kehitysajo
npm run dist:win   # Windows-asennusohjelma (rakennetaan parhaiten Windows-koneella)
```

Windows-asennusohjelman voi rakentaa myös GitHub Actionsilla: *Actions → Build Windows → Run workflow*. Tagi `vX.Y.Z` julkaisee valmiit `.exe`-tiedostot Releaseen.

## Lähteet ja lisenssit
Sovellus ei sisällä musiikkia. Kappaleet haetaan suoraan palvelujen avoimista rajapinnoista, ja jokaisen kappaleen lisenssi (esim. Creative Commons) näkyy "Nyt soi" -näkymässä, kun se on tiedossa. Tarkista käytettävien palvelujen käyttöehdot ennen jakelua.

Versio 0.1 – työn alla.

## Eki-TV-sovellus

Soitin on mukana myös Eki-TV-fanisovelluksen (iPhone, iPad, Apple TV) "Musiikki"-välilehtenä.
Jaettu koodi synkataan sinne komennolla `./sync_ekitv.sh`; aja se aina, kun `Shared/`, `iOS/` tai `tvOS/` muuttuu.
