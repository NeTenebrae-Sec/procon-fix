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

> Problema de un año, resuelto en una noche. Una **réplica barra de mando
> Nintendo Switch Pro** emparejaba por Bluetooth en Arch Linux, aparecía en
> `bluetoothctl`… pero ni una sola pulsación llegaba nunca. La radio
> funcionaba perfecta (`btmon` mostraba informes de entrada a 66 Hz): el
> fallo estaba siempre en el puente HID
> (`mando -> radio ACL -> bluetoothd -> puente HID -> /dev/input`), nunca en
> la radio. Este repo documenta las **causas raíz reales** (no eran las que
> nadie esperaba) y entrega un script que las corrige todas.

---

## TL;DR: la solución en 30 segundos

```bash
sudo bash fix-procon.sh          # aplica todo (idempotente)
sudo bash fix-procon.sh --pair   # solo re-emparejar (mando en modo SYNC)
        bash fix-procon.sh --status  # diagnóstico, no cambia nada (sin root)
```

Después abre <https://hardwaretester.com/gamepad> y pulsa botones.

## Instalación

**Requisitos:**

- Arch Linux con kernel **≥ 7.2.11** (`hid_nintendo` compilado)
- `bluez` con `input.conf`
- Un adaptador Bluetooth (probado con Realtek RTL8821C)
- El mando: cualquier clon `057E:2009`

```bash
git clone https://github.com/NeTenebrae-Sec/procon-fix.git
cd procon-fix
sudo bash fix-procon.sh
```

El script es **idempotente**: ejecútalo las veces que quieras; solo cambia
lo que falta y siempre guarda copias `*.bak` de los configs que toca.

## Causas raíz reales (todas)

Análisis completo con evidencia: [`docs/THE-PROBLEM.md`](docs/THE-PROBLEM.md).

| # | Causa raíz | Síntoma que causaba | Corrección |
|---|---|---|---|
| RC1 | `ClassicBondedOnly=true` en bluez | El clon era rechazado: *"!bonded device"* | `ClassicBondedOnly=false` |
| RC2 | Kernel 7.2.10 quedó sin módulos (`hidp` no cargable) | `Host is down (112)`, nunca apareció dispositivo HID | Reboot a 7.2.11 (reinicio manual del usuario) |
| RC3 | Ruido SDP del headset MOVISUN K80 | Error aterrador cada 60 s — **pista falsa**, sin relación | Nada (ignorar / desvincular el dispositivo) |
| RC4 | **`joycond` hace `EVIOCGRAB` sobre el nodo del gamepad** | El dispositivo existía, los LED se movían, pero **cero botones llegaban a userspace** | `systemctl disable --now joycond` |
| RC5 | El firmware del clon ignora los subcomandos de rumble | Las cargas de force-feedback funcionaban, el motor nunca vibraba | Nada — límite de hardware del clon |
| RC6 | El clon pierde su clave de enlace al desconectar el host | `Paired: no` tras `bluetoothctl disconnect`; `br-connection-create-socket` al reconectar | Re-emparejar con `--pair` (modo forzado) |
| RC7 | `/dev/input/event*` se recrea como `root:root` en cada reconexión; ACL `uaccess` poco fiable | *"funcionó, y luego los botones desaparecieron"* | Regla udev + pertenencia al grupo `input` |

> **Los dos villanos que se escondían el uno tras el otro:** `joycond` (RC4)
> hacía que el dispositivo existiera pero estuviera mudo; las ACL
> inestables (RC7) hacían que funcionara y luego dejara de funcionar en
> silencio. Cada uno se disfrazaba del síntoma del otro.

## Estado de funciones

| Función | Estado |
|---|---|
| Sticks, D-pad, todos los botones, triggers | sí |
| IMU (giroscopio / acelerómetro) | sí — expuesto como `event*` |
| LEDs de jugador | sí — el driver asigna el patrón |
| Reporte de batería | parcial — el clon reporta basura (`0%`), ignóralo |
| Rumble | no — el firmware del clon descarta los subcomandos (spam de `joycon_enforce_subcmd_rate` en dmesg) |
| Reconexión automática tras apagar el mando | sí (`Trusted: yes`) |
| Reconexión tras desconexión iniciada por el host | parcial — puede requerir `--pair` (RC6, culpa del clon) |

## Por qué esta configuración

- **Puente HID en userspace UHID** (`UserspaceHID=true`), no el HIDP del
  kernel: tras el reboot `hidp` *sí* estaba disponible, pero `hid_nintendo`
  se engancha encima del dispositivo UHID sin fragilidad — gana las
  funciones del driver (calibración, IMU, LEDs de jugador). Decidido con
  datos.
- **Driver `hid_nintendo`** (kernel 7.2.11): sticks, D-pad, botones, IMU y
  LEDs de jugador, todo vinculado a `0005:057E:2009.*`.
- **`joycond` desactivado**: está pensado para Joy-Cons sueltos en grip; agarra
  los Pro Controllers y se traga sus eventos sin ningún beneficio.

## Documentación

| Documento | Qué contiene |
|---|---|
| [`docs/THE-PROBLEM.md`](docs/THE-PROBLEM.md) | La historia completa de depuración: evidencias, callejones sin salida y cada causa raíz real |
| [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md) | El manual de comandos usado para aislar la avería — reutilízalo con el próximo dispositivo roto |
| [`docs/HARDWARE-LIMITS.md`](docs/HARDWARE-LIMITS.md) | Qué **nunca** se puede corregir por software en estos clones (y cómo distinguir un original de un clon) |
| [`SPEC.md`](SPEC.md) | El registro de desarrollo spec-driven: tokens T1–T7, iteraciones, decisiones |

## Desinstalación

Todo es configuración pura — para revertir:

```bash
sudo mv /etc/bluetooth/input.conf.bak /etc/bluetooth/input.conf
sudo rm /etc/udev/rules.d/99-gamepad-access.rules
sudo gpasswd -d netenebrae input      # te sacas del grupo
sudo systemctl reenable joycond       # solo si realmente usas Joy-Cons
```

## Licencia

**MIT** (ver [LICENSE](LICENSE))
