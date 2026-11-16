#!/bin/bash
# Baut Dashboard.app.
#
#   ./build.sh                Entwicklungsbau nach ./build/ (nur diese CPU – schnell)
#   ./build.sh --universal    zusätzlich für Intel-Macs (arm64 + x86_64)
#   ./build.sh --install      baut und installiert nach /Applications
#   ./build.sh --dist         universal + ZIP zum Verschicken
#
# Hinweis zur Signatur: ohne Apple-Entwicklerzertifikat kann nur ad-hoc
# signiert werden. Das genügt auf diesem Mac, aber nicht für den Versand –
# siehe VERTEILEN.md.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Dashboard.app"
UNIVERSAL=0
INSTALL=0
DIST=0

for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    --dist)      DIST=1; UNIVERSAL=1 ;;
    debug)       CONFIG=debug ;;
    *) echo "Unbekannte Option: $arg" >&2; exit 1 ;;
  esac
done
CONFIG="${CONFIG:-release}"

ARCHFLAGS=()
if [ "$UNIVERSAL" = 1 ]; then
  ARCHFLAGS=(--arch arm64 --arch x86_64)
  echo "› Kompiliere ($CONFIG, universal: Apple Silicon + Intel) …"
else
  echo "› Kompiliere ($CONFIG) …"
fi

swift build -c "$CONFIG" ${ARCHFLAGS[@]+"${ARCHFLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHFLAGS[@]+"${ARCHFLAGS[@]}"} --show-bin-path)/Dashboard"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "› Erzeuge App-Icon …"
  swift Tools/make-icon.swift
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

echo "› Baue Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dashboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Mit Developer-ID signieren, falls eine im Schlüsselbund liegt – sonst ad-hoc.
#
# Die gehärtete Laufzeitumgebung wird nur zusammen mit einer Developer-ID
# gesetzt. Sie ist Voraussetzung für die Beglaubigung durch Apple, sperrt aber
# gleichzeitig den Zugriff auf Kalender und andere geschützte Daten, solange er
# nicht über Entitlements angemeldet ist – und Entitlements sind an eine echte
# Signatur gebunden. Bei einer ad-hoc-Signatur brächte sie also nichts und
# kostete den Kalenderzugriff.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [ -n "$IDENTITY" ]; then
  echo "› Signiere mit „$IDENTITY“ (gehärtet, beglaubigungsfähig) …"
  codesign --force --options runtime --timestamp \
           --entitlements Resources/Dashboard.entitlements \
           --sign "$IDENTITY" --identifier com.karlkohl.dashboard "$APP"
else
  echo "› Signiere (ad-hoc – kein Entwicklerzertifikat gefunden) …"
  codesign --force --sign - --identifier com.karlkohl.dashboard "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ Fertig: $APP"
lipo -archs "$APP/Contents/MacOS/Dashboard" | sed 's/^/  Architekturen: /'

if [ "$DIST" = 1 ]; then
  echo "› Packe zum Verschicken …"
  rm -f build/Dashboard.zip
  # ditto statt zip: erhält Bundle-Struktur und Signatur unversehrt.
  ditto -c -k --keepParent "$APP" build/Dashboard.zip
  echo "✓ Fertig: build/Dashboard.zip ($(du -h build/Dashboard.zip | cut -f1))"
  echo "  Empfänger brauchen die Hinweise aus VERTEILEN.md."
fi

if [ "$INSTALL" = 1 ]; then
  TARGET="/Applications/Dashboard.app"
  if pgrep -f "$TARGET/Contents/MacOS/Dashboard" >/dev/null 2>&1; then
    echo "› Beende die laufende Version …"
    osascript -e 'tell application "Dashboard" to quit' 2>/dev/null || true
    sleep 2
  fi
  echo "› Installiere nach $TARGET …"
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  echo "✓ Installiert: $TARGET"
fi
