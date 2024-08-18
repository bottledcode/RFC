#!/bin/sh

docker run -v "$(pwd)":/data --pull always --user "$(id -u)":"$(id -g)" pandoc/latex -t dokuwiki -f gfm "$1" -o "$2"
# remove all <HTML> and </HTML> tags
sed -i 's/<HTML>//g' "$2"
sed -i 's/<\/HTML>//g' "$2"
