#!/bin/bash
csv=${1:?Usage: update-location.sh <csv-file> [row]}
row=${2:-1}

if [ ! -f "$csv" ]; then
    echo "File not found: ${csv}"
    exit 1
fi

line=$(sed -n "${row}p" "${csv}")
if [ -z "${line}" ]; then
    echo "Row ${row} not found"
    exit 1
fi

current_row=0
while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
  current_row=$((current_row + 1))
  [ "${current_row}" -gt "${row}" ] && break

  lat=$(echo "${line}" | cut -d, -f1)
  lon=$(echo "${line}" | cut -d, -f2)
  desc=$(echo "${line}" | cut -d, -f4-)

  echo "Setting location to ${lat},${lon} (${desc})"
  xcrun simctl location "iPhone 17 Pro" set "${lat},${lon}"
  xcrun simctl location "Apple Watch Series 9 (45mm)" set "${lat},${lon}"
done < "$csv"
