# Dashboard

Native macOS-App (SwiftUI + Swift Charts) mit Kalender, Aufgaben,
Produktivitätstracker und Statistik. Bewusst als erweiterbares Grundgerüst
angelegt: ein Design-Token-System, ein Datenlayer und fünf Module, die
unabhängig voneinander wachsen können.

## Bauen und starten

```bash
./build.sh          # kompiliert, baut Dashboard.app, signiert ad-hoc
open build/Dashboard.app
```

`swift build` allein reicht zum Kompilieren, aber nicht zum Ausführen –
für Kalenderzugriff und Icon braucht es das App-Bundle aus `build.sh`.

## Aufbau

```
Sources/Dashboard/
├── App/           Einstiegspunkt, Navigation, gemeinsamer Zustand
├── Design/        Theme (Farben, Abstände, Typografie), Formatierer
├── Components/    Card, MetricTile, SegmentedBar, EmptyState
├── Models/        TaskItem, ActivitySegment, ProductivityCategory
├── Services/      Persistenz, Tracker, Kategorien, Kalender, Statistik
└── Features/      Je eine Datei pro Bereich der Seitenleiste
```

### Automatischer Start

*Einstellungen → Tracking → Bei der Anmeldung starten* registriert die App
über `SMAppService` als Anmeldeobjekt. Ohne das zeichnet der Tracker nur auf,
solange jemand die App offen hat — und lückenhafte Tage machen jeden
Tagesvergleich wertlos.

Ein Anmeldeobjekt zeigt auf einen **festen Pfad**. Die App gehört deshalb
nach `/Applications`; liegt sie woanders, weist die Einstellung darauf hin.
Verlangt macOS eine Bestätigung, führt ein Knopf direkt zu den
Anmeldeobjekten in den Systemeinstellungen.

### Datenhaltung

Alles liegt als JSON in `~/Library/Application Support/Dashboard/` — oder in
`$DASHBOARD_DATA_DIR/Dashboard/`, wenn diese Variable gesetzt ist.
**Testläufe sollten sie setzen.** Eine Umleitung von `HOME` genügt nicht:
`FileManager` löst „Application Support" über den Benutzerdatensatz auf, und
Probeläufe schreiben sonst in die echten Daten — parallel zur laufenden App.

| Datei | Inhalt |
|---|---|
| `tasks.json` | Aufgaben |
| `activity.json` | Aktivitätssegmente (120 Tage Historie) |
| `category-rules.json` | benutzerdefinierte Einstufungen |

`JSONStore` kapselt das Lesen und Schreiben – ein späterer Umstieg auf
SwiftData betrifft nur die Services, nicht die Views.

### Produktivitätstracker

`ActivityTracker` fragt alle 2 Sekunden die Vordergrund-App über
`NSWorkspace` ab und schneidet daraus zusammenhängende Segmente. Ohne
Maus- oder Tastatureingabe (Standard: 2 Minuten) pausiert die Erfassung,
damit Leerlauf nicht als Arbeitszeit zählt.

Erfasst werden ausschließlich App-Name und Bundle-ID – keine Fenstertitel,
keine Inhalte. Dafür sind keine Sonderberechtigungen nötig.

### Einstufung: automatisch oder manuell

Jede Anwendung steht auf **Automatisch** (Standard). `CategoryRules` wertet
dann in dieser Reihenfolge aus:

1. **Manuelle Festlegung** des Benutzers – überschreibt alles Weitere
2. **Mitgelieferte Liste** bekannter Anwendungen (~35 Einträge)
3. **`LSApplicationCategoryType`** aus dem App-Bundle – die Kategorie, die
   die App selbst meldet (`…developer-tools` → produktiv, `…games` →
   unproduktiv, `…utilities` → neutral usw.), abschaltbar
4. **Voreinstellung** für alles Unbekannte (standardmäßig neutral)

Woher eine Einstufung stammt, steht im Tooltip jedes Abzeichens und als
Untertitel in *Einstellungen → Einstufung*. Ein Abzeichen mit
Zauberstab-Symbol bedeutet „automatisch hergeleitet“, ohne Symbol „von dir
festgelegt“. Umstellen geht überall dort, wo eine Einstufung sichtbar ist;
gesammelt mit Suche und Filter in den Einstellungen.

### Kalender

`CalendarService` liest **und schreibt** über EventKit die Systemkalender.
Die Berechtigung wird beim ersten Öffnen des Kalenderbereichs angefragt.

