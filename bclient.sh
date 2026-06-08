#!/usr/bin/env bash
set -e
odin build ./client -collection:project=. -out:client_bin
./client_bin


