#!/bin/bash
# Prüfläufe gegen den echten Quelltext.
#
#   ./Tools/pruefen.sh
#
# Baut die Prüfprogramme aus denselben Dateien, die auch in die App gehen,
# und lässt sie gegen ein eigenes Datenverzeichnis laufen. Die echten Daten
# unter ~/Library/Application Support/Dashboard/ werden dabei nicht berührt:
# JSONStore wertet DASHBOARD_DATA_DIR aus.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Sources/Dashboard"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# Alle Quelldateien außer dem @main-Einstiegspunkt – den bringt jeder
# Prüfling selbst mit.
ALL=()
while IFS= read -r f; do ALL+=("$f"); done < <(find "$SRC" -name '*.swift' ! -name 'DashboardApp.swift' | sort)

echo "› Notizen- und Wochenplan-Logik …"
swiftc -swift-version 5 -parse-as-library -o "$OUT/logik" Tools/Pruefungen/Logik.swift "${ALL[@]}"
DASHBOARD_DATA_DIR="$OUT/logikdaten" TZ=Europe/Berlin "$OUT/logik"

echo
echo "› Alle Ansichten mit leerem Datenverzeichnis …"
swiftc -swift-version 5 -parse-as-library -o "$OUT/ansichten" Tools/Pruefungen/Ansichten.swift "${ALL[@]}"
DASHBOARD_DATA_DIR="$OUT/ansichtendaten" TZ=Europe/Berlin "$OUT/ansichten"

echo
echo "✓ Alle Prüfungen bestanden."
