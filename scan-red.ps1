<#
.SYNOPSIS
    Escanea la red local (ping sweep), identifica dispositivos por IP, MAC, nombre y fabricante,
    detecta dispositivos nuevos/desaparecidos respecto al escaneo anterior y guarda todo en
    una carpeta de reportes centralizada.

.DESCRIPTION
    Fase 1: lanza pings en paralelo a todo el rango (por defecto 192.168.1.1 - 192.168.1.254).
    Fase 2: lee la tabla ARP/vecinos para obtener las direcciones MAC.
    Fase 3: resuelve nombres por DNS inverso (y opcionalmente NetBIOS con -NetBios).
    Fase 4: consulta el fabricante por MAC (OUI) usando internet + cache local.
    Fase 5: compara con el escaneo anterior: marca NUEVO / Conocido / Desaparecido.
    Fase 6: muestra la tabla, guarda el CSV y actualiza el historial.

.PARAMETER Red
    Prefijo de red sin el ultimo octeto. Ej: 192.168.1

.PARAMETER TimeoutMs
    Milisegundos de espera por cada ping. Por defecto 800.

.PARAMETER Inicio / Fin
    Rango del ultimo octeto. Por defecto 1 a 254.

.PARAMETER Carpeta
    Carpeta donde se guardan los CSV y el historial. Por defecto: C:\Users\<usuario>\Reportes-Red

.PARAMETER Csv
    Ruta o nombre del CSV de salida. Si no se indica, se genera con fecha/hora dentro de -Carpeta.

.PARAMETER SinCsv
    No genera archivo CSV (el historial si se actualiza).

.PARAMETER NetBios
    Intenta resolver nombres con nbtstat cuando el DNS inverso falla (mas lento).

.PARAMETER SinFabricante
    No consulta el fabricante por MAC (OUI). Util si no hay internet.

.PARAMETER SinHistorial
    No lee ni actualiza el historial (no detecta nuevos/desaparecidos).

.EXAMPLE
    .\scan-red.ps1
    .\scan-red.ps1 -Red 192.168.0
    .\scan-red.ps1 -Carpeta D:\Reportes -Csv red-casa.csv
    .\scan-red.ps1 -SinFabricante -NetBios
#>
[CmdletBinding()]
param(
    [string]$Red = "192.168.1",
    [int]$TimeoutMs = 800,
    [int]$Inicio = 1,
    [int]$Fin = 254,
    [string]$Carpeta = (Join-Path $HOME 'Reportes-Red'),
    [string]$Csv,
    [switch]$SinCsv,
    [switch]$NetBios,
    [switch]$SinFabricante,
    [switch]$SinHistorial
)

$ErrorActionPreference = 'SilentlyContinue'

# PowerShell 5.1 necesita TLS 1.2 explicito para las consultas HTTPS
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ------------------------------------------------------------------
# Carpeta de reportes
# ------------------------------------------------------------------
if (-not (Test-Path $Carpeta)) {
    New-Item -ItemType Directory -Path $Carpeta -Force | Out-Null
}

$rutaEstado = Join-Path $Carpeta 'estado-anterior.json'
$estadoAnterior = @{}
$hayHistorial = $false

if (-not $SinHistorial -and (Test-Path $rutaEstado)) {
    try {
        (Get-Content $rutaEstado -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $estadoAnterior[$_.Name] = $_.Value }
        $hayHistorial = $true
    }
    catch { $estadoAnterior = @{} }
}

# Cache de fabricantes (OUI): evita repetir consultas a internet
$rutaCacheOui = Join-Path $HOME '.scan-red-oui-cache.json'
$cacheOui = @{}
if (Test-Path $rutaCacheOui) {
    try {
        (Get-Content $rutaCacheOui -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $cacheOui[$_.Name] = $_.Value }
    }
    catch { $cacheOui = @{} }
}

# ------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------
function Resolve-NombreDns {
    param([string]$Ip, [int]$EsperaMs = 1500)
    try {
        $tarea = [System.Net.Dns]::GetHostEntryAsync($Ip)
        if ($tarea.Wait($EsperaMs)) {
            $entrada = $tarea.Result
            if ($entrada -and $entrada.HostName) {
                return ($entrada.HostName -split '\.')[0]
            }
        }
    }
    catch { }
    return $null
}

function Resolve-NombreNetBios {
    param([string]$Ip)
    try {
        $salida = & nbtstat -A $Ip 2>$null
        foreach ($linea in $salida) {
            if ($linea -match '^\s*(\S+)\s+<00>\s+UNIQUE') {
                return $Matches[1]
            }
        }
    }
    catch { }
    return $null
}

