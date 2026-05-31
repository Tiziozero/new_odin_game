@echo off
odin build ./server -collection:project=. -out:server_bin.exe
server_bin.exe
