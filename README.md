# Scan-Red

Escáner de red local para Windows (PowerShell). Descubre dispositivos por **IP, MAC, nombre y fabricante**, escanea **puertos TCP**, detecta **dispositivos nuevos, desaparecidos y cambios de IP**, calcula la **presencia histórica**, genera reportes **CSV/HTML** y envía **alertas** (toast de Windows, Telegram y/o email).

## Características

- **Descubrimiento rápido**: ping sweep asíncrono (los 254 hosts en ~1 segundo) + tabla ARP.
- **Identificación**: DNS inverso, NetBIOS opcional y fabricante por prefijo OUI (con caché local).
- **Puertos TCP**: escaneo paralelo de los puertos que definas, con nombre de servicio.
- **Lista blanca**: marca tus equipos conocidos como autorizados.
- **Detección de cambios**: `NUEVO` / `Conocido`, desaparecidos y cambios de IP (usando la MAC como identidad).
- **Historial y presencia**: porcentaje de escaneos en los que apareció cada dispositivo.
- **Modo vigilancia**: repite el escaneo cada N segundos y solo reporta cambios.
- **Alertas**: toast de Windows, Telegram y email, con registro en `alertas.log`.
- **Reportes**: CSV (Excel) y HTML autocontenido, sin dependencias externas.

## Requisitos

- Windows 8 / 10 / 11 o Windows Server 2012+
- Windows PowerShell 5.1 o PowerShell 7+
- Internet **opcional** (solo para resolver fabricantes y enviar Telegram/email)

No requiere módulos externos: usa solo PowerShell y .NET.

## Instalación

```powershell
git clone https://github.com/bydavidp/Scan-Red.git
cd Scan-Red
```

## Uso rápido

```powershell
powershell -ExecutionPolicy Bypass -File .\scan-red.ps1
```

Eso escanea `192.168.1.1 - 192.168.1.254`, muestra la tabla y guarda los reportes en:

```
C:\Users\<usuario>\Reportes-Red\
```

## Configuración

Copia el ejemplo y ajústalo:

```powershell
Copy-Item config.example.json config.json
```

`config.json` **no se sube al repositorio** (puede contener secretos). Precedencia:

```
valores por defecto  <  config.json  <  parámetros de la línea de comandos
```

Ejemplo de configuración:

```json
{
  "Red": "192.168.1",
  "Inicio": 1,
  "Fin": 254,
  "CarpetaReportes": "Reportes-Red",
  "GenerarCsv": true,
  "GenerarHtml": true,
  "GuardarHistorial": true,
  "CompararEstado": true,
  "UsarFabricantes": true,
  "EscanearPuertos": true,
  "Puertos": [22, 80, 443, 554, 3389, 8000, 8080, 8443, 37777],
  "TimeoutPuertoMs": 250,
  "Vigilar": false,
  "Intervalo": 300,
  "Veces": 0,
  "ListaBlanca": ["AA-BB-CC-DD-EE-FF"],
  "IgnorarMacAleatoria": true,
  "Notificaciones": {
    "Toast": true,
    "SoloNoAutorizados": true,
    "Telegram": {
      "Activo": false,
      "BotToken": "",
      "BotTokenEnv": "SCANRED_TELEGRAM_TOKEN",
      "ChatId": ""
    },
    "Email": {
      "Activo": false,
      "Servidor": "smtp.gmail.com",
      "Puerto": 587,
      "UsarSsl": true,
      "Usuario": "tu-correo@gmail.com",
      "Password": "",
      "PasswordEnv": "SCANRED_SMTP_PASS",
      "Para": "tu-correo@gmail.com"
    }
  }
}
```

## Parámetros

| Parámetro | Descripción |
|-----------|-------------|
| `-Config <ruta>` | Archivo de configuración (por defecto `config.json`). |
| `-Red <prefijo>` | Red sin el último octeto. Ej: `192.168.1`. |
| `-TimeoutMs <ms>` | Espera por ping (por defecto 800). |
| `-Inicio` / `-Fin` | Rango del último octeto (1 a 254). |
| `-Carpeta <ruta>` | Carpeta de reportes. |
| `-Csv <ruta>` / `-Html <ruta>` | Nombre o ruta de los reportes (relativo = dentro de `-Carpeta`). |
| `-SinCsv` / `-SinHtml` | No generar ese reporte. |
| `-SinHistorial` | No guardar historial acumulado. |
| `-SinEstado` | No comparar con el escaneo anterior (sin nuevos/desaparecidos). |
| `-SinFabricante` | No consultar fabricantes (funciona sin internet). |
| `-SinNombres` | No resolver nombres. |
| `-NetBios` | Intentar nombres por NetBIOS cuando el DNS inverso falla. |
| `-EscanearPuertos` / `-SinPuertos` | Activar/desactivar el escaneo de puertos. |
| `-Puertos 22,80,443` | Puertos TCP a escanear. |
| `-TimeoutPuertoMs <ms>` | Espera por conexión TCP. |
| `-Vigilar` | Modo continuo. |
| `-Intervalo <seg>` | Segundos entre escaneos (mínimo 10). |
| `-Veces <n>` | Número de escaneos antes de salir (0 = infinito). |
| `-Autorizar <MAC>` | Agrega una o varias MAC a la lista blanca y sale. |
| `-ResumenHistorial` | Muestra el resumen de presencia histórica y sale. |

