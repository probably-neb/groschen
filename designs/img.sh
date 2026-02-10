#!/usr/bin/env bash

img="$1"
b64=$(base64 < "$img")           # macOS: no -w / -b flags
printf '\033_Ga=T,f=100;%s\033\\' "$b64"
