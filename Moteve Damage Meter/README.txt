Moteve Damage Meter 0.5.0 - WoW Forever (Interface 16001)
"Arkán üveg" stílus, mint a Moteve Quest és a Moteve Chat.

TELEPÍTÉS
  A "Moteve Damage Meter" mappát másold a WoW Forever Interface\AddOns mappájába, majd /reload.

HASZNÁLAT
  - Keret nélküli, halvány háttér; egérrel fölé menve erősebb.
  - Soronként: helyezés, név osztályszínnel, összeg, DPS/HPS, százalék
    (a százalék harc után, kb. 270 px-nél szélesebb ablakban).
    A név alatt vékony, izzó, osztályszínű vonal mutatja az arányt. Lila pötty = te.
  - A fejlécben a mód neve: kattintásra lenyíló menü
    (Sebzés, Gyógyítás, Elnyelés, Kapott sebzés, Megszakítások, Dispelek, Fenyegetés;
    Aktuális harc / Összesített; adatok törlése; ablak zárolása; ablak eltávolítása).
  - Jobb felső "Aktuális" felirat: harcválasztó. Az aktuális harc mellett a játék által
    még tárolt utolsó (legfeljebb 10) lezárt harc választható, névvel és időtartammal.
    Csak Aktuális harc időszakban, fenyegetés módon kívül. Új harc, adattörlés,
    időszakváltás és /reload után visszaáll "Aktuális"-ra; nem mentődik.
  - Fejléc húzása: mozgatás. Jobb alsó sarok (egérrel fölé menve látszik): átméretezés.
  - Görgő: lista görgetése. Sorra vitt egér: spellenkénti bontás (harc után).
  - Lábléc: harc hossza vagy "Harcban", összesített érték és csapat-DPS.

TÖBB ABLAK
  - Legfeljebb 4 ablak, mindegyiknek saját módja, időszaka, mérete, helye és zárolása.
    /reload után is megmaradnak. Az utolsó ablak nem távolítható el.

FENYEGETÉS MÓD
  - A csapat minden tagjának (pet nélkül) fenyegetése a célpontodon; ha nincs megtámadható
    célpont, a fókuszon. Ha egyik sincs: "Nincs célpont". Ciánkék gyűrű = ő tankol.
  - "Fenyegetés ablak": kompakt, 200x140-es ablak lábléc nélkül, alacsonyabb sorokkal.
  - Az értékek néha (pl. dungeonben, harc közben) titkosak: ilyenkor a sáv és a felirat
    frissül, de a sorok csapatsorrendben maradnak, és nincs tank-jelölés.

MINIMAP GOMB
  - Bal klikk: menü (+ Új ablak, + Fenyegetés ablak, ablakonként Eltávolítás).
  - Jobb klikk: minden ablak megjelenítése / elrejtése. Húzás: mozgatás a minimap szélén.

PARANCSOK: /moteve vagy /mtv
  toggle | show | hide | lock | unlock | reset | scale 0.5-2 | center
  (show/hide/lock/unlock/scale/center minden ablakra vonatkozik)
  new      - új ablak (legfeljebb 4)
  threat   - új kompakt fenyegetés ablak
  minimap  - minimap gomb elrejtése / megjelenítése

MŰKÖDÉS
  WoW Foreveren az addonok nem férnek hozzá a combat loghoz, ezért a Moteve a Blizzard
  beépített C_DamageMeter adataiból dolgozik. Harc közben a nevek és számok "titkos" értékek:
  a játék megjeleníti őket, de az addon nem számolhat velük, ezért a százalék és a bontás
  harc után jelenik meg. Ha nincs adat, kapcsold be a játék saját damage meterét a
  beállításokban (az ablaka utána elrejthető).
  Betűtípusok: Marcellus és Barlow (SIL Open Font License, a Fonts mappában a licenccel).