### Ejemplos

```powershell
# Escaneo normal
.\scan-red.ps1

# Otra red y rango
.\scan-red.ps1 -Red 192.168.0 -Inicio 1 -Fin 100

# Vigilancia cada 5 minutos
.\scan-red.ps1 -Vigilar -Intervalo 300

# Vigilancia limitada a 3 escaneos (útil para probar)
.\scan-red.ps1 -Vigilar -Veces 3 -Intervalo 15

# Autorizar un dispositivo por su MAC
.\scan-red.ps1 -Autorizar 74-A7-EA-30-75-3F

# Ver presencia histórica
.\scan-red.ps1 -ResumenHistorial

# Sin internet y sin puertos
.\scan-red.ps1 -SinFabricante -SinPuertos
```

## Lista blanca

```powershell
.\scan-red.ps1 -Autorizar AA-BB-CC-DD-EE-FF
```

- La MAC se normaliza (`aabbccddeeff` → `AA-BB-CC-DD-EE-FF`).
- Se guarda en `config.json` → `ListaBlanca`.
- Los equipos autorizados aparecen como `Autorizado = Si`.
- Con `SoloNoAutorizados: true`, solo se alerta de los **no** autorizados.
- Los equipos con **MAC aleatoria** (bit localmente administrado) se pueden ignorar con `IgnorarMacAleatoria: true`.

## Notificaciones

### Toast de Windows

Activado por defecto (`"Toast": true`). No requiere configuración adicional.

### Telegram

