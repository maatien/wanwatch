#!/bin/sh

FRITZBOX_IP="192.168.178.1"
VODAFONE_HOP="83.xxx.xxx.xxx"
EXTERNAL_IP="1.1.1.1"

LOG_DIR="/data/wanwatch/logs"
LOG_RETENTION_DAYS=14

INTERVAL=1
TIMEOUT=3
MIN_OUTAGE_DURATION=5

PIDS=""

mkdir -p "$LOG_DIR"

log_text() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_DIR/wan-outages-$(date '+%Y-%m-%d').log"
}

log_csv() {
  _csv="$LOG_DIR/wan-outages-$(date '+%Y-%m-%d').csv"
  [ -f "$_csv" ] || echo "timestamp,event,target,duration_seconds,result" >> "$_csv"
  echo "$(date '+%Y-%m-%d %H:%M:%S'),$1,$2,$3,$4" >> "$_csv"
}

purge_old_logs() {
  find "$LOG_DIR" -name "wan-outages-*.log" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null
  find "$LOG_DIR" -name "wan-outages-*.csv" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

purge_loop() {
  while true; do
    purge_old_logs
    sleep 86400
  done
}

log_outage_start() {
  NAME="$1"
  IP="$2"
  DURATION="$3"

  log_text "OUTAGE_START target=$NAME ip=$IP duration=${DURATION}s timeout>${TIMEOUT}s threshold>${MIN_OUTAGE_DURATION}s"
  log_csv "OUTAGE_START" "$NAME/$IP" "$DURATION" "timeout>${TIMEOUT}s threshold>${MIN_OUTAGE_DURATION}s"
}

cleanup() {
  log_text "wanwatch stopping"

  for PID in $PIDS; do
    kill "$PID" 2>/dev/null
  done

  wait 2>/dev/null

  log_text "wanwatch stopped"
  exit 0
}

trap cleanup INT TERM EXIT

check_target() {
  NAME="$1"
  IP="$2"

  START=""
  IN_OUTAGE=0
  OUTAGE_LOGGED=0

  log_text "worker started target=$NAME ip=$IP pid=$$"

  while true; do
    if ping -c 1 -W "$TIMEOUT" "$IP" >/dev/null 2>&1; then
      if [ "$IN_OUTAGE" -eq 1 ]; then
        END_TS=$(date +%s)
        DURATION=$((END_TS - START))

        if [ "$DURATION" -gt "$MIN_OUTAGE_DURATION" ]; then
          if [ "$OUTAGE_LOGGED" -eq 0 ]; then
            log_outage_start "$NAME" "$IP" "$DURATION"
          fi

          log_text "OUTAGE_END target=$NAME ip=$IP duration=${DURATION}s"
          log_csv "OUTAGE_END" "$NAME/$IP" "$DURATION" "recovered"
        fi

        IN_OUTAGE=0
        OUTAGE_LOGGED=0
        START=""
      fi
    else
      NOW_TS=$(date +%s)

      if [ "$IN_OUTAGE" -eq 0 ]; then
        START="$NOW_TS"
        IN_OUTAGE=1
        OUTAGE_LOGGED=0
      else
        DURATION=$((NOW_TS - START))

        if [ "$DURATION" -gt "$MIN_OUTAGE_DURATION" ]; then
          if [ "$OUTAGE_LOGGED" -eq 0 ]; then
            log_outage_start "$NAME" "$IP" "$DURATION"
            OUTAGE_LOGGED=1
          else
            log_text "OUTAGE_CONTINUES target=$NAME ip=$IP duration=${DURATION}s"
          fi
        fi
      fi
    fi

    sleep "$INTERVAL"
  done
}

log_text "wanwatch started pid=$$"

purge_loop &
PIDS="$PIDS $!"

check_target "FRITZBOX" "$FRITZBOX_IP" &
PIDS="$PIDS $!"

check_target "VODAFONE_HOP" "$VODAFONE_HOP" &
PIDS="$PIDS $!"

check_target "EXTERNAL" "$EXTERNAL_IP" &
PIDS="$PIDS $!"

wait
