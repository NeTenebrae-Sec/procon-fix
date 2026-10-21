# HARDWARE-LIMITS — what software can never fix on these clones

> After everything in [`THE-PROBLEM.md`](THE-PROBLEM.md) is fixed, a cheap
> `057E:2009` clone still has permanent limitations. Knowing them saves
> hours of pointless debugging.

---

## 1. Rumble (haptic feedback) — ❌ absent by design

**What happens:** `hid_nintendo` uploads force-feedback effects and the
kernel reports success:

```
Setting master gain to 75% ... OK
Uploading effect #0 (Periodic sinusoidal) ... OK (id 0)
Uploading effect #4 (Strong rumble) ... OK (id 1)
```

…but the motor never spins. The user feels nothing.

**Why:** the driver talks the *real* Nintendo subcommand protocol over the
vendor channel. The clone **ignores** unknown subcommands, so every command
times out:

```
nintendo 0005:057E:2009.x: joycon_enforce_subcmd_rate: exceeded max attempts
```

The pad only emulates the **input report** (buttons/sticks). Anything that
requires the host to *talk back* (rumble, player-LED fine patterns, IR
camera, HD rumble) is dead hardware.

**Verdict:** not a driver bug, not a bluez bug, not fixable. Games that hard-
require rumble will feel broken; everything else works.

## 2. Bond storage — ⚠️ volatile on host-initiated disconnect

**What happens:** `bluetoothctl disconnect` from the PC sometimes leaves the
pad showing `Paired: no`; reconnecting fails with
`br-connection-create-socket` until you re-pair via SYNC mode.

**Why:** the clone's firmware doesn't persist the link key reliably. When
*the host* tears the connection down, the pad treats it as "forget
everything". An official pad keeps the key for years.

**What still works:** power-cycling the controller — it reconnects on its
own (`Trusted: yes` makes bluez accept it). Only *host-initiated* drops are
dangerous.

**Habit to adopt:**

| You want to… | Do this |
|---|---|
| Stop playing for now | just power off the controller (Home long-press) |
| Pause, keep bond | don't disconnect from the OS; let it sleep |
| Already lost the bond | `sudo bash fix-procon.sh --pair` + SYNC button |

## 3. Battery reporting — ⚠️ nonsense values

`hid_nintendo` exposes a `power_supply` node; the clone reports `0%` /
`Not charging` permanently. Cosmetic — the pad keeps working for hours
anyway. Don't trust the icon.

## 4. IMU timing — ⚠️ noisy but usable

```
nintendo ...: compensating for 4 dropped IMU reports
nintendo ...: delta=90 avg_delta=16
```

The clone's Bluetooth scheduling is sloppy; the driver compensates by
interpolating dropped gyro/accelerometer samples. Good enough for
motion-controlled UIs, not for precision aiming.

## 5. How to tell a genuine pad from a clone (before buying)

| Clue | Genuine | Clone |
|---|---|---|
| Price | ~USD 70 | ~USD 15 |
| `ManufacturerData` in BT scan | Nintendo company ID `0x0330` | random/garbage |
| Rumble | works | silent (this repo's case) |
| LED patterns on connect | full animation | single LED or none |
| Firmware updates | possible via Switch | impossible |

---

## The philosophical conclusion

> The clone got **95 % of the way**: pairing, sticks, buttons, triggers,
> D-pad, IMU, auto-reconnect, player LED. The missing 5 % (rumble, bond
> durability) is firmware, and firmware on a $15 pad is written once and
> forgotten. This repo removes every *software* obstacle — what remains is
> the device being what it is.
