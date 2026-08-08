#!/usr/bin/env bash
set -euo pipefail

mod_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_dir="$mod_root/Assets/Creatures"
data_file="$mod_root/Lua/Client/wiki_data.lua"
work_dir="$(mktemp -d)"
data_temp="$work_dir/wiki_data.lua"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$asset_dir"

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

printf 'return {\n' > "$data_temp"
for record in "${creatures[@]}"; do
  title="${record%%|*}"
  identifier="${record#*|}"
  encoded_title="$(printf '%s' "$title" | jq -sRr @uri)"
  json="$work_dir/$identifier.json"
  html="$work_dir/$identifier.html"
  if ! curl -L --fail --silent --show-error \
    "https://barotraumagame.com/baro-wiki/api.php?action=parse&page=$encoded_title&prop=text&format=json" -o "$json"; then
    printf '  ["%s"] = { title = [=[%s]=], description = [=[]=], image = [=[]=], url = [=[https://barotraumagame.com/wiki/%s]=] },\n' \
      "$identifier" "$title" "${encoded_title//%20/_}" >> "$data_temp"
    continue
  fi
  jq -r '.parse.text."*" // ""' "$json" > "$html"
  description="$(xmllint --html --xpath "string((//*[self::h1 or self::h2 or self::h3][.//*[@id='Description']]/following-sibling::p)[1])" "$html" 2>/dev/null || true)"
  image_url="$(xmllint --html --xpath "string((//table[contains(@class,'infobox')]//img)[1]/@src)" "$html" 2>/dev/null || true)"
  image_path=""
  if [[ -n "$image_url" ]]; then
    image_url="https://barotraumagame.com${image_url}"
    if curl -L --fail --silent --show-error "$image_url" -o "$asset_dir/$identifier.png"; then
      image_path="LocalMods/Europa Encyclopedia/Assets/Creatures/$identifier.png"
    fi
  fi
  description="${description//]=]/] = ]}"
  printf '  ["%s"] = { title = [=[%s]=], description = [=[%s]=], image = [=[%s]=], url = [=[https://barotraumagame.com/wiki/%s]=] },\n' \
    "$identifier" "$title" "$description" "$image_path" "${encoded_title//%20/_}" >> "$data_temp"
done
printf '}\n' >> "$data_temp"
mv "$data_temp" "$data_file"
