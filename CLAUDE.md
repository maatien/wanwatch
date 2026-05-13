# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`wanwatch` is a single POSIX `sh` script (`wanwatch.sh`) that monitors WAN connectivity on a UniFi Dream Router. It pings three targets in parallel (FritzBox LAN, first provider hop, external IP) and logs outages that exceed a configurable duration threshold to daily-rotated `.log` and `.csv` files under `/data/wanwatch/logs/`.

There is no build system, package manager, or test suite — the entire project is one shell script.

## Running it

Run directly on the target device (or locally for quick syntax checks):

```sh
# Syntax check only (no network calls)
sh -n wanwatch.sh

# Run live (requires network access to configured IPs)
./wanwatch.sh

# Watch output in a second terminal
tail -f /data/wanwatch/logs/wan-outages-$(date '+%Y-%m-%d').log
```

Stop with `CTRL+C` — the script traps `INT`, `TERM`, and `EXIT` to kill worker subprocesses cleanly.

## Architecture

The script spawns four background processes from the main process:

- **3 worker processes** — each runs `check_target()` in a loop, pinging one target every `INTERVAL` seconds
- **1 purge process** — runs `purge_loop()`, calling `purge_old_logs()` once per day via `find -mtime`

All PIDs are collected in `$PIDS`; the `cleanup` trap iterates and kills them on exit. The main process blocks on `wait`.

### Outage state machine (per worker)

Each `check_target()` worker tracks two flags: `IN_OUTAGE` and `OUTAGE_LOGGED`.

- Ping fails → set `IN_OUTAGE=1`, record `START` timestamp
- While in outage, if `duration > MIN_OUTAGE_DURATION`: write `OUTAGE_START` once (`OUTAGE_LOGGED=1`), then `OUTAGE_CONTINUES` on subsequent ticks
- Ping recovers → if outage was logged, write `OUTAGE_END`; if duration never exceeded threshold, silently discard

This means short glitches (`≤ MIN_OUTAGE_DURATION` seconds) produce no log output at all.

### Log files

Daily rotation is handled by embedding the date in filenames (`wan-outages-YYYY-MM-DD.log` / `.csv`). Old files are purged after `LOG_RETENTION_DAYS` (default 14) by the background `purge_loop`.

## Configuration

Defaults live at the top of `wanwatch.sh`. To override without modifying the tracked file, create `wanwatch.conf` in the same directory — it is sourced after the defaults and is git-ignored:

```sh
# /data/wanwatch/wanwatch.conf
VODAFONE_HOP="83.135.22.1"
MIN_OUTAGE_DURATION=3
```

All tunables:

| Variable | Default | Purpose |
|---|---|---|
| `FRITZBOX_IP` | `192.168.178.1` | LAN IP of the FritzBox |
| `VODAFONE_HOP` | `83.xxx.xxx.xxx` | First provider hop (find with `traceroute`) |
| `EXTERNAL_IP` | `1.1.1.1` | External reachability target |
| `INTERVAL` | `1` | Seconds between pings per worker |
| `TIMEOUT` | `3` | `ping -W` timeout in seconds |
| `MIN_OUTAGE_DURATION` | `5` | Minimum outage duration to log (seconds) |
| `LOG_RETENTION_DAYS` | `14` | Days before log files are purged |

## Deployment target

The script is designed to run on UniFi OS (busybox `sh`, not bash). Keep it POSIX-compatible — no bash-isms (`[[`, arrays, `$(())` is fine, `${var//x/y}` substitutions are not universally safe in busybox sh).