1. Crea un bot con [@BotFather](https://t.me/BotFather) y copia el **token**.
2. Envía un mensaje al bot (para que exista el chat).
3. Obtén el `chat_id`:

```powershell
Invoke-RestMethod "https://api.telegram.org/bot<TU_TOKEN>/getUpdates" |
    Select-Object -ExpandProperty result |
    Select-Object -ExpandProperty message |
    Select-Object -ExpandProperty chat
```

4. Configura `ChatId` y el token:

```powershell
# Recomendado: variable de entorno (no queda en config.json)
$env:SCANRED_TELEGRAM_TOKEN = "123456:ABC..."
```

O escríbelo en `Notificaciones.Telegram.BotToken` y pon `"Activo": true`.

### Email

```json
"Email": {
  "Activo": true,
  "Servidor": "smtp.gmail.com",
  "Puerto": 587,
  "UsarSsl": true,
  "Usuario": "tu-correo@gmail.com",
  "Password": "",
  "PasswordEnv": "SCANRED_SMTP_PASS",
  "Para": "tu-correo@gmail.com"
}
```

```powershell
$env:SCANRED_SMTP_PASS = "tu-password-de-aplicacion"
```

Para Gmail necesitas una **contraseña de aplicación** (con verificación en dos pasos activa).

Todas las alertas se registran además en `Reportes-Red/alertas.log`.

## Modo vigilancia

```powershell
.\scan-red.ps1 -Vigilar -Intervalo 300
```

- El **primer** escaneo muestra la tabla completa.
- Los siguientes solo muestran **cambios**.
- En modo vigilancia, los CSV/HTML solo se generan cuando hay cambios (para no llenar la carpeta).
- El historial acumulado sí se actualiza en cada vuelta.
- Detén con `Ctrl+C`.

## Escaneo de puertos

Usa conexiones TCP (sin privilegios de administrador). Puertos comunes reconocidos:

| Puerto | Servicio |
|--------|----------|
| 21 | FTP |
| 22 | SSH |
| 80 / 8080 | HTTP |
| 443 / 8443 | HTTPS |
| 554 / 8554 | RTSP (cámaras) |
| 139 / 445 | NetBIOS / SMB |
| 3389 | RDP |
| 37777 | Dahua |
| 34567 | DVR |
| 9100 | Impresora |

El escaneo es **paralelo** y con timeout corto (250 ms por defecto), así que no frena el escaneo principal.

## Reportes y archivos generados

Todo se guarda en la carpeta de reportes (`C:\Users\<usuario>\Reportes-Red` por defecto):

| Archivo | Contenido |
|---------|-----------|
| `scan-red-AAAAMMDD-HHMMSS.csv` | Reporte de la ejecución (Excel). |
| `reporte-AAAAMMDD-HHMMSS.html` | Reporte visual autocontenido. |
| `historial.csv` | Historial acumulado (una fila por dispositivo y escaneo). |
| `historial-resumen.json` | Estadísticas de presencia. |
| `estado-anterior.json` | Estado del último escaneo (para comparar). |
| `alertas.log` | Registro de alertas enviadas. |
| `config.json` | Configuración local (en la carpeta del script). |
| `.scan-red-oui-cache.json` | Caché de fabricantes (en el perfil del usuario). |

### Columnas del CSV

| Columna | Descripción |
|---------|-------------|
| `IP` | Dirección IPv4. |
| `MAC` | Dirección física (identidad estable). |
| `Nombre` | Nombre por DNS/NetBIOS, si existe. |
| `Fabricante` | Fabricante según el prefijo OUI. |
| `Autorizado` | `Si`, `No` o `-` (sin MAC). |
| `MacAleatoria` | `Si` si la MAC es localmente administrada/aleatoria. |
| `PuertosTexto` | Puertos abiertos con su servicio. |
| `Estado` | `Activo` (responde ping) o `Solo ARP`. |
| `Ms` | Tiempo de respuesta del ping. |
| `Cambio` | `NUEVO` o `Conocido`. |
| `PrimeraVez` | Primer avistamiento. |
| `UltimoVisto` | Último escaneo en que apareció. |
| `Presencia` | Porcentaje de escaneos en que apareció (0-100). |

## Presencia histórica

```powershell
.\scan-red.ps1 -ResumenHistorial
```

Muestra cada dispositivo con:

- **Presencia**: % de escaneos en que apareció.
- **Veces**: número de escaneos en que se vio.
- **PrimeraVez** / **UltimoVisto**: fechas.

La presencia es una **aproximación** basada en escaneos, no un uptime real.

### Reiniciar el historial

```powershell
# Borrar solo las estadísticas de presencia
Remove-Item "$HOME\Reportes-Red\historial-resumen.json"

# Borrar también el historial detallado
Remove-Item "$HOME\Reportes-Red\historial.csv"

# Reiniciar la detección de cambios (la próxima corrida es línea base)
Remove-Item "$HOME\Reportes-Red\estado-anterior.json"
```

### Limpiar reportes

```powershell
Remove-Item "$HOME\Reportes-Red\scan-red-*.csv"
Remove-Item "$HOME\Reportes-Red\reporte-*.html"
```

## Cómo funciona

1. **Ping sweep** asíncrono a todo el rango.
2. **ARP** (`Get-NetNeighbor`, con respaldo a `arp -a`) para obtener MACs.
3. **Nombres**: DNS inverso en paralelo; NetBIOS opcional.
4. **Fabricante**: `api.macvendors.com` (respaldo `api.maclookup.app`), con caché y límite de ~1 consulta/segundo.
5. **Puertos**: conexiones TCP asíncronas en paralelo.
6. **Comparación**: agrupa por MAC, detecta nuevos, desaparecidos y cambios de IP.
7. **Historial**: acumula y calcula presencia.
8. **Salida**: consola + CSV + HTML + alertas.

## Limitaciones

- Un dispositivo puede **bloquear el ping** y aun así estar en la red: aparece como `Solo ARP`.
- Las **MAC aleatorias** (celulares modernos) rotan y pueden aparecer como `NUEVO` periódicamente; se pueden ignorar con `IgnorarMacAleatoria`.
- Las entradas ARP pueden tardar en expirar: un equipo desconectado puede tardar en marcarse como desaparecido.
- Redes con **AP isolation** pueden ocultar clientes entre sí.
- El escaneo de puertos es TCP connect: no detecta servicios solo UDP.
- Las notificaciones requieren que el script esté corriendo (no es un servicio de Windows).

## Seguridad

- `config.json` está en `.gitignore` porque puede contener el token de Telegram y la contraseña SMTP.
- Prefiere variables de entorno (`SCANRED_TELEGRAM_TOKEN`, `SCANRED_SMTP_PASS`) antes que texto plano.
- Los CSV, el historial y el estado también están ignorados: contienen IPs y MACs privadas.

## Aviso de uso

Usa esta herramienta **solo en redes que administres o para las que tengas autorización explícita**. Escanear redes ajenas sin permiso puede ser ilegal.
