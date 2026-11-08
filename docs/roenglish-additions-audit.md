# AdditionsGenerator: Bestandsaufnahme

Stand: ROEnglishRE `680a2f2126c8eb5872bf06cf441685c408ed1358`. Grundlage: [Upstream-Inventar](roenglish-upstream-inventory.md), der [AdditionsGenerator](https://github.com/raiken-mf/ROenglishRE/blob/680a2f2126c8eb5872bf06cf441685c408ed1358/Tools/AdditionsGenerator.bat) und der [Additions-Quellbaum](https://github.com/raiken-mf/ROenglishRE/tree/680a2f2126c8eb5872bf06cf441685c408ed1358/Additions) der gepinnten GitHub-Revision sowie read-only `roBrowserLegacy/src/DB/DBManager.js`. Diese Bestandsaufnahme beruht auf statischer Prüfung; Generator, Tests und Client wurden für sie nicht ausgeführt.

## Leseschlüssel

`D` bezeichnet Quelle `Additions/data` und Ziel `Tools/Client/data`, `S` Quelle `Additions/SystemEN` und Ziel `Tools/Client/SystemEN`. Relative Pfade gelten auf beiden Seiten; ein Pfeil zeigt eine Umbenennung. Verzeichnisse und Wildcards stehen wie im Batch. `texture/<legacy>/map` ersetzt den nicht-ASCII-Pfadbestandteil; dessen Byte-Kodierung ist ungeprüft. Menü 0 und Exit kopieren nichts. Datumsausdrücke nennen die im Zweig vorkommenden Vergleiche; sie gelten jeweils nur für die im Batch bedingten Dateien. Bei Gesamtpaketen sind die Anweisungen dateispezifisch, nicht zwangsläufig die Vereinigung der Einzelzweige.

**Status aller Zeilen:** Auswahl statisch erfasst; tatsächliches Kopierergebnis, Abhängigkeiten, Format und Client-Kompatibilität ungeprüft, soweit unten nicht ausdrücklich belegt. Loader-Spalte: fallunabhängige Suche nach den expliziten Dateinamen ausschließlich in `DBManager.js`; ein Treffer ist eine Fundstelle, kein Funktionsnachweis. „Kein direkter Treffer“ schließt andere oder dynamische Loader nicht aus. Verzeichnis- und Wildcard-Inhalte wurden für diese Suche nicht expandiert. **Tests:** Kein dedizierter Test für die jeweilige Auswahl nachgewiesen, außer den unten genannten Teilprüfungen; die Testsammlung wurde nicht vollständig semantisch auditiert.

Der Generator setzt den angekündigten Standard irrtümlich auf `date` statt `cdate`, validiert die Eingabe nicht, löscht den bestehenden Client-Baum nicht und überschreibt mit `xcopy /C /Y`; „Copied“ bestätigt keinen Erfolg.

## Belegte Ladepfade und Abhängigkeiten

`DBManager.js:310` definiert `data/luafiles514/lua files/` als Lua-Basis. Headgear lädt `accessoryid` und `accname` gemeinsam (460); Roben `spriterobeid` und `spriterobename` (468). World Map lädt `worldviewdata_language`, `worldviewdata_list` und `worldviewdata_table` (4982), nicht das ausgewählte `worldviewdata_info`. Stateicon lädt `efstids`, `stateiconimginfo` und `stateiconinfo` (7196); letzteres fehlt im Additions-Pfad und muss gegebenenfalls aus einer anderen Schicht kommen. Skillinfo verwendet unter anderem `skillid`, `skilldescript`, `skillinfolist` und `skilltreeview` (526–548). Quellen und Kompatibilität anderer Schichten bleiben ungeprüft.

PetEvolution wird als `System/PetEvolutionCln.lub` über System-Aliase angefragt (`DBManager.js:487–488`); `images/remote/apache-access.conf:28–29` leitet bei fehlender System-Datei auf `SystemEN/PetEvolution.lub` um. Dies hängt von Serverkonfiguration und vorhandenen Dateien ab. Für Karten ist ein generischer Pfad über `roBrowserLegacy/src/Renderer/MapRenderer.js:191` belegt (Kartenname zu `.rsw`); weitere Dateien und Assets jeder Karte sowie individuelle Minimap-Ladepfade sind ungeprüft.

## Vorhandene Teiltests und Implementierung

Die ausgewählte Additions-WorldMap-Tabelle (`worldviewdata_table.lub`) und die
Renewal-Sprachdatei (`worldviewdata_language.lub`) der gepinnten Revision
`680a2f2126c8eb5872bf06cf441685c408ed1358` passen im Rohzustand nicht
vollständig zusammen: Die sechs Schlüssel `MSI_102_CH1_FILD1`,
`MSI_2_CH1_ZERO1` bis `MSI_2_CH1_ZERO4` und `MSI_DUN51` wurden im Upstream
zwar mit dem `2025-08-02`-Update (`d336ab454031fda5868e710cbf2435216474bff4` /
`8e71824234385c7cd5084ccbd6976c8dbeb44019`) eingeführt, beim Übertragen der
erweiterten `worldviewdata_table.lub` nach `Additions/`
(`a2e9b9dd94511a345a730faad9fa988f182a8fa2`) jedoch nicht in
`Translation/Renewal/.../worldviewdata_language.lub` übernommen. Der Generator
ergänzt diese sechs Upstream-Einträge ausschließlich in der erzeugten Kopie von
`worldviewdata_language.lub`, nachdem der kanonische SHA-256-Hash der gepinnten
Quelldatei und genau eine Ersetzungsstelle geprüft wurden; Quelle und
Benutzer-Overrides bleiben unverändert. Die tatsächliche Darstellung im Client
hängt weiterhin auch von den geladenen GRFs ab.

`scripts/check-roenglish-generator.php` prüft mit synthetischen Fixtures unter anderem sechs Texttabellen, `stateicon/efstids`, `stateiconimginfo`, `worldviewdata_table`, Cash-Shop-Banner, die ItemDBNameTbl-Grenze und ein `.gat`-Beispiel. `scripts/check-roenglish.py` vergleicht ausgewählte Additions-Dateien; `scripts/check-roenglish.sh` prüft PetEvolution mit Lua; `scripts/check-compose.py` prüft unter anderem die PetEvolution-Weiterleitung. Die aktuelle [CI-Konfiguration](../.github/workflows/ci.yml) führt diese vorhandenen Generator-Fixtures, die Übersetzungsprüfung einschließlich `check-roenglish.py` und den Compose-Smoke-Test aus, wenn der Scope als relevant erkannt wird. Ein konkretes CI-Laufergebnis wurde für diese Bestandsaufnahme nicht überprüft. Diese Tests belegen keine vollständige Menüäquivalenz oder Client-Laufzeit. `images/remote/roenglish-generate.php` implementiert eine explizite Teilmenge; dessen `all` entspricht nicht der vollständigen Batch-Auswahl.

## Data

`itemmoveinfov5.txt` is deliberately not applied as a general override yet.
The client loads eight restriction flags from this table starting at
`PACKETVER=20150422`, and displays the corresponding prohibition when a flag
is `1`. The pinned Additions and Pre-Renewal tables disagree for 363 of 1,449
shared item IDs: for example, the Storage flag changes from `0` to `1` for
1183, 1184 and 1279, and from `1` to `0` for 6046. These data describe
server-dependent restrictions, so format compatibility alone does not show
which value is correct for an installation. The client requests the mixed-case
path `data/ItemMoveInfoV5.txt`; case-sensitive loose-file override precedence
also needs to be verified before automatically installing it.

| Auswahl | Regel; Quelle → Ziel | roBrowser-Fundstelle |
|---|---|---|
| 1 All in One Package | keine Datumsbedingung; Gesamtpaket; `D:*.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 2 bookitemnametable.txt | keine Datumsbedingung; `D:bookitemnametable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 3 buyingstoreitemlist.txt | keine Datumsbedingung; `D:buyingstoreitemlist.txt` | buyingstoreitemlist.txt: DBManager.js:905 |
| 4 card*.txt | keine Datumsbedingung; `D:carditemnametable.txt`<br>`D:cardpostfixnametable.txt`<br>`D:num2cardillustnametable.txt` | cardpostfixnametable.txt: DBManager.js:855; num2cardillustnametable.txt: DBManager.js:836 |
| 5 etcinfo.txt | keine Datumsbedingung; `D:etcinfo.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 6 exceptionminimapnametable.txt | keine Datumsbedingung; `D:exceptionminimapnametable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 7 fogParameterTable.txt | keine Datumsbedingung; `D:fogParameterTable.txt` | fogParameterTable.txt: DBManager.js:866 |
| 8 indoorrswtable.txt | keine Datumsbedingung; `D:indoorrswtable.txt` | indoorrswtable.txt: DBManager.js:867 |
| 9 itemmoveinfov5.txt | keine Datumsbedingung; `D:itemmoveinfov5.txt` | itemmoveinfov5.txt: DBManager.js:4443 |
| 10 leveluseskillspamount.txt | keine Datumsbedingung; `D:leveluseskillspamount.txt` | leveluseskillspamount.txt: DBManager.js:790 |
| 11 manner.txt | keine Datumsbedingung; `D:manner.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 12 mapobjlighttable.txt | keine Datumsbedingung; `D:mapobjlighttable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 13 mappostable.txt | keine Datumsbedingung; `D:mappostable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 14 metalprocessitemtable.txt | keine Datumsbedingung; `D:metalprocessitemtable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 15 mp3nametable.txt | keine Datumsbedingung; `D:mp3nametable.txt` | mp3nametable.txt: DBManager.js:372 |
| 16 resnametable.txt | keine Datumsbedingung; `D:resnametable.txt` | resnametable.txt: DBManager.js:403 |
| 17 viewpointtable.txt | keine Datumsbedingung; `D:viewpointtable.txt` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |

## Lua

| Auswahl | Regel; Quelle → Ziel | roBrowser-Fundstelle |
|---|---|---|
| 1 All in One Package | geq 20211028, geq 20230802, geq 20240311, geq 20240417, geq 20240502, geq 20250618; Gesamtpaket; `D:luafiles514/lua files/datainfo/accessoryid.lub`<br>`D:luafiles514/lua files/datainfo/accname.lub`<br>`D:luafiles514/lua files/datainfo/tb_layer_priority.lub`<br>`D:luafiles514/lua files/datainfo/spriterobeid.lub`<br>`D:luafiles514/lua files/datainfo/spriterobename.lub`<br>`D:luafiles514/lua files/transparentItem/transparentItem.lub`<br>`D:luafiles514/lua files/stateicon/efstids.lub`<br>`D:luafiles514/lua files/stateicon/stateiconimginfo.lub`<br>`D:luafiles514/lua files/worldviewdata/worldviewdata_table.lub`<br>`D:luafiles514/lua files/datainfo/accname_eng.lub`<br>`D:luafiles514/lua files/datainfo/changedirectorylist.lub`<br>`D:luafiles514/lua files/datainfo/DrawItemOnAura.lub`<br>`D:luafiles514/lua files/datainfo/exceptionitemproducer.lub`<br>`D:luafiles514/lua files/datainfo/jobidentity.lub`<br>`D:luafiles514/lua files/datainfo/kaframovemapservicelist.lub`<br>`D:luafiles514/lua files/datainfo/npclocationradius.lub`<br>`D:luafiles514/lua files/datainfo/shadowtable.lub`<br>`D:luafiles514/lua files/datainfo/tb_cashshop_banner.lub`<br>`D:luafiles514/lua files/datainfo/tb_checkattendance_banner.lub`<br>`D:luafiles514/lua files/datainfo/weapontable.lub`<br>`D:luafiles514/effecttool/`<br>`D:luafiles514/lua files/worldviewdata/worldviewdata_info.lub`<br>`D:luafiles514/skilleffectinfo/`<br>`D:luafiles514/lua files/skillinfoz/jobinheritlist.lub`<br>`D:luafiles514/lua files/skillinfoz/skillid.lub`<br>`D:luafiles514/lua files/stateicon/stateiconinfo.lub`<br>`D:luafiles514/lua files/stateicon/stateiconinfo_f.lub`<br>`D:luafiles514/stylingshop/`<br>`D:luafiles514/lua files/ItemDBNameTbl.lub`<br>`D:luafiles514/CashEmotion/`<br>`D:luafiles514/lua files/EquipmentProperties/EquipmentProperties.lub`<br>`D:luafiles514/lua files/probabilityinfo/simplecashshopscript.lub`<br>`D:luafiles514/lua files/hateffectinfo/`<br>`D:luafiles514/lua files/hateffectinfo/HatEffect_F.lub`<br>`D:luafiles514/lua files/AdventureGuide/`<br>`D:luafiles514/lua files/skillinfoz/skilldelaylist.lub` | accessoryid.lub: DBManager.js:460; accname.lub: DBManager.js:460; spriterobeid.lub: DBManager.js:468; spriterobename.lub: DBManager.js:468; efstids.lub: DBManager.js:7188; stateiconimginfo.lub: DBManager.js:7188; worldviewdata_table.lub: DBManager.js:4982; tb_cashshop_banner.lub: DBManager.js:705; weapontable.lub: DBManager.js:517; jobinheritlist.lub: DBManager.js:6982; skillid.lub: DBManager.js:524; stateiconinfo.lub: DBManager.js:7188; ItemDBNameTbl.lub: DBManager.js:514 |
| 2 Headgears | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/accessoryid.lub`<br>`D:luafiles514/lua files/datainfo/accname.lub`<br>`D:luafiles514/lua files/datainfo/tb_layer_priority.lub`<br>`D:luafiles514/lua files/datainfo/accname_eng.lub` | accessoryid.lub: DBManager.js:460; accname.lub: DBManager.js:460 |
| 3 changedirectorylist.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/changedirectorylist.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 4 DrawItemOnAura.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/DrawItemOnAura.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 5 exceptionitemproducer.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/exceptionitemproducer.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 6 jobidentity.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/jobidentity.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 7 kaframovemapservicelist.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/kaframovemapservicelist.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 8 npclocationradius.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/npclocationradius.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 9 shadowtable.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/shadowtable.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 10 Robes/Costume Garments | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/spriterobeid.lub`<br>`D:luafiles514/lua files/datainfo/spriterobename.lub`<br>`D:luafiles514/lua files/transparentItem/transparentItem.lub` | spriterobeid.lub: DBManager.js:468; spriterobename.lub: DBManager.js:468 |
| 11 tb_cashshop_banner.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/tb_cashshop_banner.lub` | tb_cashshop_banner.lub: DBManager.js:705 |
| 12 tb_checkattendance_banner.lub | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/tb_checkattendance_banner.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 13 Weapons | keine Datumsbedingung; `D:luafiles514/lua files/datainfo/weapontable.lub` | weapontable.lub: DBManager.js:517 |
| 14 World Map | keine Datumsbedingung; `D:luafiles514/lua files/worldviewdata/worldviewdata_info.lub`<br>`D:luafiles514/lua files/worldviewdata/worldviewdata_table.lub` | worldviewdata_table.lub: DBManager.js:4982 |
| 15 effecttool\forcerendereffect.lub | keine Datumsbedingung; `D:luafiles514/lua files/effecttool/forcerendereffect.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 16 Hateffectinfo (2024-04-17 and newer) | geq 20240417; `D:luafiles514/lua files/hateffectinfo/` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 17 skilleffectinfo | keine Datumsbedingung; `D:luafiles514/lua files/skilleffectinfo/actorstate.lub`<br>`D:luafiles514/lua files/skilleffectinfo/effectid.lub`<br>`D:luafiles514/lua files/skilleffectinfo/skilleffectinfolist.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 18 skillinfoz | geq 20250618; `D:luafiles514/lua files/skillinfoz/jobinheritlist.lub`<br>`D:luafiles514/lua files/skillinfoz/skillid.lub`<br>`D:luafiles514/lua files/skillinfoz/skilldelaylist.lub` | jobinheritlist.lub: DBManager.js:6982; skillid.lub: DBManager.js:524 |
| 19 stateicon | keine Datumsbedingung; `D:luafiles514/lua files/stateicon/efstids.lub`<br>`D:luafiles514/lua files/stateicon/stateiconimginfo.lub`<br>`D:luafiles514/lua files/stateicon/stateiconinfo_f.lub` | efstids.lub: DBManager.js:7188; stateiconimginfo.lub: DBManager.js:7188 |
| 20 stylingshop | keine Datumsbedingung; `D:luafiles514/lua files/stylingshop/stylingshopinfo.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 21 ItemDBNameTbl (2021-10-28 and newer) | geq 20211028; `D:luafiles514/lua files/ItemDBNameTbl.lub` | ItemDBNameTbl.lub: DBManager.js:514 |
| 22 EquipmentProperties.lub (2023-08-02 and newer) | geq 20230802; `D:luafiles514/lua files/EquipmentProperties/EquipmentProperties.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 23 CashEmotion (2023-08-02 and newer) | geq 20230802; `D:luafiles514/lua files/CashEmotion/` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 24 probabilityinfo (2024-03-11 and newer) | geq 20240311; `D:luafiles514/lua files/probabilityinfo/simplecashshopscript.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 25 AdventureGuide (2024-05-02 and newer) | geq 20240502; `D:luafiles514/lua files/AdventureGuide/` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |

## System

| Auswahl | Regel; Quelle → Ziel | roBrowser-Fundstelle |
|---|---|---|
| 1 All in One Package | geq 20190605, geq 20221207, geq 20230802, leq 20170614, lss 20241016; Gesamtpaket; `S:ChangeMaterial.lub`<br>`S:CheckAttendance.lub`<br>`S:PetEvolution.lub`<br>`S:PrivateAirplane.lub`<br>`S:Signboard_C.lub`<br>`S:OngoingQuests_C.lub`<br>`S:RecommendedQuests_C.lub`<br>`D:luafiles514/lua files/datainfo/questinfo_f.lub`<br>`S:monster_size_effect 20170614.lub → monster_size_effect.lub`<br>`S:monster_size_effect.lub`<br>`S:Towninfo_C.lub`<br>`S:mapinfo_C.lub`<br>`S:Rune/` | CheckAttendance.lub: DBManager.js:677; PrivateAirplane.lub: DBManager.js:809 |
| 2 ChangeMaterial.lub (2022-12-07 and newer) | geq 20221207; `S:ChangeMaterial.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 3 CheckAttendance.lub | keine Datumsbedingung; `S:CheckAttendance.lub` | CheckAttendance.lub: DBManager.js:677 |
| 4 monster_size_effect.lub | leq 20170614; `S:monster_size_effect 20170614.lub → monster_size_effect.lub`<br>`S:monster_size_effect.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 5 PetEvolution.lub | keine Datumsbedingung; `S:PetEvolution.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 6 PrivateAirplane.lub | keine Datumsbedingung; `S:PrivateAirplane.lub` | PrivateAirplane.lub: DBManager.js:809 |
| 7 Signboard_C.lub | keine Datumsbedingung; `S:Signboard_C.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 8 OngoingQuests/RecommendedQuests_C.lub | keine Datumsbedingung; `S:OngoingQuests_C.lub`<br>`S:RecommendedQuests_C.lub`<br>`D:luafiles514/lua files/datainfo/questinfo_f.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 9 mapInfo_C.lub (2019-06-05 and newer) | geq 20190605; `S:mapinfo_C.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 10 Towninfo_C.lub | keine Datumsbedingung; `S:Towninfo_C.lub` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |
| 11 Rune Folder (2023-08-02 and newer) | geq 20230802, lss 20241016; `S:Rune/` | kein direkter Treffer in DBManager.js; weitere Loader ungeprüft |

## Legacy Maps

| Auswahl | Regel; Quelle → Ziel | roBrowser-Fundstelle |
|---|---|---|
| 1 All in One Package | keine Datumsbedingung; Gesamtpaket; `D:*.gat`<br>`D:*.gnd`<br>`D:*.rsw`<br>`D:texture/<legacy>/map/2009rwc_01.bmp`<br>`D:texture/<legacy>/map/2009rwc_02.bmp`<br>`D:texture/<legacy>/map/2009rwc_03.bmp`<br>`D:texture/<legacy>/map/2009rwc_04.bmp`<br>`D:texture/<legacy>/map/2009rwc_05.bmp`<br>`D:texture/<legacy>/map/2009rwc_06.bmp`<br>`D:texture/<legacy>/map/2009rwc_07.bmp`<br>`D:texture/<legacy>/map/2009rwc_08.bmp`<br>`D:texture/<legacy>/map/2009rwc_f01.bmp`<br>`D:texture/<legacy>/map/poring_c01.bmp`<br>`D:texture/<legacy>/map/poring_c02.bmp`<br>`D:texture/<legacy>/map/payon.bmp` | generischer Kartenpfad siehe oben |
| 2 Airport Maps (Einbroch, Lighthalzen, Yuno) | keine Datumsbedingung; `D:einbroch.gat`<br>`D:einbroch.gnd`<br>`D:einbroch.rsw`<br>`D:lighthalzen.gat`<br>`D:lighthalzen.gnd`<br>`D:lighthalzen.rsw`<br>`D:yuno.gat`<br>`D:yuno.gnd`<br>`D:yuno.rsw` | generischer Kartenpfad siehe oben |
| 3 gefenia01.rsw | keine Datumsbedingung; `D:gefenia01.rsw` | generischer Kartenpfad siehe oben |
| 4 tur_d03_i.rsw | keine Datumsbedingung; `D:tur_d03_i.rsw` | generischer Kartenpfad siehe oben |
| 5 aldeg_cas01.rsw | keine Datumsbedingung; `D:aldeg_cas01.rsw` | generischer Kartenpfad siehe oben |
| 6 gef_fild02.rsw | keine Datumsbedingung; `D:gef_fild02.rsw` | generischer Kartenpfad siehe oben |
| 7 gl_cas01.rsw | keine Datumsbedingung; `D:gl_cas01.rsw` | generischer Kartenpfad siehe oben |
| 8 mjolnir_07.rsw | keine Datumsbedingung; `D:mjolnir_07.rsw` | generischer Kartenpfad siehe oben |
| 9 mjolnir_08.rsw | keine Datumsbedingung; `D:mjolnir_08.rsw` | generischer Kartenpfad siehe oben |
| 10 mjolnir_09.rsw | keine Datumsbedingung; `D:mjolnir_09.rsw` | generischer Kartenpfad siehe oben |
| 11 mjolnir_10.rsw (Menü: 11) | keine Datumsbedingung; `D:mjolnir_10.rsw` | generischer Kartenpfad siehe oben |
| 12 mjolnir_11.rsw (Menü ebenfalls: 11) | keine Datumsbedingung; `D:mjolnir_11.rsw` | generischer Kartenpfad siehe oben |
| 13 moc_fild01.rsw | keine Datumsbedingung; `D:moc_fild01.rsw` | generischer Kartenpfad siehe oben |
| 14 paramk.rsw | keine Datumsbedingung; `D:paramk.rsw` | generischer Kartenpfad siehe oben |
| 15 pay_fild04.rsw | keine Datumsbedingung; `D:pay_fild04.rsw` | generischer Kartenpfad siehe oben |
| 16 prt_fild00.rsw | keine Datumsbedingung; `D:prt_fild00.rsw` | generischer Kartenpfad siehe oben |
| 17 prt_fild01.rsw | keine Datumsbedingung; `D:prt_fild01.rsw` | generischer Kartenpfad siehe oben |
| 18 prt_fild02.rsw | keine Datumsbedingung; `D:prt_fild02.rsw` | generischer Kartenpfad siehe oben |
| 19 prt_fild03.rsw | keine Datumsbedingung; `D:prt_fild03.rsw` | generischer Kartenpfad siehe oben |
| 20 prt_fild04.rsw | keine Datumsbedingung; `D:prt_fild04.rsw` | generischer Kartenpfad siehe oben |
| 21 prt_fild05.rsw | keine Datumsbedingung; `D:prt_fild05.rsw` | generischer Kartenpfad siehe oben |
| 22 prt_fild06.rsw | keine Datumsbedingung; `D:prt_fild06.rsw` | generischer Kartenpfad siehe oben |
| 23 prt_fild07.rsw | keine Datumsbedingung; `D:prt_fild07.rsw` | generischer Kartenpfad siehe oben |
| 24 prt_fild09.rsw | keine Datumsbedingung; `D:prt_fild09.rsw` | generischer Kartenpfad siehe oben |
| 25 prt_fild10.rsw | keine Datumsbedingung; `D:prt_fild10.rsw` | generischer Kartenpfad siehe oben |
| 26 2009rwc_ Maps | keine Datumsbedingung; `D:2009rwc_01.gat`<br>`D:2009rwc_01.gnd`<br>`D:2009rwc_01.rsw`<br>`D:texture/<legacy>/map/2009rwc_01.bmp`<br>`D:2009rwc_02.gat`<br>`D:2009rwc_02.gnd`<br>`D:2009rwc_02.rsw`<br>`D:texture/<legacy>/map/2009rwc_02.bmp`<br>`D:2009rwc_03.gat`<br>`D:2009rwc_03.gnd`<br>`D:2009rwc_03.rsw`<br>`D:texture/<legacy>/map/2009rwc_03.bmp`<br>`D:2009rwc_04.gat`<br>`D:2009rwc_04.gnd`<br>`D:2009rwc_04.rsw`<br>`D:texture/<legacy>/map/2009rwc_04.bmp`<br>`D:2009rwc_05.gat`<br>`D:2009rwc_05.gnd`<br>`D:2009rwc_05.rsw`<br>`D:texture/<legacy>/map/2009rwc_05.bmp`<br>`D:2009rwc_06.gat`<br>`D:2009rwc_06.gnd`<br>`D:2009rwc_06.rsw`<br>`D:texture/<legacy>/map/2009rwc_06.bmp`<br>`D:2009rwc_07.gat`<br>`D:2009rwc_07.gnd`<br>`D:2009rwc_07.rsw`<br>`D:texture/<legacy>/map/2009rwc_07.bmp`<br>`D:2009rwc_08.gat`<br>`D:2009rwc_08.gnd`<br>`D:2009rwc_08.rsw`<br>`D:texture/<legacy>/map/2009rwc_08.bmp`<br>`D:2009rwc_f01.gat`<br>`D:2009rwc_f01.gnd`<br>`D:2009rwc_f01.rsw`<br>`D:texture/<legacy>/map/2009rwc_f01.bmp` | generischer Kartenpfad siehe oben |
| 27 2012rwc_ Maps | keine Datumsbedingung; `D:2012rwc_01.gat`<br>`D:2012rwc_01.gnd`<br>`D:2012rwc_01.rsw`<br>`D:2012rwc_02.gat`<br>`D:2012rwc_02.gnd`<br>`D:2012rwc_02.rsw`<br>`D:2012rwc_03.gat`<br>`D:2012rwc_03.gnd`<br>`D:2012rwc_03.rsw`<br>`D:2012rwc_04.gat`<br>`D:2012rwc_04.gnd`<br>`D:2012rwc_04.rsw`<br>`D:2012rwc_05.gat`<br>`D:2012rwc_05.gnd`<br>`D:2012rwc_05.rsw`<br>`D:2012rwc_06.gat`<br>`D:2012rwc_06.gnd`<br>`D:2012rwc_06.rsw`<br>`D:2012rwc_07.gat`<br>`D:2012rwc_07.gnd`<br>`D:2012rwc_07.rsw`<br>`D:2012rwc_08.gat`<br>`D:2012rwc_08.gnd`<br>`D:2012rwc_08.rsw` | generischer Kartenpfad siehe oben |
| 28 poring_c01 | keine Datumsbedingung; `D:poring_c01.gat`<br>`D:poring_c01.gnd`<br>`D:poring_c01.rsw`<br>`D:texture/<legacy>/map/poring_c01.bmp` | generischer Kartenpfad siehe oben |
| 29 poring_c02 | keine Datumsbedingung; `D:poring_c02.gat`<br>`D:poring_c02.gnd`<br>`D:poring_c02.rsw`<br>`D:texture/<legacy>/map/poring_c02.bmp` | generischer Kartenpfad siehe oben |
| 30 sch_lab | keine Datumsbedingung; `D:sch_lab.gat`<br>`D:sch_lab.gnd`<br>`D:sch_lab.rsw`<br>`D:texture/<legacy>/map/sch_lab.bmp` | generischer Kartenpfad siehe oben |
| 31 airplane | keine Datumsbedingung; `D:airplane.rsw` | generischer Kartenpfad siehe oben |
| 32 payon | keine Datumsbedingung; `D:payon.gat`<br>`D:payon.gnd`<br>`D:payon.rsw`<br>`D:texture/<legacy>/map/payon.bmp` | generischer Kartenpfad siehe oben |
| 33 ra_temple | keine Datumsbedingung; `D:ra_temple.gat`<br>`D:ra_temple.gnd`<br>`D:ra_temple.rsw` | generischer Kartenpfad siehe oben |
| 34 spl_fild01 | keine Datumsbedingung; `D:spl_fild01.rsw` | generischer Kartenpfad siehe oben |
| 35 aldebaran | keine Datumsbedingung; `D:aldebaran.rsw` | generischer Kartenpfad siehe oben |

## Legacy Minimaps

| Auswahl | Regel; Quelle → Ziel | roBrowser-Fundstelle |
|---|---|---|
| 1 All in One Package | keine Datumsbedingung; Gesamtpaket; `D:texture/<legacy>/map/ama_dun01.bmp`<br>`D:texture/<legacy>/map/ayo_dun01.bmp`<br>`D:texture/<legacy>/map/ice_dun04.bmp`<br>`D:texture/<legacy>/map/map2_int.bmp`<br>`D:texture/<legacy>/map/new_zone02.bmp`<br>`D:texture/<legacy>/map/new_zone04.bmp`<br>`D:texture/<legacy>/map/ra_temsky.bmp`<br>`D:texture/<legacy>/map/tha_t07.bmp`<br>`D:texture/<legacy>/map/tha_t08.bmp`<br>`D:texture/<legacy>/map/thana_boss.bmp`<br>`D:texture/<legacy>/map/tur_dun05.bmp`<br>`D:texture/<legacy>/map/tur_dun06.bmp`<br>`D:texture/<legacy>/map/yggdrasil01.bmp`<br>`D:texture/<legacy>/map/yuno_in02.bmp` | individueller Ladepfad ungeprüft |
| 2 ama_dun01 | keine Datumsbedingung; `D:texture/<legacy>/map/ama_dun01.bmp` | individueller Ladepfad ungeprüft |
| 3 ayo_dun01 | keine Datumsbedingung; `D:texture/<legacy>/map/ayo_dun01.bmp` | individueller Ladepfad ungeprüft |
| 4 ice_dun04 | keine Datumsbedingung; `D:texture/<legacy>/map/ice_dun04.bmp` | individueller Ladepfad ungeprüft |
| 5 map2_int | keine Datumsbedingung; `D:texture/<legacy>/map/map2_int.bmp` | individueller Ladepfad ungeprüft |
| 6 new_zone02 | keine Datumsbedingung; `D:texture/<legacy>/map/new_zone02.bmp` | individueller Ladepfad ungeprüft |
| 7 new_zone04 | keine Datumsbedingung; `D:texture/<legacy>/map/new_zone04.bmp` | individueller Ladepfad ungeprüft |
| 8 ra_temsky | keine Datumsbedingung; `D:texture/<legacy>/map/ra_temsky.bmp` | individueller Ladepfad ungeprüft |
| 9 tha_t07 | keine Datumsbedingung; `D:texture/<legacy>/map/tha_t07.bmp` | individueller Ladepfad ungeprüft |
| 10 tha_t08 | keine Datumsbedingung; `D:texture/<legacy>/map/tha_t08.bmp` | individueller Ladepfad ungeprüft |
| 11 thana_boss | keine Datumsbedingung; `D:texture/<legacy>/map/thana_boss.bmp` | individueller Ladepfad ungeprüft |
| 12 tur_dun05 | keine Datumsbedingung; `D:texture/<legacy>/map/tur_dun05.bmp` | individueller Ladepfad ungeprüft |
| 13 tur_dun06 | keine Datumsbedingung; `D:texture/<legacy>/map/tur_dun06.bmp` | individueller Ladepfad ungeprüft |
| 14 yggdrasil01 | keine Datumsbedingung; `D:texture/<legacy>/map/yggdrasil01.bmp` | individueller Ladepfad ungeprüft |
| 15 yuno_in02 | keine Datumsbedingung; `D:texture/<legacy>/map/yuno_in02.bmp` | individueller Ladepfad ungeprüft |

## Bekannte Abweichungen

- Im Lua-Gesamtpaket lassen die Pfade für `effecttool`, `skilleffectinfo`, `stylingshop` und `CashEmotion` `lua files` aus; Einzelzweige verwenden es. `skillinfoz/skillid.lub`, `stateicon/stateiconinfo.lub` (nur Gesamtpaket) und `SystemEN/Signboard_C.lub` fehlen laut Inventar an den referenzierten Additions-Quellpfaden.
- `monster_size_effect`: bis einschließlich 2017-06-14 wird die datierte Quelle auf den normalen Zielnamen kopiert, danach die normale Quelle. Rune wird ab 2023-08-02 kopiert und `set_reward.lub` vor 2024-10-16 anschließend gelöscht. Die datierten Varianten von PrivateAirplane und EquipmentProperties werden nicht ausgewählt.
- Das Karten-Gesamtpaket verwendet Wildcards für GAT/GND/RSW und explizite BMPs; der Einzelzweig fordert insbesondere `sch_lab.bmp` an, das Gesamtpaket nicht. Das Menü nennt zweimal 11; Zweig 12 kopiert `mjolnir_11`. Maßgeblich für Wildcards, Ordnerinhalte und Bedingungen sind die Batch-Anweisungen und der gepinnte Quellbaum.