Termine anlegen: Schaltfläche *+ Termin*, ⌘N, Doppelklick auf einen Tag im
Monatsraster, Rechtsklick auf einen Tag, oder das Plus in der Übersicht.
Klick auf einen bestehenden Termin öffnet ihn zum Bearbeiten oder Löschen.
Geschrieben wird in den gewählten Systemkalender – die Termine erscheinen
also auch in Kalender.app. Wiederkehrende Termine werden mit
`span: .thisEvent` bearbeitet, also nur der einzelne Eintrag.

### Assistenz

Der Bereich *Assistenz* beantwortet Fragen zu den Dashboard-Daten. Das
Sprachmodell ist das **systemeigene Modell von macOS 26** (`FoundationModels`)
— es läuft vollständig auf dem Gerät. Kein API-Schlüssel, kein Konto, und
es verlassen keine Daten den Mac. Voraussetzung ist eingeschaltetes Apple
Intelligence; auf älteren Systemen zeigt der Bereich einen Hinweis statt
einer Fehlermeldung.

Der Aufbau in drei Schichten:

```
DashboardQuery      rechnet – Summen, Durchschnitte, Vergleiche, Tagesverläufe
      ↑
AssistantTools      sechs Werkzeuge, die das Modell aufrufen kann
      ↑
OnDeviceBackend     Sitzung, Systemanweisung, Streaming
```

Entscheidend ist die Arbeitsteilung: **das Modell rechnet nicht.** Sämtliche
Zahlen kommen fertig ausgewertet aus `DashboardQuery`, das Modell wählt nur
das Werkzeug und formuliert die Antwort. Deshalb stimmen die Zahlen auch bei
einem kleinen On-Device-Modell.

Zwölf Werkzeuge — lesend, schreibend und zeichnend:

| lesend | schreibend |
|---|---|
| `nutzung_anzeigen` | `aufgabe_anlegen` |
| `apps_vergleichen` | `aufgabe_abhaken` |
| `produktivitaet_anzeigen` | `aufgabe_loeschen` |
| `termine_anzeigen` | `termin_anlegen` |
| `aufgaben_anzeigen` | `termin_loeschen` |
| `diagramm_zeichnen` | `app_einstufen` |

App- und Aufgabennamen werden unscharf aufgelöst — „chrome" trifft „Google
Chrome". Passt mehr als ein Eintrag, wird zurückgefragt statt geraten.

### Diagramme

`diagramm_zeichnen` erzeugt echte Grafiken, keine Texttabellen — gezeichnet
mit Swift Charts direkt in der Antwort.

Das Modell **stellt das Diagramm selbst zusammen** — Form, Inhalt, Zeitraum,
Anwendungen und Anzahl sind freie Parameter von `diagramm_zeichnen`. Es gibt
keinen Katalog fertiger Szenarien; jede Kombination ist erlaubt, auch solche,
an die beim Bauen niemand gedacht hat.

**Form und Inhalt sind dabei getrennt.** Das war anfangs vermischt:
„Kuchendiagramm" galt als Wunsch nach der Produktivitätsverteilung, obwohl es
nur die *Form* benennt. `ChartRequest` liest beide Achsen einzeln:

| | |
|---|---|
| **Inhalt** | Anwendungen · Einstufung · Score · Aufgaben · Termine |
| **Form** | Kuchen/Ring · Balken · Säulen · Linie · Tabelle |
| **Zeitraum** | heute · Woche · Monat · „letzte 14 Tage" |
| **Anzahl** | „die beiden" · „drei" · „Top 5" |

Jede Kombination ist gültig: ein Kuchendiagramm der zwei meistgenutzten Apps
nach reiner Nutzungszeit ebenso wie eines der Produktivitätsverteilung.

Die Rangfolge ist überall dieselbe: **was die Frage ausdrücklich nennt, gilt
— alles Übrige komponiert das Modell.** So bleibt Spielraum für Unerwartetes,
ohne dass eine klare Ansage überstimmt werden kann. Unverrückbar ist nur
zweierlei: Zahlen kommen aus den Aufzeichnungen, und App-Namen werden gegen
die Daten geprüft, bevor sie irgendwo landen.

Anschlussfragen funktionieren auch nach dem Leeren des Verlaufs: die
Systemanweisung trägt eine Kurzbeschreibung des zuletzt gezeigten Diagramms,
und eine Frage wie „zeig nur die drei größten davon" gilt als Diagrammanfrage,
solange gerade eines zu sehen war.

**Ohne erkennbaren Inhalt wird nicht gezeichnet.** Fragt jemand nach einem
„Netzdiagramm der Schlafqualität", entstand früher ein beliebiges
Anwendungsdiagramm — die Bitte um eine *Tabelle mit Aufgaben* endete so als
Balkendiagramm der App-Nutzung. `ChartRequest.hasKnownSubject` blockt das:
die Antwort sagt dann, was das Dashboard stattdessen zeigen kann.

