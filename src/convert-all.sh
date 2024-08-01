#!/bin/bash

# Ensure target directory exists
mkdir -p published

for file in drafts/*.md; do
  echo "converting $file"
  output_file="published/$(basename "${file%.md}.ptxt")"
  src/convert-from-md.sh "$file" "$output_file"
done
