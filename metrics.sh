#!/usr/bin/env bash

URL="https://YOUR_VERCEL_URL.vercel.app/api/telemetry"
SECRET_KEY="YOUR_HOMELAB_SECRET_KEY"
PID_FILE="/tmp/homelab_telemetry.pid"

if [ "$1" = "-stop" ]; then
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            echo "Successfully stopped telemetry service (PID: $PID)."
        else
            echo "Process $PID not found, cleaning up stale PID file."
        fi
        rm -f "$PID_FILE"
    else
        echo "Telemetry service is not currently running."
    fi
    exit 0
fi

if [ -f "$PID_FILE" ]; then
    if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Error: Telemetry is already running (PID: $(cat "$PID_FILE"))."
        echo "Use './telemetry.sh -stop' to stop it first."
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
    INTERVAL_SECONDS="$1"
else
    INTERVAL_SECONDS=30
fi

run_telemetry() {
    IFACE=$(ip route | grep default | sed -e "s/^.*dev \([^ ]*\).*$/\1/" | head -n1)
    
    read_rx() { cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0; }
    read_tx() { cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0; }

    PREV_RX=$(read_rx)
    PREV_TX=$(read_tx)

    while true; do
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        CPU=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')

        read MEM_USED MEM_TOTAL MEM_PCT <<< $(free -m | awk 'NR==2{printf "%.2f %.2f %.1f", $3/1024, $2/1024, $3*100/$2}')

        read DISK_USED DISK_TOTAL DISK_PCT <<< $(df -BM / | awk 'NR==2{printf "%.2f %.2f %s", $3/1024, $2/1024, $5}' | tr -d '%')

        sleep "$INTERVAL_SECONDS"
        
        CUR_RX=$(read_rx)
        CUR_TX=$(read_tx)

        RX_RATE=$(awk "BEGIN {printf \"%.1f\", (($CUR_RX - $PREV_RX) / $INTERVAL_SECONDS) * 8 / 1000}")
        TX_RATE=$(awk "BEGIN {printf \"%.1f\", (($CUR_TX - $PREV_TX) / $INTERVAL_SECONDS) * 8 / 1000}")

        PREV_RX=$CUR_RX
        PREV_TX=$CUR_TX

        PAYLOAD=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "cpu_percent": $CPU,
  "memory": {
    "used_gb": $MEM_USED,
    "total_gb": $MEM_TOTAL,
    "percent": $MEM_PCT
  },
  "network": {
    "download_kbps": $RX_RATE,
    "upload_kbps": $TX_RATE
  },
  "storage": {
    "used_gb": $DISK_USED,
    "total_gb": $DISK_TOTAL,
    "percent": $DISK_PCT
  }
}
EOF
)

        curl -s -L -X POST "$URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $SECRET_KEY" \
            -d "$PAYLOAD"
    done
}

run_telemetry > /dev/null 2>&1 &

echo $! > "$PID_FILE"
echo "Telemetry service started in the background (PID: $!)."
echo "Interval set to $INTERVAL_SECONDS seconds."
echo "To stop the service, run: $0 -stop"