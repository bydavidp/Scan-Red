# Scan-Red

Escáner de red local multiplataforma, escrito en Python. Descubre equipos con
ping/ARP, resuelve nombres, identifica fabricantes por OUI, guarda historial de
altas y bajas, exporta CSV/JSON y, opcionalmente, escanea puertos TCP.

La versión PowerShell original (con alertas, lista blanca, vigilancia continua,
HTML y presencia histórica) se conserva en [`legacy/`](legacy/README.md).

> **Uso responsable:** ejecuta Scan-Red solo en redes que administres o para las
> que tengas autorización escrita. El flag `--autorizado` es obligatorio.

---

## Características

- **Ping sweep** concurrente sobre un rango de la LAN.
- **Tabla ARP/neighbor** multiplataforma (Windows, Linux, macOS), con
  normalización de MAC y detección de equipos que no responden a ICMP pero sí
  están en la red.
- **DNS inverso** en paralelo y **NetBIOS** opcional en Windows (`--netbios`).
- **Fabricante por OUI** con caché local, límite de peticiones y fallback entre
  dos APIs. Se puede desactivar con `--sin-fabricante`.
- **Historial** de equipos nuevos, conocidos y desaparecidos. La MAC es la
  identidad estable; si no hay MAC se usa la IP.
- **CSV y JSON** con puertos abiertos, fechas y estado.
- **Escaneo de puertos TCP** opcional:
  - `connect` (por defecto): sin privilegios, conexión completa.
  - `syn`: con `scapy`, requiere administrador/root y Npcap en Windows.
- **Salvaguarda legal** integrada en la librería, no solo en la CLI.

## Requisitos

- Python **3.10 o superior**.
- Windows, Linux o macOS.
- Para el motor `syn`: `pip install "scan-red[syn]"` + permisos elevados
  (Npcap en Windows).
- Internet solo si quieres resolver fabricantes por OUI.

## Instalación

```powershell
git clone https://github.com/bydavidp/Scan-Red.git
cd Scan-Red

python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Uso normal
python -m pip install -e .

# Desarrollo (pytest + ruff)
python -m pip install -e ".[dev]"

# Motor SYN opcional
python -m pip install -e ".[syn]"
```

En Linux/macOS la activación es `source .venv/bin/activate`.

El comando instalado es `scan-red`. También puedes ejecutar el paquete sin
instalarlo, desde la raíz del repositorio:

```powershell
python -m scan_red --autorizado
```

## Uso rápido

```powershell
# Escaneo por defecto: 192.168.1.1-254, historial y CSV
scan-red --autorizado

# Rango concreto
scan-red --red 192.168.0 --inicio 1 --fin 100 --autorizado

# Puertos TCP (connect)
scan-red --autorizado --puertos 22,80,443,3389

# Rango de puertos
scan-red --autorizado --puertos 1-1024

# Motor SYN (scapy + administrador)
scan-red --autorizado --puertos 80,443 --motor-puertos syn

# Sin consultar fabricantes (sin internet)
scan-red --autorizado --sin-fabricante

# Exportar también a JSON
scan-red --autorizado --json reporte.json
```

### Parámetros

