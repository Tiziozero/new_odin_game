@echo off
odin build ./client -collection:project=. -out:client_bin.exe
client_bin.exe
