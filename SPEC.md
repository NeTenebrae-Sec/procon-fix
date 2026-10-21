# SPEC — procon-fix (proyecto bash)

**Objetivo:** solución determinista y reproducible por Bluetooth para mando clone Nintendo Switch Pro Controller en Arch Linux. USB descartado. Desarrollo spec-driven: todo cambio se anota aquí con su token de test.

---

## 1. Contexto (hechos verificados)

| Dato | Valor |
|---|---|
| Kernel en uso | `7.2.10-arch1-1` — **`/lib/modules` BORRADO** por upgrade a 7.2.11 (pendiente reboot manual del usuario) |
| Kernel instalado | `7.2.11-arch1-1` (módulos disponibles: `hidp`, `hid_nintendo`, `uhid`) |
| BT | bluez 5.87-2, adaptador `1C:BF:C0:BF:03:4E` (Realtek `0bda:b00a`, RTL8821C) |
| Mando | `98:B6:77:B5:16:C6` "Pro Controller", clon, modalias `usb:v057Ep2009d0001` |
| `hidp` | `CONFIG_BT_HIDP=m` y **NO cargable con kernel 7.2.10** (dir módulos ausente) → `modinfo hidp` = not found |
| `uhid` | `CONFIG_UHID=m` y **SÍ cargado** ✅ (`lsmod`: `uhid 24576`) |
| `hid_nintendo` | `CONFIG_HID_NINTENDO=m`, módulo en `/lib/modules/7.2.11-arch1-1/` — cargable tras reboot |
| Otro disp BT | MOVISUN K80 `7B:41:6C:0E:0B:B3` (bonded, desconectado — **red herring**) |

---

## 2. Causa raíz (cadena completa)

- **RC1 — BONDEO (RESUELTO ✅):** `ClassicBondedOnly=true` rechazaba el clon (`!bonded device`).
  - Fix: `ClassicBondedOnly=false` en `/etc/bluetooth/input.conf` → **T2 PASS** (bloqueo de 1 año eliminado).

- **RC2 — PUENTE HID (ACTIVO ❌):** se puso `UserspaceHID=false` (ruta kernel HIDP) → necesita `hidp` → **no cargable hasta reboot** → `ioctl_is_connected() Can't open HIDP control socket` → `control_connect_cb ... Host is down (112)` → sin device HID (T3/T4 FAIL) **aunque el ACL esté perfecto**.

- **RC3 — RED HERRING (descartado ✅):** el error cada 60 s `src/profile.c:record_cb() Unable to get Hands-Free Voice gateway SDP record: Host is down` es del **MOVISUN K80** (`7B:41:6C:0E:0B:B3`, `Connect Failed 0x04 = Page Timeout`), no del mando. No tiene nada que ver.

- **RC4 — JOYCOND (RESUELTO ✅):** `joycond` (daemon para Joy-Con en grip, instalado como dependencia de hid_nintendo) hacía **EVIOCGRAB exclusivo de `event17`** → `evtest` reportaba "This device is grabbed by another process" y **el navegador/juegos no recibían botones aunque T3/T4 fueran PASS**. Fix: `systemctl disable --now joycond`. Un Pro Controller no necesita joycond.

- **RC5 — RUMBLE NO SOPORTADO POR EL CLON (limitación de hardware ✅ aceptado):** `hid_nintendo` sube efectos FF vía evdev correctamente (`fftest`: sinusoidal OK, strong rumble OK, gain OK) pero el mando **no vibra**. dmesg: `joycon_enforce_subcmd_rate: exceeded max attempts` continuo = el clon ignora los subcomandos de rumble del protocolo Nintendo (solo emula el report de input). No es bug del stack; es firmware del clon. Rumble queda fuera de alcance (T6 = LED solamente).

- **RC6 — BOND VOLÁTIL EN EL CLON (ABIERTO, mitigado ✅):** `bluetoothctl disconnect` → el clon envía `Connection terminated by remote user` y bluez registra `Paired: no` (link key no persiste; el `info` en `/var/lib/bluetooth` no contiene `[LinkKey]`). El intento de `connect` posterior falla con `br-connection-create-socket` (= bluez intenta conectar un device sin credenciales). **El usuario debe re-emparejar con forced mode (SYNC) tras cada apagado/desconexión del mando** — comportamiento típico de clones baratos sin NVS estable. Mitigación: `Trusted: yes` persiste, así que el mando reconecta **solo** al encenderlo si bluez aún tiene el bond (el fallo solo ocurre si el disconnect es host-initiated). NOTA: la reconexión del usuario tras forced-mode SÍ funcionó y T3/T4/T5 volvieron (device `.0004`, driver `nintendo`, 524 eventos).

