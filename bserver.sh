#!/usr/bin/env bash
set -e -x
odin build ./server -collection:project=. -out:server_bin

./server_bin