| Parámetro | Equivalente PowerShell | Descripción |
|---|---|---|
| `-Red`, `--red` | `-Red` | Prefijo de 3 octetos. Por defecto `192.168.1`. |
| `-Inicio`, `--inicio` | `-Inicio` | Primer octeto del rango. Por defecto `1`. |
| `-Fin`, `--fin` | `-Fin` | Último octeto del rango. Por defecto `254`. |
| `-TimeoutMs`, `--timeout-ms` | `-TimeoutMs` | Espera de ping en ms. Por defecto `800`. |
| `-Carpeta`, `--carpeta` | `-Carpeta` | Carpeta de reportes. Por defecto `~/Reportes-Red`. |
| `-Csv`, `--csv` | `-Csv` | Nombre/ruta del CSV (relativo a `-Carpeta`). |
| `--json` | — | Exporta además un JSON. |
| `-SinCsv`, `--sin-csv` | `-SinCsv` | No genera CSV. |
| `-SinHistorial`, `--sin-historial` | `-SinHistorial` | No lee ni guarda estado anterior. |
| `-SinFabricante`, `--sin-fabricante` | `-SinFabricante` | No consulta fabricantes. |
| `--netbios` | `-NetBios` | Prueba NetBIOS si falla el DNS inverso. |
| `--puertos` | `-Puertos` | Lista/rango de puertos TCP. Vacío = no escanear. |
| `--motor-puertos` | — | `connect` (defecto) o `syn`. |
| `--timeout-puerto` | `-TimeoutPuertoMs` | Timeout por conexión TCP, en segundos. |
| `--solo-publicas` | — | Omite IPs privadas/reservadas. |
| `--autorizado` | — | Confirmación legal **obligatoria**. |
| `-v`, `--verbose` | — | `-v` info, `-vv` debug. |
| `--version` | — | Muestra la versión. |

## Migración desde PowerShell

| PowerShell (`legacy/scan-red.ps1`) | Python (`scan-red`) |
|---|---|
| `.\scan-red.ps1` | `scan-red --autorizado` |
| `-Red 192.168.0 -Inicio 1 -Fin 100` | igual, con `--red`, `--inicio`, `--fin` |
| `-Carpeta C:\Reportes` | `-Carpeta C:\Reportes` |
| `-Csv salida.csv` | `-Csv salida.csv` |
| `-SinCsv`, `-SinHistorial`, `-SinFabricante` | mismos nombres |
| `-NetBios` | `--netbios` |
| `-Puertos 22,80,443` | `--puertos 22,80,443` |
| `-EscanearPuertos` | se activa al pasar `--puertos` |
| `-Vigilar`, `-Veces`, `-IntervaloSeg` | no portado: usa el Programador de tareas o `cron` |
| `-ResumenHistorial` | no portado |
| `-Autorizar MAC` | no portado: la lista blanca vive en `legacy/config.json` |

### Alcance de esta reescritura

| Función | Python | PowerShell legacy |
|---|---|---|
| Ping / ARP / DNS / OUI | Sí | Sí |
| Historial nuevo/conocido/desaparecido | Sí | Sí |
| CSV | Sí | Sí |
| JSON | Sí | — |
| Puertos `connect` | Sí | Sí |
| Puertos `syn` | Sí (`scapy`) | — |
| NetBIOS | Sí (opt-in) | Sí |
| Alertas toast / Telegram / email | — | Sí |
| Lista blanca | — | Sí |
| Vigilancia continua | — | Sí |
| Reporte HTML | — | Sí |
| Presencia histórica | — | Sí |
| Configuración `config.json` | — (flags) | Sí |

El objetivo de esta rama es portar el núcleo del escáner y añadir el motor de
puertos. Las funciones de la versión 2 de PowerShell siguen disponibles en
`legacy/` y pueden portarse en una siguiente fase.

## Historial y compatibilidad

- El estado se guarda en `<Carpeta>/estado-anterior.json`.
- La clave es la **MAC**; si el equipo no tiene MAC, `IP:<ip>`.
- Se guardan varias IPs por MAC (por ejemplo, cámaras con dos direcciones).
- El JSON incluye claves en `snake_case` y en `PascalCase` (`IPs`,
  `PrimeraVez`, `UltimoVisto`, ...) para que la versión PowerShell pueda leerlo
  y escribir en el mismo archivo.
- `--sin-historial` no lee ni escribe el estado; todos los equipos aparecen con
  `Cambio = "-"`.
- Un equipo "desaparecido" es el que estaba en el estado anterior y no apareció
  en este escaneo. Se muestra una vez y deja de estar en el estado guardado.

> La presencia es aproximada: se basa en los escaneos, no es uptime real.

## Cómo funciona

