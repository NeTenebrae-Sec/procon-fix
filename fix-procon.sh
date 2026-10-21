#!/usr/bin/env bash
# fix-procon.sh — Nintendo Switch Pro Controller (clon) por Bluetooth en Arch Linux
# Idempotente: se puede ejecutar cuantas veces se quiera.
#
# Uso:
#   sudo bash ~/fix-procon.sh              # config + servicios + verificación
#   sudo bash ~/fix-procon.sh --pair       # solo re-emparejar (mando en modo SYNC)
#   sudo bash ~/fix-procon.sh --status     # solo diagnosticar, no cambia nada
#
# Historial de por-qué cada paso: ver SPEC.md (RC1..RC7, H1..H5).
set -u

MAC="${PROCON_MAC:-98:B6:77:B5:16:C6}"
IN_CONF=/etc/bluetooth/input.conf
UDEV_RULE=/etc/udev/rules.d/99-gamepad-access.rules
MODE="${1:-full}"

if [ "$MODE" = "--status" ]; then
  echo "== BLUETOOTH =="
  bluetoothctl info "$MAC" 2>&1 | grep -E 'Name|Connected|Paired|Bonded|Trusted|Blocked' || echo "  (mando no visto)"
  echo "== HID ==";       ls /sys/bus/hid/devices/ 2>/dev/null | grep -i 2009 || echo "  (sin device HID del mando)"
  echo "== INPUT ==";     ls /dev/input/js* 2>/dev/null; grep -l 'Vendor=057e' /proc/bus/input/devices >/dev/null 2>&1
  grep -E '^N: Name' /proc/bus/input/devices 2>/dev/null | grep -i 'pro controller' || true
  echo "== SERVICIOS =="
  echo -n "  joycond: ";    systemctl is-enabled joycond 2>/dev/null; systemctl is-active joycond 2>/dev/null
  echo -n "  bluetooth: ";  systemctl is-active bluetooth
  echo "== DRIVER =="
  for d in /sys/bus/hid/devices/0005:057E:2009.*; do
    [ -e "$d" ] && { echo -n "  $d -> "; basename "$(readlink -f "$d/driver" 2>/dev/null)"; }
  done
  echo "== UDEV ==";      ls -la /dev/input/js0 /dev/input/event17 2>/dev/null | awk '{print "  "$1" "$3":"$4" "$NF}'
  echo "== DMESEG (últimos) =="; dmesg 2>/dev/null | grep -iE 'nintendo|uhid|hidp' | tail -5
  exit 0
fi

echo "== 1/5 Config Bluetooth (backup automático) =="
[ -f "$IN_CONF" ] || { echo "  [!!] no existe $IN_CONF"; exit 1; }
[ -f "$IN_CONF.bak" ] || cp "$IN_CONF" "$IN_CONF.bak"
set_conf() {  # $1=clave $2=valor
  local k="$1" v="$2"
  if grep -qE "^#?${k}=" "$IN_CONF"; then sed -i "s/^#*${k}=.*/${k}=${v}/" "$IN_CONF"
  else echo "${k}=${v}" >> "$IN_CONF"; fi
  grep -qE "^${k}=${v}$" "$IN_CONF" && echo "  [+] ${k}=${v}" || echo "  [!!] fallo al poner ${k}"
}
# RC1: el clon sin bond era rechazado. UHID (H1) funciona y hid_nintendo se engancha encima (H3).
set_conf ClassicBondedOnly false
set_conf UserspaceHID true

echo "== 2/5 Servicios =="
# RC4: joycond hace grab exclusivo de event17 y silencia los botones. No usar con Pro Controller.
if systemctl list-unit-files joycond.service >/dev/null 2>&1; then
  systemctl is-active --quiet joycond && echo "  [-] joycond estaba activo (bloqueaba inputs) — deteniendo"
  systemctl disable --now joycond 2>/dev/null && echo "  [+] joycond deshabilitado" || true
fi
systemctl restart bluetooth; sleep 3
bluetoothctl power on 2>/dev/null; bluetoothctl pairable on 2>/dev/null