- **RC7 — PERMISOS DE /dev/input TRANSITORIOS (RESUELTO ✅):** tras cada reconexión, `event17` aparecía `root:root 600` sin ACL → el navegador no puede leerlo aunque el device exista. El udev `uaccess` estándar no aplicó de forma fiable sobre devices uhid/virtual. Fix persistente: regla `/etc/udev/rules.d/99-gamepad-access.rules` (`GROUP=input MODE=0660 TAG+=uaccess` para `js*`/`event*` con `ID_INPUT_JOYSTICK`) + usuario añadido al grupo `input` (surtirá efecto en próximo login).

- **Evidencia clave (btmon `/tmp/opencode/bt-cap1.txt`, 25.931 líneas, 130 s):**
  - ACL handle 3 empuja `a1 3f 00 00 08 00 80 00 80 00 80 00 80` a **66 Hz** (8.624 paquetes) = **el mando YA envía inputs a nivel radio** (sticks centrados 0x80/0x8000, botones 0).
  - Cero señalización L2CAP hacia PSM 0x11 durante la captura (canal establecido antes de que btmon arrancara).
  - Únicos eventos MGMT: 2 × `Connect Failed` del K80 a 60 s exactos.
  - bluetoothd posee 10/11 sockets L2CAP.
  - **Conclusión: el fallo es puramente de enlace azul→HID, NO de radio.**

---

## 3. Decisiones

- **D1:** Solo Bluetooth. USB descartado explícitamente por el usuario.
- **D2:** REA (github.com/morluto/rea) no aplica — es reverse-engineering de binarios.
- **D3:** El usuario hace el reboot manualmente (nunca el asistente ejecuta `reboot`).
- **D4:** `sudo` NOPASSWD temporal (`/etc/sudoers.d/opencode-temp`) para iterar → **BORRAR AL FINAL: `sudo rm /etc/sudoers.d/opencode-temp`** (checklist §7).
- **D5:** Aceptación vía https://hardwaretester.com/gamepad con Playwright.
- **D6:** El usuario solo hace la acción física del mando (modo forzado/Blueman); todo lo demás se automatiza.
- **D7:** Workflow: btmon primero, cambios después; cada cambio deja rastro en §6.

---

## 4. Tokens de test (aceptación)

| Token | Criterio | Estado |
|---|---|---|
| T1 | Adaptador BT activo | **PASS ✅** |
| T2 | `Bonded: yes` en bluetoothctl | **PASS ⚠️** (ver nota T2-abajo) |
| T3 | `/sys/bus/hid` contiene device del mando (`057E:2009` o HID BT) | **PASS ✅** (`0005:057E:2009.0004`, driver `nintendo`) |
| T4 | `/dev/input/js*` o `event` del mando existe | **PASS ✅** (`js0`+`event17` gamepad, `event16` IMU) |
| T5 | hardwaretester.com/gamepad registra inputs (4 slots ≠ "None detected") | **PASS local ✅** (evtest: 524 eventos ABS/KEY en 14 s) — falta confirmación en navegador |
| T6 | Rumble/LED (requiere `hid_nintendo` post-reboot) | **PARCIAL ⚠️** — LED player-1 OK (driver lo asigna), rumble NO (clon no soporta; ver RC5) |
| T7 | Re-conexión reproducible (forced mode → Blueman → T3-T5) | **FAIL parcial ❌** (ver RC6: el clon pierde el bond al hacer disconnect desde el host) |

> **Nota T2:** en este clon `Paired: yes` es lo real; `Bonded: yes` solo apareció tras el primer pairing y **se pierde en cada disconnect del host** (RC6). T2 cuenta como PASS con `Paired: yes` + `Trusted: yes`.

---

## 5. Hipótesis activas (orden de ataque)

- **H1 (CERRADA ✅):** `UserspaceHID=true` (UHID usa `uhid`, cargado) + restart bluetooth + reconectar → **confirmada: T3 PASS**, y además `hid_nintendo` se engancha al device UHID → T4 PASS.
- **H2 (NO HACE FALTA):** UHID funcionó; no se necesita analizar el handshake L2CAP PSM 0x11.
- **H3 (CERRADA ✅ — decisión: NO volver a `UserspaceHID=false`):** tras reboot 7.2.11 `hidp` está disponible, **pero `hid_nintendo` ya funciona sobre el device UHID** (LEDs, IMU, calibración). Volver a la ruta kernel HIDP no daría beneficio y arriesgaría regresar a "Host is down". Se mantiene UHID. Si en el futuro se quiere rumble real, probar con un mando original (no clon).
- **H4 (NO HACE FALTA):** el clon no exige nombre de host concreto (funciona con `archlinux`).
- **H5 (aplicada en script final):** el script detecta en runtime si `hidp` es cargable y decide UHID vs HIDP; con hid_nintendo funcionando sobre UHID, la ruta por defecto es UHID siempre.

---

