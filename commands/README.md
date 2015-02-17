# Lit CLI Commands

 - `lit help` - Show usage information

## Local configuration

 - `lit auth username` - Verify local private key and set username in config.
 - `lit up [upstream]` - Go online.  Uses default upstream or specified url
 - `lit down` - Go offline (disable upstream)
 - `lit config` - Print configuration

## Package Management

 - `lit add path*` - Import, tag, and sign packages from disk to the local db.
 - `lit publish path*` - Add and publish packages to upstream.
 - `lit install` - Install deps of package in cwd.
 - `lit install names*` - Install dependencies

## Execution and Packaging

 - `lit run path/to/script.lua` - Run a script with injected require
 - `lit make appdir` - Build appdir into a single executable

## Server

 - `lit serve` - Start a lit package server (upstream or proxy)

## Upstream Organization Management

 - `lit claim orgname` - Send claim request to upstream
 - `lit share orgname username` - Send share request to upstream
 - `lit unclaim orgname` - Send unclaim request to upstream
