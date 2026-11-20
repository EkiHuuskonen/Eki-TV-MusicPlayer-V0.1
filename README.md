# Eki-TV MusicPlayer V0.1

Yksinkertainen macOS-musiikkisoitin (SwiftUI), joka hakee ja soittaa **laillisesti ilmaista** musiikkia avoimista lähteistä.

## Ominaisuudet
- Haku usealta lähteeltä: Internet Archive, Audius, ccMixter, Openverse (sis. Jamendon CC-musiikkia) ja nettiradiot (Radio Browser)
- Albumit listataan haussa ensin ALBUMI-merkillä
- Soittolistat, suosikit ja oma kirjasto hakemistopuuna (artisti → albumi → kappale)
- "Nyt soi" -näkymä ja äänenvoimakkuuden säätö (⌘↑ / ⌘↓)
- Sivupalkissa kappaleen **sävellaji ja soinnut** (automaattinen arvio kromagrammista)

## Kaksi versiota samassa repossa

| Kansio | Alusta | Tekniikka |
|---|---|---|
| `/` (Sources/, Package.swift) | macOS 14+ | SwiftUI (natiivi) |
| `electron/` | Windows, macOS, Linux | Electron + React + TypeScript |

Molemmilla on samat ominaisuudet ja sama `library.json`-tiedostomuoto (suosikit ja soittolistat).

## Electron-versio (Windows ym.)
Vaatii Node.js 22+.

```bash
cd electron
npm install
npm run dev        # kehitysajo
npm run dist:win   # Windows-asennusohjelma (rakennetaan parhaiten Windows-koneella)
```

Windows-asennusohjelman voi rakentaa myös GitHub Actionsilla: *Actions → Build Windows → Run workflow*. Valmis `.exe` ladataan työnkulun artifacteista.

## macOS-versio (SwiftUI)
Vaatii macOS 14+ ja täyden Xcoden (SwiftUI-makrot).

```bash
./build_app.sh
open ArkistoSoitin.app
```

Ikoni piirretään koodilla: `swift tools/make_icon.swift Resources/AppIcon.iconset`.

## Lähteet ja lisenssit
Sovellus ei sisällä musiikkia. Kappaleet haetaan suoraan palvelujen avoimista rajapinnoista, ja jokaisen kappaleen lisenssi (esim. Creative Commons) näkyy "Nyt soi" -näkymässä, kun se on tiedossa. Tarkista käytettävien palvelujen käyttöehdot ennen jakelua.

Versio 0.1 – työn alla.