function Get-Fabricante {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return '' }

    # Se consulta por el prefijo OUI (primeros 3 octetos = 6 hex)
    $oui = ($Mac -replace '-', '').ToUpper()
    if ($oui.Length -lt 6) { return '' }
    $oui = $oui.Substring(0, 6)

    if ($cacheOui.ContainsKey($oui)) { return $cacheOui[$oui] }

    $fabricante = ''

    # Fuente 1: api.macvendors.com (respuesta en texto plano)
    try {
        $r = Invoke-RestMethod -Uri "https://api.macvendors.com/$oui" -TimeoutSec 8 `
            -Headers @{ 'User-Agent' = 'scan-red-ps/1.0' }
        if ($r) { $fabricante = "$r".Trim() }
    }
    catch { }

    # Fuente 2 (respaldo): api.maclookup.app
    if (-not $fabricante) {
        try {
            $r2 = Invoke-RestMethod -Uri "https://api.maclookup.app/v2/macs/$oui" -TimeoutSec 8
            if ($r2.found -and $r2.company) { $fabricante = $r2.company }
        }
        catch { }
    }

    if (-not $fabricante) { $fabricante = 'Desconocido' }

    $cacheOui[$oui] = $fabricante
    Start-Sleep -Milliseconds 1100   # respeta el limite ~1 consulta/segundo del servicio
    return $fabricante
}

# ------------------------------------------------------------------
# Fase 1: ping sweep en paralelo
# ------------------------------------------------------------------
Write-Host ""
Write-Host ("  Escaneando {0}.{1} - {0}.{2} ..." -f $Red, $Inicio, $Fin) -ForegroundColor Cyan
Write-Host ""

$inicioTiempo = Get-Date
$msPorIp = @{}

$tareas = foreach ($n in $Inicio..$Fin) {
    $ip = "$Red.$n"
    $ping = [System.Net.NetworkInformation.Ping]::new()
    [pscustomobject]@{
        IP    = $ip
        Ping  = $ping
        Tarea = $ping.SendPingAsync($ip, $TimeoutMs)
    }
}

foreach ($t in $tareas) {
    try {
        $resp = $t.Tarea.GetAwaiter().GetResult()
        if ($resp.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $msPorIp[$t.IP] = [int]$resp.RoundtripTime
        }
    }
    catch { }
    finally { $t.Ping.Dispose() }
}

# ------------------------------------------------------------------
# Fase 2: tabla ARP / vecinos -> MAC por IP
# ------------------------------------------------------------------
$macPorIp = @{}

if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -like "$Red.*" -and
            $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and
            $_.LinkLayerAddress -ne 'FF-FF-FF-FF-FF-FF' -and
            $_.State -in @('Reachable', 'Stale', 'Delay', 'Probe', 'Permanent')
        } |
        ForEach-Object { $macPorIp[$_.IPAddress] = $_.LinkLayerAddress.ToUpper() }
}
else {
    foreach ($linea in (arp -a)) {
        if ($linea -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:-[0-9a-fA-F]{2}){5})') {
            $macPorIp[$Matches[1]] = $Matches[2].ToUpper()
        }
    }
}

# ------------------------------------------------------------------
# Fase 3: unir ping + ARP en una sola lista
# ------------------------------------------------------------------
$todasLasIp = ($msPorIp.Keys + $macPorIp.Keys) | Sort-Object -Unique | Sort-Object { [version]$_ }

$filas = @(foreach ($ip in $todasLasIp) {
    [pscustomobject]@{
        IP         = $ip
        MAC        = if ($macPorIp.ContainsKey($ip)) { $macPorIp[$ip] } else { '' }
        Nombre     = ''
        Fabricante = ''
        Estado     = if ($msPorIp.ContainsKey($ip)) { 'Activo' } else { 'Solo ARP' }
        Ms         = if ($msPorIp.ContainsKey($ip)) { $msPorIp[$ip] } else { $null }
        Clave      = ''
        Cambio     = ''
        PrimeraVez = ''
        UltimoVisto= ''
    }
})

# ------------------------------------------------------------------
# Fase 4: resolver nombres (DNS inverso en paralelo + NetBIOS opcional)
# ------------------------------------------------------------------
$tareasDns = @{}
foreach ($fila in $filas) {
    try { $tareasDns[$fila.IP] = [System.Net.Dns]::GetHostEntryAsync($fila.IP) } catch { }
}

foreach ($fila in $filas) {
    $nombre = $null
    if ($tareasDns.ContainsKey($fila.IP)) {
        try {
            if ($tareasDns[$fila.IP].Wait(1500)) {
                $entrada = $tareasDns[$fila.IP].Result
                if ($entrada -and $entrada.HostName) { $nombre = ($entrada.HostName -split '\.')[0] }
            }
        }
        catch { }
    }
    if (-not $nombre -and $NetBios) {
        $nombre = Resolve-NombreNetBios -Ip $fila.IP
    }
    if ($nombre) { $fila.Nombre = $nombre }
}

# ------------------------------------------------------------------
# Fase 4b: fabricante por MAC (OUI) con cache local
# ------------------------------------------------------------------
if (-not $SinFabricante) {
    $conMac = @($filas | Where-Object { $_.MAC })
    $pendientes = @($conMac | Where-Object { -not $cacheOui.ContainsKey((($_.MAC -replace '-', '').Substring(0, 6))) })

    if ($pendientes.Count -gt 0) {
        Write-Host ("  Consultando fabricantes ({0} nuevos, ~{1} s) ..." -f `
                $pendientes.Count, [math]::Round($pendientes.Count * 1.1)) -ForegroundColor DarkGray
    }

    foreach ($fila in $filas) {
        if ($fila.MAC) { $fila.Fabricante = Get-Fabricante -Mac $fila.MAC }
    }

    try { $cacheOui | ConvertTo-Json | Set-Content -Path $rutaCacheOui -Encoding UTF8 } catch { }
}

