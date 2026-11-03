# Moteve Damage Meter

A **Moteve Damage Meter** egy könnyű damage meter addon a WoW Forever klienshez. A játék beépített `C_DamageMeter` adataiból mutatja a sebzést, gyógyítást, elnyelést, kapott sebzést, megszakításokat és dispeleket, egy külön módban pedig a csapat threat-jét a célpontodon. Egyszerre legfeljebb négy ablak lehet nyitva, a Moteve addonok „arkán üveg” stílusában: keret nélkül, halvány háttérrel és vékony, izzó, kasztszínű vonalakkal.

**Aktuális verzió: 0.5.0**

[Legfrissebb addon letöltése (ZIP)](https://github.com/zolesz05/Kodo-DPS/raw/main/downloads/Moteve%20Damage%20Meter.zip)

A `downloads` mappában mindig csak a legfrissebb telepíthető `Moteve Damage Meter.zip` szerepel, így frissítéskor ugyanaz a letöltési link használható.

## Telepítés

1. Töltsd le és csomagold ki a fenti ZIP-et.
2. Másold a `Moteve Damage Meter` mappát a játék `Interface/AddOns/` könyvtárába.
3. A karakterválasztón engedélyezd a **Moteve Damage Meter** addont, majd lépj be (vagy játékban `/reload`).

```text
Interface/
└── AddOns/
    └── Moteve Damage Meter/
        ├── Moteve Damage Meter.toc
        ├── Moteve.lua
        ├── Theme.lua
        ├── Fonts/
        └── Textures/
```

A mappanevet tartsd meg: a `Moteve Damage Meter.toc` közvetlenül a `Moteve Damage Meter` mappában legyen. Ha egy új addon még nem jelenik meg a listában, indítsd újra a klienst. A `WTF` könyvtárat tartsd meg, mert abban vannak a mentett beállítások (`MoteveDB`).

## Használat

- Az ablak halvány háttérrel jelenik meg; az egérmutatót fölé víve erősebb lesz.
- Soronként: helyezés, név kasztszínnel, összeg, DPS/HPS és százalék. A név alatti vékony, kasztszínű vonal mutatja az arányt; a lila pötty jelöli a saját karaktered.
- A százalék harc után jelenik meg, kb. 270 px-nél szélesebb ablakban.
- A fejlécben a mód neve látható. Rákattintva lenyíló menü nyílik:
  - mód: **Sebzés**, **Gyógyítás**, **Elnyelés**, **Kapott sebzés**, **Megszakítások**, **Dispelek**, **Threat**;
  - időszak: **Aktuális harc** vagy **Összesített** (threat módban nincs);
  - adatok törlése, az ablak zárolása és **Ablak eltávolítása**.
- A fejléc jobb felső sarkában az **Aktuális** felirat egy harcválasztó. Rákattintva az aktuális harc mellett a játék által még tárolt korábbi, lezárt harcok közül választhatsz: legfeljebb 10 közül, a legújabb van elöl, névvel és időtartammal. Az ablak ekkor annak a harcnak a sorait, spellenkénti bontását és összesítő sorát mutatja, a fejlécben pedig a harc neve látszik. Ha a név nem ismert vagy titkos, „N. harc” jelenik meg. A választó csak **Aktuális harc** időszakban és threat módon kívül működik. Új harc kezdetekor, az adatok törlésekor, időszakváltáskor és `/reload` után az ablak visszaáll **Aktuális**-ra. A kiválasztás ablakonként külön van, és nem mentődik. Ha a kiválasztott harcot a játék már nem tárolja, az ablak az aktuális harcot mutatja.
- A fejléc húzásával mozgatható, a jobb alsó saroknál fogva (rámutatáskor látszik) átméretezhető. A hely és a méret mentődik.
- Egérgörgővel a lista görgethető. Egy sorra mutatva harc után spellenkénti bontás jelenik meg.
- A láblécben a harc hossza vagy a „Harcban” felirat, az összesített érték és a csapat-DPS látható.

### Több ablak

Egyszerre legfeljebb **négy** ablak lehet nyitva, például egy a sebzésnek és egy a gyógyításnak. Minden ablaknak saját módja, időszaka, mérete, helye és zárolása van, és mindez `/reload` után is megmarad. Új ablakot a minimap gombbal vagy a `/moteve new` paranccsal nyithatsz; ablakot a saját menüjének **Ablak eltávolítása** pontjával vagy a minimap gomb menüjéből zárhatsz be. Az utolsó ablak nem távolítható el.

### Threat mód

A **Threat** mód a csapat minden tagjának (pet nélkül) threat-jét mutatja a célpontodon; ha nincs megtámadható célpontod, a fókuszodon. Ha egyik sincs, a „Nincs célpont” felirat jelenik meg. A sor a threat százalékát mutatja, a vékony vonal 0–100%-ig telik, a ciánkék gyűrű a célpontot tankoló játékost jelöli. A fejléc jobb oldalán látszik, hogy a célpont vagy a fókusz adatai láthatók.

A **Threat ablak** egy kisebb, kompakt (200×140 px, lábléc nélküli, alacsonyabb sorokkal) ablakot nyit ebben a módban, így DPS-ként a sebzés mellett a threat-re is figyelhetsz.

A threat értékei bizonyos helyzetekben (például dungeonben, harc közben) **titkosak** lehetnek. Ilyenkor a játék még kirajzolja a sávot és a feliratot, de az addon nem rendezheti őket: a sorok csapatsorrendben maradnak, és a tank-jelölés sem jelenik meg.

### Minimap gomb

A minimap szélén egy kerek **M** gomb található.

- **Bal klikk:** menü az **+ Új ablak**, **+ Threat ablak** és ablakonként egy **Eltávolítás: <n>. ablak (<mód>)** ponttal.
- **Jobb klikk:** minden ablak megjelenítése / elrejtése.
- **Húzás:** a gomb a minimap széle mentén mozgatható, a helye mentődik.

A gomb a `/moteve minimap` paranccsal rejthető el és hozható vissza. Szögletes vagy lecserélt minimapnél (például ElvUI) a gomb a minimap körül, kör alakban helyezkedik el.

## Parancsok

| Parancs | Művelet |
| --- | --- |
| `/moteve` vagy `/mtv` | Minden ablak megjelenítése / elrejtése |
| `/moteve toggle` | Minden ablak megjelenítése / elrejtése |
| `/moteve show` / `/moteve hide` | Minden ablak megjelenítése / elrejtése |
| `/moteve lock` / `/moteve unlock` | Minden ablak zárolása / feloldása |
| `/moteve reset` | Mért adatok törlése |
| `/moteve scale 1.2` | Minden ablak méretaránya (0,5–2) |
| `/moteve center` | Minden ablak a képernyő közepére |
| `/moteve new` | Új ablak (legfeljebb 4) |
| `/moteve threat` | Új kompakt threat ablak |
| `/moteve minimap` | Minimap gomb elrejtése / megjelenítése |

## Működés és korlátok

WoW Foreveren az addonok nem férnek hozzá a combat loghoz, ezért a Moteve a Blizzard beépített `C_DamageMeter` adataiból dolgozik. Harc közben a nevek és a számok „titkos” értékek: a játék megjeleníti őket, de az addon nem számolhat velük, ezért a százalék és a spellenkénti bontás csak harc után jelenik meg.

A threat mód nem a `C_DamageMeter`, hanem a játék threat-adatai (`UnitDetailedThreatSituation`) alapján dolgozik. Ezek az értékek is lehetnek titkosak, ilyenkor a sorrend a csapat sorrendje marad.

Ha nincs adat, kapcsold be a játék saját damage meterét a beállításokban; az ablaka utána elrejthető.

## Kompatibilitás

A célkliens **WoW Forever**, a TOC Interface-értéke **16001**. A mentés neve `MoteveDB`. A 0.4.0 az ablakokat a `MoteveDB.windows` listában menti; a 0.3.x beállításai frissítéskor automatikusan az első ablakba kerülnek, így az ablak ugyanott, ugyanakkorán és ugyanabban a módban jelenik meg. A feliratok a csomagban lévő Marcellus és Barlow betűtípusokat használják, amelyek a magyar ő/ű betűket is tartalmazzák.

## Fejlesztés

A `tests/` mappában a játékon kívül futtatható tesztek vannak, egy egyszerű WoW API-utánzattal (`tests/wow_mock.lua`). A repó gyökeréből Lua 5.1-gyel futtathatók:

```sh
lua5.1 tests/moteve_test.lua
```

A tesztek nem kerülnek a letölthető ZIP-be.

## Hibajelentés és források

Hibát az [Issues oldalon](https://github.com/zolesz05/Kodo-DPS/issues) jelezhetsz. Add meg a kliens és az addon verzióját, valamint a reprodukálás lépéseit.

A teljes addon a [Moteve Damage Meter](Moteve%20Damage%20Meter/) mappában található, a [rövid játékbeli leírás](Moteve%20Damage%20Meter/README.txt) is ott van. A Marcellus és Barlow betűtípusok SIL Open Font License fájljai a `Moteve Damage Meter/Fonts/` mappában szerepelnek.
