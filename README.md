# Scan-Red

Escáner de red local para Windows (PowerShell). Hace un *ping sweep* al rango indicado, identifica cada dispositivo por **IP, MAC, nombre y fabricante**, detecta **dispositivos nuevos o desaparecidos** respecto al escaneo anterior y guarda un **CSV** (compatible con Excel) en una carpeta de reportes.

## Requisitos

- Windows 8 / 10 / 11 o Windows Server 2012+
- Windows PowerShell 5.1 o PowerShell 7+
- Conexión a internet **opcional** (solo para resolver el fabricante por MAC)

## Uso rápido

```powershell
powershell -ExecutionPolicy Bypass -File .\scan-red.ps1
```

Eso escanea `192.168.1.1 - 192.168.1.254`, muestra la tabla y guarda el CSV en:

```
C:\Users\<usuario>\Reportes-Red\
```

## Ejemplos

```powershell
# Rango y subred distintos
.\scan-red.ps1 -Red 192.168.0 -Inicio 1 -Fin 100

# Elegir carpeta de reportes
.\scan-red.ps1 -Carpeta "D:\Reportes"

# Nombre de archivo específico
.\scan-red.ps1 -Csv "red-casa.csv"

# Sin internet (omite la consulta de fabricantes)
.\scan-red.ps1 -SinFabricante

# Sin historial (no detecta nuevos/desaparecidos)
.\scan-red.ps1 -SinHistorial

# Forzar nombres por NetBIOS cuando el DNS inverso falla
.\scan-red.ps1 -NetBios
```

## Parámetros

| Parámetro | Por defecto | Descripción |
|-----------|-------------|-------------|
| `-Red` | `192.168.1` | Prefijo de red sin el último octeto. |
| `-TimeoutMs` | `800` | Milisegundos de espera por ping. |
| `-Inicio` / `-Fin` | `1` / `254` | Rango del último octeto. |
| `-Carpeta` | `$HOME\Reportes-Red` | Carpeta de CSV e historial. |
| `-Csv` | *(automático)* | Nombre o ruta del CSV de salida. |
| `-SinCsv` | — | No genera CSV. |
| `-SinHistorial` | — | No lee ni actualiza el historial. |
| `-SinFabricante` | — | No consulta fabricantes (OUI). |
| `-NetBios` | — | Intenta resolver nombres con `nbtstat`. |

## Cómo funciona

1. **Ping sweep en paralelo**: lanza los 254 pings de forma asíncrona (tarda ~1 s en vez de minutos).
2. **Tabla ARP**: obtiene la MAC de cada IP con `Get-NetNeighbor` (o `arp -a` como respaldo).
3. **Nombres**: DNS inverso en paralelo; NetBIOS opcional.
4. **Fabricante**: consulta el prefijo OUI en `api.macvendors.com` (respaldo: `api.maclookup.app`) con caché local y límite de ~1 consulta/segundo.
5. **Historial**: compara con `estado-anterior.json` y marca `NUEVO` / `Conocido`, además de listar desaparecidos y cambios de IP.
6. **Salida**: tabla en consola + CSV UTF-8.

## Columnas del CSV

| Columna | Descripción |
|---------|-------------|
| `IP` | Dirección IPv4 del dispositivo. |
| `MAC` | Dirección física (identificador estable). |
| `Nombre` | Nombre resuelto por DNS/NetBIOS (si existe). |
| `Fabricante` | Fabricante según el prefijo OUI de la MAC. |
| `Estado` | `Activo` (responde ping) o `Solo ARP` (en la red pero no responde ping). |
| `Ms` | Tiempo de respuesta del ping. |
| `PrimeraVez` | Primer avistamiento registrado. |
| `UltimoVisto` | Último escaneo en que apareció. |
| `Cambio` | `NUEVO` o `Conocido`. |

## Archivos generados (no se suben al repo)

- `Reportes-Red/*.csv`: reportes de cada ejecución.
- `Reportes-Red/estado-anterior.json`: historial de dispositivos.
- `.scan-red-oui-cache.json`: caché de fabricantes.

Están excluidos en `.gitignore` porque contienen datos privados de tu red (IPs y MACs).

## Limitaciones

- Un dispositivo puede **bloquear el ping** y aun así estar en la red: aparecerá como `Solo ARP`.
- Los equipos con **MAC aleatoria** (celulares modernos con privacidad) pueden aparecer como `NUEVO` cada cierto tiempo, porque rotan su MAC.
- Las entradas ARP pueden tardar un poco en expirar, por lo que un dispositivo desconectado puede seguir apareciendo como desaparecido más tarde.
- Algunas redes aíslan clientes (AP isolation) y el escaneo no verá esos equipos.

## Aviso de uso

Usa esta herramienta **solo en redes que administres o para las que tengas autorización explícita**. Escanear redes ajenas sin permiso puede ser ilegal.
