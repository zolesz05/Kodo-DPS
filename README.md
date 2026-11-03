# Moteve Damage Meter

A **Moteve Damage Meter** egy könnyű damage meter addon a WoW Forever klienshez. A játék beépített `C_DamageMeter` adataiból mutatja a sebzést, gyógyítást, elnyelést, kapott sebzést, megszakításokat és dispeleket, a Moteve addonok „arkán üveg” stílusában: keret nélkül, halvány háttérrel és vékony, izzó, kasztszínű vonalakkal.

**Aktuális verzió: 0.3.1**

[Legfrissebb addon letöltése (ZIP)](https://github.com/zolesz05/Kodo-DPS/raw/main/downloads/Moteve.zip)

A `downloads` mappában mindig csak a legfrissebb telepíthető `Moteve.zip` szerepel, így frissítéskor ugyanaz a letöltési link használható.

## Telepítés

1. Töltsd le és csomagold ki a fenti ZIP-et.
2. Másold a `Moteve` mappát a játék `Interface/AddOns/` könyvtárába.
3. A karakterválasztón engedélyezd a **Moteve Damage Meter** addont, majd lépj be (vagy játékban `/reload`).

```text
Interface/
└── AddOns/
    └── Moteve/
        ├── Moteve.toc
        ├── Moteve.lua
        ├── Theme.lua
        ├── Fonts/
        └── Textures/
```

A mappanevet tartsd meg: a `Moteve.toc` közvetlenül a `Moteve` mappában legyen. Ha egy új addon még nem jelenik meg a listában, indítsd újra a klienst. A `WTF` könyvtárat tartsd meg, mert abban vannak a mentett beállítások (`MoteveDB`).

## Használat

- Az ablak halvány háttérrel jelenik meg; az egérmutatót fölé víve erősebb lesz.
- Soronként: helyezés, név kasztszínnel, összeg, DPS/HPS és százalék. A név alatti vékony, kasztszínű vonal mutatja az arányt; a lila pötty jelöli a saját karaktered.
- A százalék harc után jelenik meg, kb. 270 px-nél szélesebb ablakban.
- A fejlécben a mód neve látható. Rákattintva lenyíló menü nyílik:
  - mód: **Sebzés**, **Gyógyítás**, **Elnyelés**, **Kapott sebzés**, **Megszakítások**, **Dispelek**;
  - időszak: **Aktuális harc** vagy **Összesített**;
  - adatok törlése és az ablak zárolása.
- A fejléc húzásával mozgatható, a jobb alsó saroknál fogva (rámutatáskor látszik) átméretezhető. A hely és a méret mentődik.
- Egérgörgővel a lista görgethető. Egy sorra mutatva harc után spellenkénti bontás jelenik meg.
- A láblécben a harc hossza vagy a „Harcban” felirat, az összesített érték és a csapat-DPS látható.

## Parancsok

| Parancs | Művelet |
| --- | --- |
| `/moteve` vagy `/mtv` | Ablak megjelenítése / elrejtése |
| `/moteve toggle` | Ablak megjelenítése / elrejtése |
| `/moteve show` / `/moteve hide` | Ablak megjelenítése / elrejtése |
| `/moteve lock` / `/moteve unlock` | Ablak zárolása / feloldása |
| `/moteve reset` | Mért adatok törlése |
| `/moteve scale 1.2` | Méretarány (0,5–2) |
| `/moteve center` | Ablak a képernyő közepére |

## Működés és korlátok

WoW Foreveren az addonok nem férnek hozzá a combat loghoz, ezért a Moteve a Blizzard beépített `C_DamageMeter` adataiból dolgozik. Harc közben a nevek és a számok „titkos” értékek: a játék megjeleníti őket, de az addon nem számolhat velük, ezért a százalék és a spellenkénti bontás csak harc után jelenik meg.

Ha nincs adat, kapcsold be a játék saját damage meterét a beállításokban; az ablaka utána elrejthető.

## Kompatibilitás

A célkliens **WoW Forever**, a TOC Interface-értéke **16001**. A mentés neve `MoteveDB`. A feliratok a csomagban lévő Marcellus és Barlow betűtípusokat használják, amelyek a magyar ő/ű betűket is tartalmazzák.

## Hibajelentés és források

Hibát az [Issues oldalon](https://github.com/zolesz05/Kodo-DPS/issues) jelezhetsz. Add meg a kliens és az addon verzióját, valamint a reprodukálás lépéseit.

A teljes addon a [Moteve](Moteve/) mappában található, a [rövid játékbeli leírás](Moteve/README.txt) is ott van. A Marcellus és Barlow betűtípusok SIL Open Font License fájljai a `Moteve/Fonts/` mappában szerepelnek.
