#!/usr/bin/env bash
set -e -x
odin build ./client -collection:project=. -out:client_bin -debug
./client_bin


