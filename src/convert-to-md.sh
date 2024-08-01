#!/bin/sh

docker run -v "$(pwd)":/data --user "$(id -u)":"$(id -g)" pandoc/latex -f dokuwiki -t gfm "$1" -o "$2"