echo "== 3/5 Permisos de input (RC7) =="
cat > "$UDEV_RULE" <<'EOF'
# procon-fix: acceso de usuario a gamepads (Pro Controller clone via UHID)
KERNEL=="js[0-9]*",     SUBSYSTEM=="input", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="input", MODE="0660", TAG+="uaccess"
KERNEL=="event[0-9]*",  SUBSYSTEM=="input", ENV{ID_INPUT_JOYSTICK}=="?*", GROUP="input", MODE="0660", TAG+="uaccess"
EOF
udevadm control --reload && udevadm trigger --subsystem-match=input --action=change
echo "  [+] $UDEV_RULE"
id -nG | grep -qw input || { usermod -aG input "$SUDO_USER" 2>/dev/null && echo "  [+] $SUDO_USER añadido al grupo input (efectivo en próximo login)"; }

if [ "$MODE" = "--pair" ]; then goto_pair=1; else goto_pair=0; fi
if [ "$goto_pair" = "0" ]; then
  echo "== 4/5 Comprobación automática =="
  bluetoothctl info "$MAC" 2>/dev/null | grep -q 'Connected: yes' && {
    echo "  [+] el mando ya está conectado; omito emparejado (usa --pair para forzar)"
    goto_pair=0
  } || goto_pair=1
fi

if [ "$goto_pair" = "1" ]; then
  echo "== 4/5 EMPAREJAR =="
  echo "Pon el MANDO EN MODO SYNC (botón SYNC trasero hasta LEDs en ráfaga rápida), cerca del PC."
  echo "(RC6: si el mando ya estaba emparejado pero se desconectó, este clon pierde el bond — hay que re-emparejar)"
  read -r -p "Pulsa ENTER cuando esté en modo sync... "
  bluetoothctl remove "$MAC" 2>/dev/null
  bluetoothctl scan on >/dev/null 2>&1
  echo -n "  escaneando"
  FOUND=0
  for i in $(seq 1 90); do
    if bluetoothctl devices 2>/dev/null | grep -qi "$MAC"; then FOUND=1; echo " [descubierto ${i}s]"; break; fi
    [ $((i % 5)) -eq 0 ] && echo -n "."
    sleep 1
  done
  bluetoothctl scan off 2>/dev/null
  [ "$FOUND" != "1" ] && { echo; echo "  [!!] No descubierto. Sal y reintenta con el mando en sync."; exit 1; }
  echo "  pair:";    bluetoothctl pair "$MAC" 2>&1 | tail -1;   sleep 1
  echo "  trust:";   bluetoothctl trust "$MAC" 2>&1 | tail -1
  echo "  connect:"; bluetoothctl connect "$MAC" 2>&1 | tail -1; sleep 3
  # confirma driver nintendo enganchado
  for d in /sys/bus/hid/devices/0005:057E:2009.*; do
    [ -e "$d/driver" ] && echo "  [+] driver: $(basename "$(readlink -f "$d/driver")")"
  done
fi

echo "== 5/5 VERIFICACIÓN =="
bluetoothctl info "$MAC" | grep -iE "paired|connected|trusted"
echo -n "  T2 Paired: ";    bluetoothctl info "$MAC" | grep -qi "Paired: yes"    && echo "PASS ✅" || echo "FAIL ❌"
echo -n "  T3 device HID: ";ls /sys/bus/hid/devices/ 2>/dev/null | grep -qi 2009 && echo "PASS ✅ ($(ls /sys/bus/hid/devices/ | grep 2009))" || echo "FAIL ❌"
echo -n "  T4 joystick: ";  ls /dev/input/js* 2>/dev/null | grep -q .            && echo "PASS ✅ ($(ls /dev/input/js* 2>/dev/null))" || echo "FAIL ❌"
echo -n "  joycond off: ";  systemctl is-active joycond 2>/dev/null | grep -q active && echo "FAIL ❌ (¡bloquea botones!)" || echo "PASS ✅"
echo
echo "Siguiente: abre https://hardwaretester.com/gamepad y pulsa botones (T5)."
echo "Si no registra: cierra y reabre la pestaña; el navegador cachea la lista de gamepads."
echo "(RC6: al apagar el mando puede perder el bond → re-emparejar con --pair)"
