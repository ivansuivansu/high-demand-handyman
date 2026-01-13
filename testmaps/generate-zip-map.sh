#!/usr/bin/env bash
set -euo pipefail

MAPBOX_TOKEN="pk.eyJ1IjoiaXZhbnN1IiwiYSI6ImNtazM4ZDNzZTBwdGszZm9lNmdzcXh0dnIifQ.5aINNsXbitNXPiWtqdey-w"
STYLE="mapbox/streets-v12"     # можно light/dark, но streets-v12 норм
SIZE="1000x700"                # итоговая картинка
ZIPS="85012,85014,85016,85018,85020,85024,85028,85032,85083,85250,85251,85253,85254,85255,85258,85259,85260,85266,85268"

# 1) Скачай ZCTA (один раз) и распакуй рядом:
#    tl_2025_us_zcta520.zip -> tl_2025_us_zcta520.shp
#    (год можно другой, главное чтобы был ZCTA)
SHP="tl_2025_us_zcta520.shp"

if [ ! -f "$SHP" ]; then
  echo "Missing $SHP рядом со скриптом. Скачай TIGER/Line ZCTA и распакуй."
  exit 1
fi

# 2) Вырезаем только нужные ZIP’ы
# Поле в TIGER обычно ZCTA5CE20 (для 2020 ZCTA), иногда может быть ZCTA5CE10.
FIELD="ZCTA5CE20"

WHERE="$FIELD IN ('$(echo "$ZIPS" | sed "s/,/','/g")')"

echo "Extracting ZIP polygons..."
ogr2ogr -f GeoJSON zips_raw.geojson "$SHP" -where "$WHERE"

# 3) Упрощаем геометрию, чтобы влезло в URL (очень важно)
# 5% обычно хватает для карты города; можно 3% если хочешь точнее.
echo "Simplifying..."
mapshaper zips_raw.geojson -simplify 5% keep-shapes -o format=geojson zips_simplified.geojson

# 4) Добавляем simplestyle-стили (fill / stroke), которые Static API понимает
# (Mapbox Static поддерживает simplestyle для GeoJSON overlays) :contentReference[oaicite:2]{index=2}
echo "Styling..."
node - <<'NODE'
const fs = require('fs');

const gj = JSON.parse(fs.readFileSync('zips_simplified.geojson','utf8'));
for (const f of gj.features) {
  f.properties = f.properties || {};
  f.properties['fill'] = '#41d17a';
  f.properties['fill-opacity'] = 0.25;
  f.properties['stroke'] = '#1c8f55';
  f.properties['stroke-width'] = 2;
  f.properties['stroke-opacity'] = 0.9;
}
fs.writeFileSync('zips_styled.geojson', JSON.stringify(gj));
NODE

# 5) URL-энкодим GeoJSON и делаем запрос к Static Images API
# Формат: /styles/v1/{style}/static/{overlay}/{camera}/{w}x{h}?access_token=... :contentReference[oaicite:3]{index=3}
echo "Building URL..."
ENCODED=$(python3 - <<'PY'
import urllib.parse, json
data=open('zips_styled.geojson','r',encoding='utf-8').read()
print(urllib.parse.quote(data, safe=''))
PY
)

# camera = auto -> Mapbox сам подберёт центр/зум под overlay
URL="https://api.mapbox.com/styles/v1/${STYLE}/static/geojson(${ENCODED})/auto/${SIZE}?padding=80&access_token=${MAPBOX_TOKEN}"

echo "Fetching PNG..."
curl -g -L "$URL" -o service-area.png

echo "✅ Done: service-area.png"
