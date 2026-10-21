#!/bin/bash
csv=${1:?Usage: update-location.sh <csv-file> [row]}
row=${2:-1}

if ! [[ "${row}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Row must be a number from 1: ${row}"
    exit 1
fi

if [ ! -f "$csv" ]; then
    echo "File not found: ${csv}"
    exit 1
fi

# The row-th line that is not a comment or blank, without a Windows line ending
line=$(tr -d '\r' < "${csv}" | grep -v -e '^#' -e '^[[:space:]]*$' | sed -n "${row}p")
if [ -z "${line}" ]; then
    echo "Row ${row} not found"
    exit 1
fi

lat=$(echo "${line}" | cut -d, -f1)
lon=$(echo "${line}" | cut -d, -f2)
desc=$(echo "${line}" | cut -d, -f4-)

echo "Setting location to ${lat},${lon} (${desc})"
xcrun simctl location "SpotGolf Phone" set "${lat},${lon}"
xcrun simctl location "SpotGolf Watch" set "${lat},${lon}"