1. Ping sweep concurrente (64 procesos a la vez) sobre el rango.
2. Lectura de la tabla ARP/neighbor del sistema.
3. Unión de IPs que respondieron a ping o que están en ARP.
4. DNS inverso en paralelo; NetBIOS opcional.
5. Fabricante por OUI, con caché en `~/.scan-red-oui-cache.json` y 1 petición/s.
6. Comparación con el estado anterior.
7. Escaneo TCP de los puertos indicados, sobre todos los equipos descubiertos.
8. Salida por consola, CSV/JSON y guardado del estado.

### Puertos

- `connect` abre conexiones TCP reales. No necesita privilegios, pero queda
  registrado en los logs del equipo escaneado. Límite por defecto: 500
  conexiones/s y 200 en paralelo.
- `syn` envía paquetes SYN y no completa la conexión. Requiere `scapy`,
  permisos elevados y Npcap en Windows.
- `--solo-publicas` omite IPs privadas, loopback, link-local, multicast y
  rangos reservados. En una LAN normal no escaneará nada; es una protección
  para usos concretos sobre IPs públicas autorizadas.
- Los puertos se muestran en la columna `PUERTOS` y en `PuertosAbiertos` del
  CSV, separados por comas.

## Columnas del CSV

`IP, MAC, Nombre, Fabricante, Estado, Ms, PrimeraVez, UltimoVisto, Cambio,
PuertosAbiertos`

El CSV se escribe en **UTF-8 con BOM** (`utf-8-sig`) para que Excel lo abra
correctamente.

## Estructura

```text
scan_red/
├── __init__.py
├── __main__.py
├── cli.py
├── discovery.py
├── exporters.py
├── history.py
├── models.py
└── portscanner/
    ├── __init__.py
    ├── connect.py
    ├── legal.py
    └── syn.py
tests/
legacy/            # versión PowerShell original
pyproject.toml
```

## Pruebas y calidad

```powershell
python -m pytest -q
ruff check scan_red tests
ruff format --check scan_red tests
```

La suite cubre salvaguardas legales, parseo ARP (Windows/Linux/MAC con puntos),
normalización de MAC/OUI, historial (incluida compatibilidad con PowerShell),
exportadores, CLI y escaneo `connect` contra un servidor local.

## Limitaciones

- El ping se hace con el binario del sistema: 254 procesos por escaneo
  (limitados a 64 concurrentes). Es portable, pero más lento que ICMP nativo.
- El RTT se toma de la salida de `ping`; si el idioma no coincide con el patrón,
  se usa el tiempo total del proceso como aproximación.
- La tabla ARP puede tardar en poblarse tras el ping; algunos equipos aparecen
  como "Solo ARP" en el primer escaneo.
- En Linux, `ip neigh` es la fuente principal; si no existe, se usa `arp -an`.
- `syn` no está cubierto por la suite si `scapy` no está instalado.
- No se portaron alertas, lista blanca, vigilancia, HTML ni presencia histórica.

## Seguridad y datos

- `config.json`, los reportes, los CSV y el estado están en `.gitignore`: pueden
  contener IPs, MACs y nombres de tu red.
- No subas reportes ni configuraciones con secretos al repositorio.
- La caché OUI solo guarda el prefijo de 6 caracteres y el nombre del fabricante.

## Versión PowerShell (legacy)

```powershell
powershell -ExecutionPolicy Bypass -File .\legacy\scan-red.ps1 -Red 192.168.1
```

Consulta [`legacy/README.md`](legacy/README.md) para alertas, lista blanca,
vigilancia, HTML y configuración. El estado `estado-anterior.json` es compatible
entre ambas versiones.

## Aviso legal

Scan-Red está pensado para auditorías de redes propias o expresamente
autorizadas. Escanear redes de terceros sin permiso puede ser ilegal y está
fuera del propósito de este proyecto. El uso de `--puertos` no cambia esa
responsabilidad: el flag `--autorizado` confirma que tienes autorización.