**Der Rückfall überlebt einen Modellfehler.** Bricht der Aufruf ab
(`GenerationError`), lief die Rückfallebene früher gar nicht erst an, und
eine völlig eindeutige Bitte blieb unbeantwortet. Der Fehler wird jetzt
gemerkt, nicht geworfen; ist die Frage eindeutig, zeichnet die App trotzdem.

Kleinigkeiten, die alle aus Tests stammen: Zahlwörter zählen nur mit Bezug
(„die letzten 7 Tage" meint keine sieben Anwendungen), Systemprozesse wie
`loginwindow` werden gar nicht erst aufgezeichnet, „Chrome" trifft
„Google Chrome" über einzelne Namensbestandteile, alles nach „statt" wird
abgeschnitten („als Balken statt Linie"), ein einzelnes Kuchenstück bekommt
„Übrige Anwendungen" daneben, und jenseits von acht Segmenten wandert der
Rest in ein Sammelsegment.

### Warum die Änderungen belegt werden

Ein Sprachmodell behauptet bereitwillig, etwas eingetragen zu haben, ohne es
zu tun. Dagegen gibt es drei Stufen:

1. **Beleg statt Behauptung.** Jede Änderung läuft über `DashboardCommands`
   und landet im `ActionLog`. Unter der Antwort steht, was *tatsächlich*
   geschah — mit **Rückgängig**. Bleibt die Zeile leer, ist nichts passiert,
   egal was die Antwort sagt.
2. **Selbstprüfung.** Behauptet die Antwort eine Änderung, ohne dass eine
   protokolliert wurde, stellt `AssistantEngine` die Anfrage automatisch ein
   zweites Mal — mit geleertem Verlauf, damit kein vorheriger Satz zum
   Abschreiben einlädt.
3. **Warnung.** Scheitert auch das, wird die Antwort ausdrücklich als
   unbelegt markiert.

Für Diagramme gilt dasselbe Muster, nur mit einem stärkeren Abschluss: wird
eines erbeten und keines gezeichnet, folgt ein zweiter Anlauf — und danach
zeichnet die App es **selbst** aus den Aufzeichnungen (`DashboardCharts.isRequested`
und `inferredDays` lesen Art und Zeitraum direkt aus der Frage). Ein Diagramm
darf nicht vom Zufall abhängen.

### Keine erfundenen Anwendungen

Nach einem Diagramm der „beiden meistgenutzten" Apps setzte das Modell
Namen ein, die nie liefen. Drei Sperren dagegen:

- Fragt der Benutzer nach „den meistgenutzten", werden die vom Modell
  gelieferten Namen **verworfen** — die Rangliste entscheidet
  (`AssistantContext.wantsMostUsed`).
- Ein namentlich genannter, aber nie aufgezeichneter Name wird **nie**
  stillschweigend ersetzt; die Antwort sagt, dass dazu nichts vorliegt.
- Nennt der Antworttext keine der abgebildeten Reihen, steht unter dem
  Diagramm eine Richtigstellung.

### Aus Tests gelernt

- **Werkzeugnamen brauchen eindeutige Verben.** `aufgaben` und
  `aufgabe_anlegen` lagen zu dicht beieinander; das Modell griff zum
  Lesewerkzeug, wenn es anlegen sollte. Jetzt heißt jedes Werkzeug
  `…_anzeigen`, `…_anlegen`, `…_abhaken` oder `…_loeschen`.
- **Keine `Bool`-Argumente.** Daran ist die Auswertung der Modellausgabe
  wiederholt gescheitert („Failed to deserialize a Generable type").
  Ganztägigkeit ergibt sich jetzt aus einer leeren Uhrzeit.
- **Werkzeugausgaben sind der Antwortentwurf.** Enthalten sie Meta-Sätze
  („wird dem Benutzer angezeigt"), landen die wörtlich in der Antwort. Sie
  geben deshalb genau den Satz zurück, den der Benutzer lesen soll.
- **Das Kontextfenster ist klein.** Lange Anweisungen und viele Werkzeuge
  füllen es; nach einigen Zügen lief es über. `OnDeviceBackend` verwirft
  darum die Sitzung und stellt die Frage neu, statt abzuweisen.

Ein neues Werkzeug ergänzen: Methode in `DashboardQuery` (lesend) oder
`DashboardCommands` (schreibend) schreiben, `Tool`
in `AssistantTools.swift` daraufsetzen, in `OnDeviceBackend.activeSession()`
in die Liste eintragen. `AssistantBackend` ist bewusst ein Protokoll — ein
anderes Modell (etwa über die Claude API) ließe sich daneben hängen, ohne
die Oberfläche anzufassen.

Beim Formulieren der Werkzeugausgaben ist zweierlei wichtig, beides aus
Tests gelernt: Wochentage **ausgeschrieben** (aus „Mi." macht ein kleines
Modell schnell „Dienstag"), und Score-Punkte klar von Prozentangaben
trennen, sonst werden sie vermischt.

## Erweitern

**Neuen Bereich hinzufügen:** einen Fall zu `DashboardSection`
(`App/AppState.swift`) ergänzen – Titel und SF-Symbol dort, View in
`RootView.detail` verdrahten. Seitenleiste, Tastaturkürzel und Menü
ergeben sich automatisch.

**Neue Kennzahl:** in `Services/Statistics.swift` rechnen, in der View als
`MetricTile` oder `Chart` darstellen. Die Statistik-Ebene kennt keine UI
und ist damit isoliert testbar.

**Aussehen ändern:** ausschließlich `Design/Theme.swift` anfassen. Alle
Farben, Abstände, Radien und Schriftgrößen kommen von dort.

## Erscheinungsbild

Umschaltbar zwischen *System*, *Hell* und *Dunkel* — in den Einstellungen,
über das Menü *Darstellung*, mit **⇧⌘D** oder über das Symbol unten in der
Seitenleiste. „System" folgt macOS und wechselt mit ihm.

Farben, die nicht schon vom System kommen, sind über
`Theme.Palette.adaptive(light:dark:)` definiert und lösen sich je nach
Erscheinungsbild auf. `AppearanceSettings` setzt zusätzlich
`NSApp.appearance`, damit auch Menüs und das Einstellungsfenster mitziehen —
`preferredColorScheme` allein erfasst nur den Fensterinhalt.

> **`AppearanceSettings` gehört in `DashboardApp`, nicht in `AppState`.**
> Änderungen an einem verschachtelten `ObservableObject` melden sich beim
> äußeren nicht an. Lag es in `AppState`, wurde die Szene beim Umschalten
> nicht neu ausgewertet: `preferredColorScheme` behielt seinen alten Wert und
> nagelte das Fenster darauf fest — stärker als `NSApp.appearance`. Umschalten
> wirkte dann erst beim nächsten Bereichswechsel, und im Bereich *Assistenz*,
> wo man den Bereich ja nicht wechselt, überhaupt nicht. Wer hier etwas
> umbaut, sollte das Erscheinungsbild dort beobachten, wo
> `preferredColorScheme` gesetzt wird.

## Hover

`Components/Hover.swift` hält zwei Bausteine bereit: `hoverSurface()` für
Karten (Fläche hellt auf, Kante wird kräftiger, leichtes Anheben) und
`hoverRow()` für Zeilen innerhalb einer Karte. Beide bewusst zurückhaltend.

**Diagramme** wachsen unter dem Zeiger um 35 %, der Abschnitt darunter wird
hervorgehoben (der Ringabschnitt tritt heraus, andere treten zurück), und
neben der Maus steht, was dort zu sehen ist — etwa „Google Chrome · 26 % ·
24 Minuten". Der Ring lässt sich nicht über den Chart-Proxy abfragen; dort
wird der Abschnitt aus dem Winkel zum Mittelpunkt bestimmt. Die Kurzinfo
liegt in `ChartTooltip` und wird von den Diagrammen der Assistenz wie denen
der Statistikseite geteilt.

## UI prüfen ohne Bildschirmaufnahme

Diese Sitzung hatte keine Berechtigung für Screenshots. `ImageRenderer`
ersetzt sie: ein kleines Programm baut die Ansichten mit Testdaten, rendert
sie in beiden Erscheinungsbildern nach PNG, und die lassen sich ansehen.
So wurden abgeschnittene Legendentexte und eine schief ausgerichtete
Tabellenspalte gefunden. Für Verhalten statt Aussehen leistet ein
`NSHostingView` in einem unsichtbaren Fenster dasselbe: Erscheinungsbild
umschalten, Lauf­schleife pumpen, Bildpunkt auslesen — damit wurde der
Umschaltfehler oben erst reproduziert und dann die Behebung belegt. Grenzen: `ScrollView` rendert dabei leer (deshalb
Bausteine statt ganzer Seiten), und Menüs und Buttons erscheinen als gelbe
Platzhalter.

## Naheliegende nächste Schritte

- Wochen- und Tagesansicht im Kalender (aktuell Monatsraster + Tagesliste)
- Menüleisten-Extra mit Live-Score
- Fokus-Timer (Pomodoro), der Aufgaben mit erfasster Zeit verknüpft
- Tages- und Wochenziele mit Benachrichtigung
- Export der Statistik als CSV
- Aufgaben mit Kalenderterminen verknüpfen
