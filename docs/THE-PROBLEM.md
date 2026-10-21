# THE-PROBLEM — how a one-year-old "dead" controller got fixed

> Symptom reported by the user: *the controller pairs, Bluetooth sees it,
> but no game ever receives a single input.* It had been like that for
> **a year**.

This is the real debugging story — including the wrong turns. Every root
cause below left concrete evidence; nothing here was fixed by guessing.

---

## 0. The stack and where the fault had to be

```
┌────────────┐   ACL radio    ┌─────────────┐   HID bridge    ┌──────────────┐
│  controller │ ─────────────► │ bluetoothd  │ ──────────────► │  /dev/input  │
│   (clone)   │   66 Hz data   │   (bluez)   │  UHID / HIDP   │  js0,event*  │
└────────────┘                 └─────────────┘                 └──────────────┘
```

A `btmon` capture (130 s, 25 931 lines) showed handle 3 pushing
`a1 3f 00 00 08 00 80 00 80 00 80 00 80` at **66 Hz** — sticks centered
(`0x80`), buttons `0`. The controller *was* transmitting inputs over the
air. Therefore: **the radio is innocent; the break is in the bridge.**

---

## 1. RC1 — bluez rejected the clone for not being "bonded"

**Symptom:** `Rejected !bonded device` in bluetoothd logs.

**Cause:** `/etc/bluetooth/input.conf` shipped with `ClassicBondedOnly=true`
— a hard rejection of any device that didn't complete *classic* pairing the
way an official Nintendo pad does. Clones often skip parts of it.

**Fix (permanent):**

```ini
# /etc/bluetooth/input.conf
ClassicBondedOnly=false
```

**Evidence it worked:** `bluetoothctl info` went from rejected to
`Paired: yes`. Token T2 turned PASS.

> But pairing was never the whole story — the pad could pair and *still*
> produce nothing. Keep reading.

---

## 2. RC2 — the kernel had no module directory (broken upgrade)

**Symptom:** `ioctl_is_connected() Can't open HIDP control socket` and
`control_connect_cb ... Host is down (112)`, even with a flawless ACL link.

**Cause:** the machine ran kernel **7.2.10** while an upgrade to **7.2.11**
had already deleted `/lib/modules/7.2.10`. Every loadable module — including
`hidp`, the kernel Bluetooth HID bridge — was **gone**. `modinfo hidp`
returned *not found*.

**Fix:** the user's manual reboot into 7.2.11 (never auto-reboot a machine
you don't own). After the reboot:

- `hidp` available again (`/lib/modules/7.2.11-arch1-1/.../hidp.ko.zst`)
- `hid_nintendo` available and loaded
- and suddenly a HID device appeared: `0005:057E:2009.*`

**Lesson:** a *silent partial upgrade* can masquerade as an application bug.
Always check `uname -r` vs `/lib/modules` first.

---

## 3. RC3 — a red herring that wasted time

Every 60 seconds:

```
src/profile.c:record_cb() Unable to get Hands-Free Voice gateway
SDP record: Host is down
```

Looks terrifying. It belongs to a **MOVISUN K80 headset** (`7B:41:6C:0E:0B:B3`,
`Connect Failed 0x04 = Page Timeout`) bonded months ago — not to the
controller. The controller never logs anything like this.

**Fix:** none needed. Unpair the headset if you want a quiet journal.
Rule of thumb: **match every error line to a MAC address** before chasing it.

---

## 4. RC4 — `joycond` was eating the inputs (the big one)

**Symptom:** the HID device existed, `hid_nintendo` bound to it, player LEDs
even lit up — and yet `evtest` printed:

```
This device is grabbed by another process.
No events are available to evtest while the other grab is active.
```

**Cause:** `joycond` — a daemon meant for **detached Joy-Cons in a grip** —
had `EVIOCGRAB`'d `/dev/input/event17`. An exclusive grab means *every*
other consumer (evtest, jstest, browsers, games, Steam) sees a mute device.
The controller's events went into joycond, which has nothing to do with a
Pro Controller and did nothing with them.

Diagnosis in one command:

```bash
sudo fuser -v /dev/input/event17
# root  1167  F....  joycond
```

**Fix (permanent):**

```bash
sudo systemctl disable --now joycond
```

The instant it died, `jstest` started reporting `BtnA/BtnB/BtnX/BtnY: on/off`
following real button presses. **524 events in 14 seconds** on `evtest`.

> This was the root cause of the "paired but dead" experience — and it had
> nothing to do with Bluetooth at all.

---

## 5. RC5 — the clone simply has no rumble (hardware limit)

With `hid_nintendo` driving the pad, `fftest` uploaded effects successfully:

