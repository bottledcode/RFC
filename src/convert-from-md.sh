#!/bin/sh

docker run -v "$(pwd)":/data --user "$(id -u)":"$(id -g)" pandoc/latex -t dokuwiki -f gfm "$1" -o "$2"
