```
███╗   ██╗███████╗██╗   ██╗████████╗██████╗ ██╗   ██╗
████╗  ██║██╔════╝██║   ██║╚══██╔══╝██╔══██╗╚██╗ ██╔╝
██╔██╗ ██║█████╗  ██║   ██║   ██║   ██████╔╝ ╚████╔╝ 
██║╚██╗██║██╔══╝  ██║   ██║   ██║   ██╔══██╗  ╚██╔╝  
██║ ╚████║███████╗╚██████╔╝   ██║   ██║  ██║   ██║   
╚═╝  ╚═══╝╚══════╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝   ╚═╝   

              p r o c o n - f i x
     deterministic Bluetooth fix · Switch Pro clone · Arch Linux
```

> One-year-old problem, solved in one night. A cheap **Nintendo Switch Pro
> Controller clone** would pair over Bluetooth on Arch Linux but never produce
> a single button press. This repo documents the **real root causes** (they
> were not the ones you'd guess) and ships a script that fixes all of them.

---

## TL;DR — the fix in 30 seconds

```bash
sudo bash fix-procon.sh          # apply everything (idempotent)
sudo bash fix-procon.sh --pair   # re-pair only (mando in SYNC mode)
        bash fix-procon.sh --status  # diagnose, changes nothing (no root needed)
```

Then open <https://hardwaretester.com/gamepad> and press buttons.

## The problem

Symptoms observed for months:

- Controller **pairs** with bluez, shows up in `bluetoothctl`… but
- **No joystick appears** in `/dev/input`, nothing works in games or testers.
- The radio side was *perfect*: `btmon` showed the controller streaming input
  reports at 66 Hz over ACL. The data was arriving — it just died before
  reaching `/dev/input`.

The stack is: `controller → ACL radio → bluetoothd → HID bridge → /dev/input`.
The break was always in the **bridge**, never in the radio.

## Real root causes (all of them)

Full write-up with evidence: [`docs/THE-PROBLEM.md`](docs/THE-PROBLEM.md).

| # | Root cause | Symptom it caused | Fix |
|---|---|---|---|
| RC1 | `ClassicBondedOnly=true` in bluez | Clone rejected: *"!bonded device"* | `ClassicBondedOnly=false` |
| RC2 | Kernel 7.2.10 left without modules (`hidp` unloadable) | `Host is down (112)`, no HID device ever | Reboot into 7.2.11 (user's manual reboot) |
| RC3 | MOVISUN K80 headset SDP noise | Scary error every 60 s — **red herring**, unrelated | None needed (ignore / unpair device) |
| RC4 | **`joycond` EVIOCGRAB on the gamepad node** | Device existed, LEDs moved, but **zero buttons reached userspace** | `systemctl disable --now joycond` |
| RC5 | Clone firmware ignores rumble subcommands | Force-feedback uploads succeed, motor never spins | Nothing — hardware limit of the clone |
| RC6 | Clone drops its link key on host-initiated disconnect | `Paired: no` after `bluetoothctl disconnect`; `br-connection-create-socket` on reconnect | Re-pair with `--pair` (forced mode) |
| RC7 | `/dev/input/event*` recreated as `root:root` on each reconnect, `uaccess` ACL unreliable | *"it worked, then buttons vanished again"* | udev rule + `input` group membership |

> **The two villains that hid behind each other:** `joycond` (RC4) made the
> device exist but be mute; flaky ACLs (RC7) made it work and then silently
> stop working. Each one masqueraded as the other's symptom.

## Why this configuration

- **UHID userspace bridge** (`UserspaceHID=true`), not kernel HIDP: after the
  reboot `hidp` *was* available, but `hid_nintendo` attaches happily on top of
  the UHID device — gaining driver features (calibration, IMU, player LEDs)
  with zero kernel-socket fragility. H3 in the spec, decided with data.
- **`hid_nintendo` driver** (kernel 7.2.11): sticks, D-pad, buttons, IMU and
  player LEDs all bound to `0005:057E:2009.*`.
- **`joycond` disabled**: it is for detached Joy-Cons in grip mode; it grabs
  Pro Controllers and swallows their events for no benefit.

## What works / what doesn't

| Feature | Status |
|---|---|
| Sticks, D-pad, all buttons, triggers | ✅ |
| IMU (gyro/accelerometer) | ✅ exposed as `event*` |
| Player LEDs | ✅ driver assigns pattern |
| Battery reporting | ⚠️ clone reports nonsense (`0%`), ignore it |
| Rumble | ❌ clone firmware drops subcommands (`joycon_enforce_subcmd_rate` spam in dmesg) |
| Auto-reconnect after controller power-off | ✅ (`Trusted: yes`) |
| Auto-reconnect after **host**-initiated disconnect | ⚠️ may need `--pair` (RC6 — clone's fault) |

## Requirements

- Arch Linux, kernel **≥ 7.2.11** (`hid_nintendo` built)
- `bluez` with `input.conf`
- A BT adapter (this was proven on Realtek RTL8821C)
- The controller: any `057E:2009` clone

## Install

```bash
git clone https://github.com/neteumbra/procon-fix.git
cd procon-fix
sudo bash fix-procon.sh
```

The script is **idempotent** — run it as many times as you want; it only
changes what's missing and always keeps `*.bak` backups of touched configs.

## Docs

| Doc | What's inside |
|---|---|
| [`docs/THE-PROBLEM.md`](docs/THE-PROBLEM.md) | The full debugging story: evidence, dead ends, and every real root cause |
| [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md) | The command playbook used to isolate the fault — reuse it for the next broken device |
| [`docs/HARDWARE-LIMITS.md`](docs/HARDWARE-LIMITS.md) | What can *never* be fixed in software on these clones (and how to tell genuine from clone) |
| [`SPEC.md`](SPEC.md) | The spec-driven development log: tokens T1–T7, iterations, decisions |

## Uninstall

Everything is plain config — to revert:

```bash
sudo mv /etc/bluetooth/input.conf.bak /etc/bluetooth/input.conf
sudo rm /etc/udev/rules.d/99-gamepad-access.rules
sudo gpasswd -d netenebrae input      # remove yourself from the group
sudo systemctl reenable joycond       # only if you actually use Joy-Cons
```

---

```
 ╔═══════════════════════════════════════════════════╗
 ║  neteumbra · 2026                                ║
 ║  spec-driven, evidence-first, no magic            ║
 ╚═══════════════════════════════════════════════════╝
```
