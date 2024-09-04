#!/bin/sh

docker run --rm -v "$(pwd)":/data --user "$(id -u)":"$(id -g)" pandoc/latex -t dokuwiki -f gfm "$1" -o "$2"
# remove all <HTML> and </HTML> tags
sed -i 's/<HTML>//g' "$2"
sed -i 's/<\/HTML>//g' "$2"

# remove all html comments
sed -i 's/<!--.*-->//g' "$2"
