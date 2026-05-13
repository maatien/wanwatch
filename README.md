# wanwatch

`wanwatch` is a small shell-based WAN outage monitor for UniFi OS devices such as the UDR / UDR7. It continuously checks connectivity to three targets and logs short internet dropouts/timeouts, especially useful for documenting intermittent Vodafone cable issues.

The script was designed for a setup where a UniFi Dream Router is connected directly behind a cable FritzBox.

## What it monitors

By default, the script checks these three targets in parallel:

1. **FritzBox LAN IP**  
   Verifies the local connection between the UniFi router and the FritzBox.

2. **First Vodafone hop behind the FritzBox**  
   Helps document issues starting in the provider network.

3. **External reference IP**  
   Verifies general internet reachability.

Default configuration in `wanwatch.sh`:

```sh
FRITZBOX_IP="192.168.178.1"
VODAFONE_HOP="83.xxx.xxx.xxx"
EXTERNAL_IP="1.1.1.1"

INTERVAL=1
TIMEOUT=3
```

You should replace `VODAFONE_HOP` with the first hop after your FritzBox, usually found using `traceroute`.

## Files created on the UniFi device

The script writes logs to:

```text
/data/wanwatch/logs/wan-outages.log
/data/wanwatch/logs/wan-outages.csv
```

`/data` is commonly used as a persistent location on UniFi OS devices.

## Installation

SSH into your UniFi device and copy the script to `/data/wanwatch`:

```sh
mkdir -p /data/wanwatch
cp wanwatch.sh /data/wanwatch/wanwatch.sh
chmod +x /data/wanwatch/wanwatch.sh
```

Edit the target IPs:

```sh
vi /data/wanwatch/wanwatch.sh
```

At minimum, replace:

```sh
VODAFONE_HOP="83.xxx.xxx.xxx"
```

## Find the first Vodafone hop

Run:

```sh
traceroute 1.1.1.1
```

Example:

```text
1  192.168.178.1
2  83.xxx.xxx.xxx
3  ...
```

The second hop is usually the first provider-side hop and should be used as `VODAFONE_HOP`.

## Manual test

Start the script manually:

```sh
/data/wanwatch/wanwatch.sh
```

Watch the log in another SSH session:

```sh
tail -f /data/wanwatch/logs/wan-outages.log
```

Stop the test with `CTRL+C`. The script handles `INT`, `TERM`, and `EXIT` signals and stops all background worker processes cleanly.

## Expected process structure

The script starts one main process and three worker processes, one for each monitored target.

Example:

```text
1x main wanwatch.sh process
3x worker wanwatch.sh processes
3x sleep 1 processes
```

This is normal. The daemon is not necessarily starting the script multiple times; the script itself runs the checks in parallel.

You can inspect this with:

```sh
ps -o pid,ppid,cmd | grep wanwatch | grep -v grep
```

## Install as systemd service

Create the service file:

```sh
cat > /etc/systemd/system/wanwatch.service <<'EOF_SERVICE'
[Unit]
Description=WAN outage monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/data/wanwatch/wanwatch.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_SERVICE
```

Enable and start the service:

```sh
systemctl daemon-reload
systemctl enable wanwatch.service
systemctl start wanwatch.service
```

Check status:

```sh
systemctl status wanwatch.service
```

Follow the log:

```sh
tail -f /data/wanwatch/logs/wan-outages.log
```

## Example log output

```text
2026-05-13 14:03:18 wanwatch started pid=1122951
2026-05-13 14:03:18 worker started target=FRITZBOX ip=192.168.178.1 pid=1122955
2026-05-13 14:03:18 worker started target=VODAFONE_HOP ip=83.xxx.xxx.xxx pid=1122956
2026-05-13 14:03:18 worker started target=EXTERNAL ip=1.1.1.1 pid=1122958
2026-05-13 14:05:22 OUTAGE_START target=VODAFONE_HOP ip=83.xxx.xxx.xxx timeout>3s
2026-05-13 14:05:25 OUTAGE_END target=VODAFONE_HOP ip=83.xxx.xxx.xxx duration=3s
```

## CSV output

The CSV file can be used for later analysis or as documentation for the ISP:

```csv
timestamp,event,target,duration_seconds,result
2026-05-13 14:05:22,OUTAGE_START,VODAFONE_HOP/83.xxx.xxx.xxx,0,timeout>3s
2026-05-13 14:05:25,OUTAGE_END,VODAFONE_HOP/83.xxx.xxx.xxx,3,recovered
```

## Interpretation

Typical provider-side issue pattern:

```text
FRITZBOX stable
VODAFONE_HOP unstable
EXTERNAL unstable
```

This suggests the local link between UniFi and FritzBox is stable, while the issue starts behind the FritzBox in the provider path.

Local issue pattern:

```text
FRITZBOX unstable
VODAFONE_HOP unstable
EXTERNAL unstable
```

This points more toward FritzBox, LAN cable, port, UDR WAN port, or local network problems.

## Stop / remove

Stop the service:

```sh
systemctl stop wanwatch.service
```

Disable autostart:

```sh
systemctl disable wanwatch.service
```

Remove service file:

```sh
rm /etc/systemd/system/wanwatch.service
systemctl daemon-reload
```

Remove script and logs:

```sh
rm -rf /data/wanwatch
```

## Notes

After UniFi OS firmware updates, verify that the systemd service still exists and is enabled:

```sh
systemctl status wanwatch.service
```

The script and logs under `/data/wanwatch` should usually survive updates, but the systemd service file under `/etc/systemd/system` may need to be recreated depending on the UniFi OS version/update behavior.