# ------------------------------------------------------------------
# Fase 5: comparar con el escaneo anterior (nuevos / desaparecidos)
# ------------------------------------------------------------------
$ahora = Get-Date
$ahoraTexto = $ahora.ToString('yyyy-MM-dd HH:mm:ss')
$clavesActuales = @{}
$nuevos = [System.Collections.Generic.List[object]]::new()
$cambiosIp = [System.Collections.Generic.List[object]]::new()
$estadoNuevo = @{}

# Clave estable por dispositivo: la MAC; si no hay MAC, la IP
foreach ($fila in $filas) {
    $fila.Clave = if ($fila.MAC) { $fila.MAC } else { "IP:$($fila.IP)" }
    $fila.UltimoVisto = $ahoraTexto
}

# Agrupar por dispositivo (una misma MAC puede tener mas de una IP)
foreach ($grupo in ($filas | Group-Object Clave)) {
    $clave = $grupo.Name
    $ipsActuales = @($grupo.Group | ForEach-Object { $_.IP } | Sort-Object { [version]$_ })
    $primeraVez = $ahoraTexto
    $cambio = 'NUEVO'

    if ($estadoAnterior.ContainsKey($clave)) {
        $cambio = 'Conocido'
        $primeraVez = [string]$estadoAnterior[$clave].PrimeraVez

        # Compatibilidad con el formato antiguo (IP suelta) y el nuevo (IPs)
        $ipsAntes = @()
        if ($estadoAnterior[$clave].IPs) { $ipsAntes = @($estadoAnterior[$clave].IPs) }
        elseif ($estadoAnterior[$clave].IP) { $ipsAntes = @($estadoAnterior[$clave].IP) }

        $ipsNuevas = @($ipsActuales | Where-Object { $_ -notin $ipsAntes })
        if ($ipsNuevas.Count -gt 0) {
            $cambiosIp.Add([pscustomobject]@{
                    Antes      = ($ipsAntes -join ', ')
                    Ahora      = ($ipsActuales -join ', ')
                    Fabricante = $grupo.Group[0].Fabricante
                })
        }
    }
    else {
        $nuevos.Add($grupo.Group[0])
    }

    foreach ($f in $grupo.Group) {
        $f.Cambio = $cambio
        $f.PrimeraVez = $primeraVez
    }

    $clavesActuales[$clave] = $true

    $nombreGrupo = ($grupo.Group | Where-Object { $_.Nombre } | Select-Object -First 1).Nombre
    if (-not $nombreGrupo) { $nombreGrupo = '' }

    $estadoNuevo[$clave] = [pscustomobject]@{
        IPs        = $ipsActuales
        MAC        = $grupo.Group[0].MAC
        Nombre     = $nombreGrupo
        Fabricante = $grupo.Group[0].Fabricante
        PrimeraVez = $primeraVez
        UltimoVisto= $ahoraTexto
    }
}

