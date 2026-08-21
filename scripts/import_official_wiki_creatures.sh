#!/usr/bin/env bash
set -euo pipefail

mod_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_dir="$mod_root/Assets/Creatures"
data_file="$mod_root/Data/creature_wiki.json"
work_dir="$(mktemp -d)"
data_temp="$work_dir/creature_wiki.json"
records_temp="$work_dir/records.ndjson"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$asset_dir"

if [[ "${1:-}" == "--check" ]]; then
  jq -e '
    type == "object" and length > 0 and
    all(to_entries[];
      (.key | type == "string" and length > 0) and
      (.value | type == "object") and
      (.value.title | type == "string") and
      (.value.description | type == "string") and
      (.value.image | type == "string") and
      (.value.url | type == "string" and startswith("https://barotraumagame.com/wiki/")))
  ' "$data_file" >/dev/null
  printf 'Validated %s creature records in %s\n' "$(jq 'length' "$data_file")" "$data_file"
  exit 0
fi

creatures=(
  "Ancient|ancient" "Ancient Weapon Fractal Guardian|fractalguardian2"
  "Black Moloch|molochblack" "Bone Thresher|bonethresher" "Charybdis|charybdis"
  "Crawler|crawler" "Crawler Broodmother|crawlerbroodmother" "Crawler Hatchling|crawler_hatchling"
  "Cthulhu|petcthulhu" "Cyborg Worm|cyborgworm" "Defense Bot|defensebot"
  "EMP Fractal Guardian|fractalguardian_emp" "Endworm|endworm" "Fractal Guardian|fractalguardian"
  "Giant Spineling|giantspineling" "Golden Hammerhead|hammerheadgold"
  "Guardian Repair Bot|guardianrepairbot" "Hammerhead|hammerhead" "Hammerhead Matriarch|hammerheadmatriarch"
  "Hammerhead Spawn|hammerheadspawn" "Husk|husk" "Husk Chimera|huskchimera"
  "Husk Exosuit|huskexosuit" "Husk Prowler|huskprowler" "Husked Crawler|crawlerhusk"
  "Huskified Storage Container|huskcontainer" "Jove|jove" "Latcher|latcher"
  "Leucocyte|leucocyte" "Mantis|mantis" "Moloch|moloch" "Moloch Baby|molochbaby"
  "Moping Jack|mopingjack" "Mudraptor|mudraptor" "Mudraptor Hatchling|mudraptor_hatchling"
  "Mudraptor Unarmored|mudraptor_unarmored" "Mudraptor Veteran|mudraptor_veteran"
  "Orange Boy|petraptor" "Peanut|petsmallcrawler" "Petraptor|mudraptor_pet"
  "Portal Guardian|portalguardian" "Psilotoad|psilotoad" "Spineling|spineling"
  "Steam Cannon Fractal Guardian|fractalguardian3" "Swarm Feeder|swarmfeeder"
  "Terminal Cell|terminalcell" "Tiger Thresher|tigerthresher"
  "Tiger Thresher Hatchling|tigerthresher_hatchling" "Viperling|viperling" "Watcher|watcher"
)

: > "$records_temp"
for record in "${creatures[@]}"; do
  title="${record%%|*}"
  identifier="${record#*|}"
  encoded_title="$(printf '%s' "$title" | jq -sRr @uri)"
  json="$work_dir/$identifier.json"
  html="$work_dir/$identifier.html"
  if ! curl -L --fail --silent --show-error \
    "https://barotraumagame.com/baro-wiki/api.php?action=parse&page=$encoded_title&prop=text&format=json" -o "$json"; then
    jq -nc \
      --arg key "$identifier" \
      --arg title "$title" \
      --arg url "https://barotraumagame.com/wiki/${encoded_title//%20/_}" \
      '{key: $key, value: {title: $title, description: "", image: "", url: $url}}' \
      >> "$records_temp"
    continue
  fi
  jq -r '.parse.text."*" // ""' "$json" > "$html"
  description="$(xmllint --html --xpath "string((//*[self::h1 or self::h2 or self::h3][.//*[@id='Description']]/following-sibling::p)[1])" "$html" 2>/dev/null || true)"
  image_url="$(xmllint --html --xpath "string((//table[contains(@class,'infobox')]//img)[1]/@src)" "$html" 2>/dev/null || true)"
  image_path=""
  if [[ -n "$image_url" ]]; then
    image_url="https://barotraumagame.com${image_url}"
    if curl -L --fail --silent --show-error "$image_url" -o "$asset_dir/$identifier.png"; then
      image_path="Assets/Creatures/$identifier.png"
    fi
  fi
  jq -nc \
    --arg key "$identifier" \
    --arg title "$title" \
    --arg description "$description" \
    --arg image "$image_path" \
    --arg url "https://barotraumagame.com/wiki/${encoded_title//%20/_}" \
    '{key: $key, value: {title: $title, description: $description, image: $image, url: $url}}' \
    >> "$records_temp"
done
jq -s 'from_entries' "$records_temp" > "$data_temp"
mv "$data_temp" "$data_file"