```
Setting master gain to 75% ... OK
Uploading effect #0 (Periodic sinusoidal) ... OK
Uploading effect #4 (Strong rumble) ... OK
```

…and the motor never spun. The user confirmed: *"no vibro"*.

dmesg explains why:

```
nintendo 0005:057E:2009.x: joycon_enforce_subcmd_rate: exceeded max attempts
```

The driver sends Nintendo-protocol subcommands; the clone **ignores** them
(it only emulates the input report). Every subcommand — rumble, IR, player
LED fine-tuning — times out. Not fixable in software. See
[`HARDWARE-LIMITS.md`](HARDWARE-LIMITS.md).

---

## 6. RC6 — the clone forgets its link key

**Symptom:** after `bluetoothctl disconnect`, the device showed `Paired: no`,
and a manual `connect` failed with:

```
org.bluez.Error.Failed br-connection-create-socket
```

That error is just bluez trying to open a socket to a device it has **no
credentials for** — the pairing record is gone.

**Cause:** cheap clone firmware without stable NV storage: when *the host*
ends the connection, it wipes the bond (`Connection terminated by remote
user`). `/var/lib/bluetooth/<adapter>/<mac>/info` contained no `[LinkKey]`.

**Reality check:**

| Disconnect type | Bond survives? |
|---|---|
| Controller powers off / goes to sleep | ✅ yes — it reconnects by itself (`Trusted: yes`) |
| `bluetoothctl disconnect` / Bluetooth settings from the PC | ❌ often lost → re-pair with `--pair` |

**Mitigation:** none possible from the host side (it's the clone's firmware).
Live with it, or buy a genuine pad. The script's `--pair` mode handles the
re-pairing dance (SYNC button → scan → pair → trust → connect).

---

## 7. RC7 — permissions that "worked and then stopped" (the nasty one)

**Symptom:** everything functional… then, after a disconnect/reconnect cycle,
the browser tester suddenly saw **no gamepad**. Again. And again.

**Cause:** each reconnect recreates `/dev/input/event*` nodes. Stock udev
leaves them `root:root` and relies on logind's `uaccess` ACL, which applies
to the *active seat session* — but on uhid-created (virtual) devices it is
**unreliable**: it ACL'd `js0` and `event16` but skipped `event17`, the very
node browsers read.

Verified directly:

```
/dev/input/js0:     LEGIBLE ✅  (had ACL)
/dev/input/event16: LEGIBLE ✅  (had ACL)
/dev/input/event17: SIN ACCESO ❌  (no ACL, root:root)
```

**Fix (permanent, two parts):**

```bash
# 1. udev rule — enforce group + mode on every joystick node, every time
# /etc/udev/rules.d/99-gamepad-access.rules
KERNEL=="js[0-9]*",    SUBSYSTEM=="input", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="input", MODE="0660", TAG+="uaccess"
KERNEL=="event[0-9]*", SUBSYSTEM=="input", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="input", MODE="0660", TAG+="uaccess"

# 2. the user joins the group (takes effect on next login!)
sudo usermod -aG input "$USER"
```

> **The trap:** `usermod` returns instantly, but the group is only active
> for **new sessions**. This is precisely why the machine kept failing until
> a reboot — and why it has worked ever since.

---

## 8. The final picture

After all fixes, verified post-reboot:

| Check | Result |
|---|---|
| `ls /sys/bus/hid/devices/ \| grep 2009` | `0005:057E:2009.0004` |
| driver symlink | `-> bus/hid/drivers/nintendo` |
| `/dev/input` | `js0` + `event17` (gamepad) + `event16` (IMU) |
| event throughput | 524 events / 14 s under `evtest` |
| permissions | `root:input 0660` + group `input` active |
| `joycond` | disabled, inactive |
| reconnect after power cycle | automatic |

## 9. Timeline of the night (for the record)

1. Baseline documented, `btmon` proved the radio fine (66 Hz stream).
2. `ClassicBondedOnly=false` → pairing OK (RC1).
3. `UserspaceHID=true` chosen → UHID bridge; reboot to 7.2.11 unlocked
   `hid_nintendo` → HID device appeared (RC2, H1/H3 closed).
4. `evtest` exposed the grab → `joycond` identified and killed (RC4).
5. `jstest`/`evtest` flooded with real inputs → T5 local PASS.
6. Reconnect test destroyed the bond → RC6 documented, `--pair` workflow.
7. Reconnect exposed the ACL gap → udev rule + group (RC7).
8. Reboot → everything permanent. Done.

---

*Every claim in this document was verified on the machine, with the logs
quoted. When the evidence and the intuition disagreed, the evidence won.*
