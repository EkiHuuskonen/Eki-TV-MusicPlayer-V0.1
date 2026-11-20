# Eki-TV MusicPlayer V0.1

Yksinkertainen macOS-musiikkisoitin (SwiftUI), joka hakee ja soittaa **laillisesti ilmaista** musiikkia avoimista lähteistä.

## Ominaisuudet
- Haku usealta lähteeltä: Internet Archive, Audius, ccMixter, Openverse (sis. Jamendon CC-musiikkia) ja nettiradiot (Radio Browser)
- Albumit listataan haussa ensin ALBUMI-merkillä
- Soittolistat, suosikit ja oma kirjasto hakemistopuuna (artisti → albumi → kappale)
- "Nyt soi" -näkymä ja äänenvoimakkuuden säätö (⌘↑ / ⌘↓)
- Sivupalkissa kappaleen **sävellaji ja soinnut** (automaattinen arvio kromagrammista)

## Rakentaminen
Vaatii macOS 14+ ja täyden Xcoden (SwiftUI-makrot).

```bash
./build_app.sh
open ArkistoSoitin.app
```

Ikoni piirretään koodilla: `swift tools/make_icon.swift Resources/AppIcon.iconset`.

## Lähteet ja lisenssit
Sovellus ei sisällä musiikkia. Kappaleet haetaan suoraan palvelujen avoimista rajapinnoista, ja jokaisen kappaleen lisenssi (esim. Creative Commons) näkyy "Nyt soi" -näkymässä, kun se on tiedossa. Tarkista käytettävien palvelujen käyttöehdot ennen jakelua.

Versio 0.1 – työn alla.