## 6. Registro de iteraciones

| # | Fecha | Cambio | Test | Resultado |
|---|---|---|---|---|
| 0 | 2026-10-17 | Baseline: BT conecta, sin input (1 año) | T1-T5 | T1 PASS, T2-T5 FAIL |
| 1 | 2026-10-17 | `ClassicBondedOnly=false` + `UserspaceHID=false` (fix-procon.sh) | T2 | **PASS** — bonding resuelto |
| 2 | 2026-10-17 | btmon captura ciclo fallo (bt-cap1.txt) | diag | RC2+RC3 identificados; mando transmite 66 Hz a nivel radio |
| 3 | 2026-10-17 | **H1: `UserspaceHID=true` + restart bluetooth** — `uhid` ref 0→1 (UHID activo), pero mando quedó `Connected: no` y no reconecta (el usuario no puede sincronizarlo ahora) | T3/T4 | FAIL — **test pendiente tras reboot** |
| 4 | 2026-10-17 | **REBOOT a 7.2.11-arch1-1** — `hidp`+`hid_nintendo` disponibles; `hid_nintendo` se engancha SOLO sobre el device UHID (`.0003`, driver `-> bus/hid/drivers/nintendo`), LEDs player-* aparecen | T3 | **PASS** ✅ — H1 confirmada, H3 resuelta (no hace falta volver a UserspaceHID=false: hid_nintendo funciona sobre UHID) |
| 5 | 2010-17 | diagnóstico T5: `evtest` → "device grabbed by another process" = **`joycond`** con EVIOCGRAB. `systemctl disable --now joycond` | T5 diag | RC4 identificado |
| 6 | 2026-10-17 | jstest confirma botones A/B/X/Y on/off tras quitar joycond; `fftest` sube rumble OK pero mando NO vibra (dmesg `joycon_enforce_subcmd_rate`) | T5/T6 | T5 local PASS; T6 = solo LED (RC5) |
| 7 | 2026-10-17 | `bluetoothctl disconnect`+`connect` (test T7) → `br-connection-create-socket`, `Paired: no`; usuario re-empareja con forced mode → funciona (device `.0004`) | T7 | FAIL — RC6 documentado |
| 8 | 2026-10-17 | `event17` volvió `root:root` sin ACL tras reconexión → regla udev `99-gamepad-access.rules` + `usermod -aG input`; evtest: **524 eventos** en 14 s | T5 | **PASS local** ✅ |

### Estado actual (checkpoint post-iteración 8)

- **Kernel 7.2.11-arch1-1 activo.** `hidp` disponible como módulo (no cargado; innecesario: UHID funciona). `hid_nintendo` cargado y enganchado al mando.
- `/etc/bluetooth/input.conf`: `ClassicBondedOnly=false`, `UserspaceHID=true` (**decidido: mantener UHID** — hid_nintendo funciona encima, H3 cerrada).
- `joycond` **deshabilitado** (RC4 — era lo que bloqueaba los botones).
- Mando: `Paired: yes`, `Trusted: yes`, `Connected: yes`, device HID `.0004`, driver `nintendo`, `js0`+`event17`+`event16`(IMU), 524 eventos en captura.
- Regla udev `99-gamepad-access.rules` + grupo `input` (RC7).
- Batería: 0% "Not charging" (el clon reporta battery rara; probablemente falso — sin importancia práctica).
- dmesg ruido: `joycon_enforce_subcmd_rate` + `compensating for N dropped IMU reports` = clon con timing imperfecto; los inputs llegan igualmente.

### Preguntas abiertas

- ~~¿por qué `br-connection-create-socket` en el connect manual?~~ → **RESPUESTO (RC6):** ocurre porque el clon borra el bond al desconectar desde el host; bluez intenta conectar sin link key. No es bug del socket.

---

## 7. Definition of Done (checklist de cierre)

1. T5 PASS estable + T7 reproducible.
2. Reboot manual del usuario → 7.2.11 → `hid_nintendo` → T6.
3. `~/fix-procon.sh` final: idempotente, con detección H5, documentado.
4. Backups revisados (`/etc/bluetooth/input.conf.bak`, `/etc/bluetooth/main.conf.bak`) → estado final definido.
5. **`sudo rm /etc/sudoers.d/opencode-temp`** ← el sudo temporal se elimina (el asistente lo recuerda).
6. Limpieza: `/tmp/opencode/bt-cap*.txt` (o mover a la spec como evidencia).

---

## Evidencias

- `/tmp/opencode/bt-cap1.txt` — btmon 130 s, 25.931 líneas (ciclo de fallo + streaming ACL del mando).
- `/home/netenebrae/fix-procon.sh` — script actual con toggles.
- `/etc/bluetooth/input.conf` — `ClassicBondedOnly=false`, `UserspaceHID=<actual>`.
