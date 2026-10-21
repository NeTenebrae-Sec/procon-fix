# DIAGNOSTICS — the command playbook

> Every command below was actually used (or is a tightened version of one)
> during the procon-fix session. They are ordered as a funnel: cheap checks
> first, invasive last. Run them in order; stop when you find the break.

---

## 1. Is the radio even receiving? (prove the controller transmits)

```bash
sudo btmon --warning          # or: bluetoothctl monitor
```

Look for input reports on the ACL handle — for a Pro-style pad:

```
a1 3f 00 00 08 00 80 00 80 00 80 00 80
```

`0x80 / 0x8000` = centered sticks. If you see these at 60+ Hz, **the
Bluetooth layer is fine** and the fault is downstream. Don't touch bluez.

## 2. What does bluez think?

```bash
bluetoothctl info AA:BB:CC:DD:EE:FF
```

| Field | Healthy value | If wrong |
|---|---|---|
| `Connected` | `yes` | radio/pairing problem — go back to step 1 |
| `Paired` | `yes` | clone lost its bond → `--pair` (RC6) |
| `Trusted` | `yes` | no auto-reconnect → `bluetoothctl trust <mac>` |

## 3. Did a HID device appear?

```bash
ls /sys/bus/hid/devices/ | grep -i 2009
readlink -f /sys/bus/hid/devices/0005:057E:2009.*/driver
```

- **No device:** the bridge is broken. Check `UserspaceHID` in
  `/etc/bluetooth/input.conf`, check the kernel still has its modules
  (`ls /lib/modules/$(uname -r)` — a half-done upgrade deletes them! RC2).
- **Device but `-> bus/hid/drivers/generic-usb`:** `hid_nintendo` didn't
  bind — `sudo modprobe hid_nintendo`.

## 4. Are events reaching userspace?

```bash
sudo evtest /dev/input/event17     # watch while pressing buttons
jstest /dev/input/js0              # needs no root once group is set
```

If evtest prints:

```
This device is grabbed by another process.
```

**Stop. That's RC4.** Find the grabber and kill it:

```bash
sudo fuser -v /dev/input/event17
sudo systemctl disable --now joycond     # 99% of the time it's this
```

## 5. Can *your user* read the device?

```bash
for f in /dev/input/event17 /dev/input/js0; do
  test -r "$f" && echo "$f: OK" || echo "$f: NO ACCESS"
done
```

`NO ACCESS` after a reconnect → RC7. Check both layers:

```bash
ls -la /dev/input/event17            # want: root:input 0660
id -nG | grep input                  # want: "input" listed (new login!)
getfacl /dev/input/event17           # uaccess ACL as fallback
```

> Remember: `usermod -aG` needs a **fresh login** to take effect.

## 6. Bluetooth journal — matching errors to devices

```bash
journalctl -u bluetooth -b --no-pager | grep -viE 'Hands-Free|Voice'
sudo dmesg | grep -iE 'nintendo|uhid|hidp' | tail
```

Interpretation cheatsheet:

| Log line | Meaning |
|---|---|
| `Rejected !bonded device` | RC1 — set `ClassicBondedOnly=false` |
| `Host is down (112)` / `Can't open HIDP control socket` | RC2 — kernel modules missing or controller asleep |
| `br-connection-create-socket` | RC6 — no bond left, re-pair |
| `Unable to get Hands-Free ... SDP record` | RC3 — some old headset, **ignore** |
| `joycon_enforce_subcmd_rate: exceeded max` | RC5 — clone ignores subcommands (rumble won't work) |
| `compensating for N dropped IMU reports` | clone timing noise — harmless |

## 7. Full health snapshot

```bash
bash fix-procon.sh --status
```

Prints BT state, HID device, input nodes, service status, bound driver,
node permissions and the last kernel lines — the whole funnel in one call.

---

## Order of operations (the meta-rule)

1. **btmon first, changes after.** Never reconfigure bluez without a capture
   showing where the data dies.
2. **One change, one verification.** Token tests T1–T7 exist for this.
3. **Match every error to a MAC address** before believing it's your device.
