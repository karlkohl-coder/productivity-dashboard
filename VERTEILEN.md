# Dashboard weitergeben

## Kurzfassung

`./build.sh --dist` erzeugt `build/Dashboard.zip` (2,5 MB, läuft auf Apple
Silicon **und** Intel). Verschicken lässt sich die Datei sofort – aber beim
Empfänger **startet sie nicht**, solange die Download-Markierung darauf liegt,
und macOS bietet dafür keinen Knopf an. Es braucht entweder einen
Terminal-Befehl (A1) oder die Übergabe per USB-Stick (A2). Ein Doppelklick
genügt erst, wenn die App von Apple beglaubigt ist; dafür braucht es ein
kostenpflichtiges Entwicklerkonto (Weg B).

## Warum blockiert macOS?

Geprüft am fertigen Paket:

```
codesign --verify --strict   → valid on disk, satisfies its Designated Requirement
spctl -a -t exec             → rejected
```

Die Signatur ist also in Ordnung und übersteht das Packen unbeschädigt. Sie ist
aber *ad hoc* – ohne Apple-Entwicklerzertifikat und ohne Beglaubigung
(Notarisierung). Gatekeeper lässt auf fremden Macs nur beglaubigte Programme
ohne Rückfrage durch. Auf deinem eigenen Mac fällt das nicht auf, weil die App
dort nie durch einen Download gelaufen ist.

## Weg A – ohne Entwicklerkonto (kostenlos)

**Wichtig:** Der oft genannte Weg über *Systemeinstellungen → Datenschutz &
Sicherheit → „Dennoch öffnen"* funktioniert hier **nicht**. Diesen Knopf zeigt
macOS nur bei Apps mit echtem Entwicklerzertifikat, die lediglich nicht
beglaubigt sind. Eine ad-hoc signierte App wird hart abgewiesen – ohne Dialog,
ohne Umgehungsmöglichkeit. Nachgemessen:

```
ohne Quarantäne     → startet
mit Quarantäne      → startet nicht, keine Meldung, kein „Dennoch öffnen"
Quarantäne entfernt → startet
```

Die Sperre hängt allein an der Markierung `com.apple.quarantine`, die macOS
jeder heruntergeladenen oder per AirDrop empfangenen Datei anheftet.

### A1 – Ein Befehl im Terminal (zuverlässig)

Dein Freund entpackt das ZIP, zieht **Dashboard.app** nach **Programme** und
führt einmalig aus (Terminal über Spotlight mit ⌘Leertaste, „Terminal"):

```bash
xattr -dr com.apple.quarantine /Applications/Dashboard.app
```

Danach startet die App per Doppelklick und dauerhaft normal. Der Befehl
entfernt nur die Download-Markierung; er ändert nichts am System und nichts an
anderen Programmen.

### A2 – Ohne Terminal: per USB-Stick übertragen

Die Markierung setzt das *empfangende* Programm – Browser, Mail, AirDrop. Beim
Kopieren von einem USB-Stick passiert das nicht. Also: **Dashboard.app** (nicht
das ZIP) auf einen Stick ziehen, am anderen Mac vom Stick direkt nach
**Programme** kopieren. Dann startet sie ohne jeden Zusatzschritt.

Das ist der bequemste Weg, wenn ihr euch ohnehin seht.

## Weg B – mit Entwicklerkonto (99 €/Jahr, Doppelklick genügt)

1. Apple Developer Program beitreten, im Entwicklerportal ein Zertifikat vom
   Typ **Developer ID Application** erzeugen und in den Schlüsselbund laden.
   `build.sh` findet es dann von selbst und signiert damit statt ad hoc.
2. Einmalig die Zugangsdaten für die Beglaubigung hinterlegen:

```bash
xcrun notarytool store-credentials "dashboard-notary" \
  --apple-id "DEINE@APPLE.ID" --team-id "DEINE-TEAM-ID" \
  --password "app-spezifisches-passwort"
```

   Das app-spezifische Passwort kommt von appleid.apple.com, nicht dein
   normales Apple-Passwort.

3. Bauen, beglaubigen, das Ergebnis ans Paket heften:

```bash
./build.sh --dist
xcrun notarytool submit build/Dashboard.zip \
  --keychain-profile "dashboard-notary" --wait
xcrun stapler staple build/Dashboard.app
ditto -c -k --keepParent build/Dashboard.app build/Dashboard.zip
```

   Der Durchlauf bei Apple dauert meist wenige Minuten. Danach meldet
   `spctl -a -t exec build/Dashboard.app` **accepted**, und ein Doppelklick
   reicht überall.

## Was der Empfänger braucht

| | |
|---|---|
| Betriebssystem | macOS 14 (Sonoma) oder neuer |
| Prozessor | Apple Silicon oder Intel – das Paket enthält beides |
| Kalender | Zugriff wird beim ersten Öffnen erfragt, rein lesend und schreibend für selbst angelegte Termine |
| Assistenz (KI) | nur macOS 26 mit eingeschaltetem Apple Intelligence; sonst bleibt der Bereich mit einem Hinweis leer, der Rest funktioniert normal |

Alles läuft auf dem Gerät. Es werden keine Daten verschickt, es gibt kein
Konto und keinen Schlüssel. Aufgezeichnet werden nur App-Name und Bundle-ID –
keine Fenstertitel, keine Inhalte.

## Ablage der Daten

`~/Library/Application Support/Dashboard/` – unabhängig davon, wo die App
liegt. Ein Umzug der App lässt die Daten unberührt. Einstellungen hängen an der
Bundle-ID und überstehen den Umzug ebenfalls.