$desaparecidos = @(foreach ($k in $estadoAnterior.Keys) {
        if (-not $clavesActuales.ContainsKey($k)) {
            $ipsAntes = if ($estadoAnterior[$k].IPs) { (@($estadoAnterior[$k].IPs) -join ', ') } else { $estadoAnterior[$k].IP }
            [pscustomobject]@{
                IP         = $ipsAntes
                MAC        = $estadoAnterior[$k].MAC
                Nombre     = $estadoAnterior[$k].Nombre
                Fabricante = $estadoAnterior[$k].Fabricante
                UltimoVisto= $estadoAnterior[$k].UltimoVisto
            }
        }
    })

$duracion = (Get-Date) - $inicioTiempo
$activos = @($filas | Where-Object { $_.Estado -eq 'Activo' })

# ------------------------------------------------------------------
# Fase 6: mostrar resultados
# ------------------------------------------------------------------
Write-Host ""
Write-Host ("  Equipo: {0}" -f [System.Net.Dns]::GetHostName()) -ForegroundColor DarkGray
Write-Host ("  Activos: {0}   |   En tabla ARP: {1}   |   Tiempo: {2:N1} s" -f `
        $activos.Count, $filas.Count, $duracion.TotalSeconds) -ForegroundColor Yellow

if ($hayHistorial) {
    Write-Host ("  Nuevos: {0}   |   Desaparecidos: {1}" -f $nuevos.Count, $desaparecidos.Count) -ForegroundColor Yellow
}
elseif (-not $SinHistorial) {
    Write-Host "  Primera ejecucion con historial: se creo la linea base." -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "  Dispositivos encontrados:" -ForegroundColor Cyan
$filas |
    Select-Object IP, MAC, Nombre, Fabricante, Estado, Cambio, Ms |
    Format-Table -AutoSize |
    Out-Host

# Alertas
if ($hayHistorial -and $nuevos.Count -gt 0) {
    Write-Host "  [!] DISPOSITIVOS NUEVOS (no estaban en el escaneo anterior):" -ForegroundColor Yellow
    foreach ($n in $nuevos) {
        Write-Host ("      {0,-15} {1,-18} {2}" -f $n.IP, $n.MAC, $n.Fabricante) -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($hayHistorial -and $desaparecidos.Count -gt 0) {
    Write-Host "  [i] DESAPARECIDOS (estaban antes y ya no aparecen):" -ForegroundColor DarkYellow
    foreach ($d in $desaparecidos) {
        Write-Host ("      {0,-15} {1,-18} {2}  (visto: {3})" -f `
                $d.IP, $d.MAC, $d.Fabricante, $d.UltimoVisto) -ForegroundColor DarkYellow
    }
    Write-Host ""
}

if ($hayHistorial -and $cambiosIp.Count -gt 0) {
    Write-Host "  [i] Cambios de IP del mismo dispositivo:" -ForegroundColor DarkCyan
    foreach ($c in $cambiosIp) {
        Write-Host ("      {0} -> {1}   {2}" -f $c.Antes, $c.IP, $c.Fabricante) -ForegroundColor DarkCyan
    }
    Write-Host ""
}

# ------------------------------------------------------------------
# Fase 7: exportar CSV + guardar historial
# ------------------------------------------------------------------
if (-not $SinCsv) {
    $ruta = $Csv
    if (-not $ruta) {
        $ruta = Join-Path $Carpeta ("scan-red-{0:yyyyMMdd-HHmmss}.csv" -f $ahora)
    }
    elseif (-not [System.IO.Path]::IsPathRooted($ruta)) {
        $ruta = Join-Path $Carpeta $ruta
    }
    elseif (Test-Path $ruta -PathType Container) {
        $ruta = Join-Path $ruta ("scan-red-{0:yyyyMMdd-HHmmss}.csv" -f $ahora)
    }

    $filas | Select-Object IP, MAC, Nombre, Fabricante, Estado, Ms, PrimeraVez, UltimoVisto, Cambio |
        Export-Csv -Path $ruta -NoTypeInformation -Encoding UTF8

    Write-Host ("  Reporte guardado en: {0}" -f $ruta) -ForegroundColor Green
}

if (-not $SinHistorial) {
    try {
        $estadoNuevo | ConvertTo-Json -Depth 5 | Set-Content -Path $rutaEstado -Encoding UTF8
        Write-Host ("  Historial actualizado: {0}" -f $rutaEstado) -ForegroundColor DarkGray
    }
    catch { }
}
Write-Host ""
