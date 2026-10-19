<#
.SYNOPSIS
    Scan-Red: escaner de red local con alertas, historial y reportes.

.DESCRIPTION
    Descubre dispositivos de la red local (ping + ARP), resuelve nombre y fabricante,
    escanea puertos TCP, compara con el escaneo anterior (nuevos/desaparecidos/cambios
    de IP), calcula la presencia historica, genera reportes CSV/HTML y envia alertas
    (toast de Windows, Telegram y/o email).

.PARAMETER Config
    Ruta de config.json. Por defecto: config.json junto al script.

.PARAMETER Red
    Prefijo de red sin el ultimo octeto. Ej: 192.168.1

.PARAMETER TimeoutMs
    Milisegundos de espera por cada ping.

.PARAMETER Inicio / Fin
    Rango del ultimo octeto (por defecto 1 a 254).

.PARAMETER Carpeta
    Carpeta de reportes. Por defecto: $HOME\Reportes-Red

.PARAMETER Csv / Html
    Nombre o ruta del reporte. Si es relativo, se guarda en -Carpeta.

.PARAMETER Puertos
    Lista de puertos TCP a escanear. Ej: 22,80,443,554

.PARAMETER Vigilar
    Modo continuo: repite el escaneo cada -Intervalo segundos.

.PARAMETER Intervalo
    Segundos entre escaneos en modo vigilancia (minimo 10).

.PARAMETER Veces
    Numero de escaneos antes de salir (0 = infinito en modo vigilancia).

.PARAMETER Autorizar
    Agrega una o varias MAC a la lista blanca y sale.

.PARAMETER ResumenHistorial
    Muestra el resumen de presencia historica y sale.

.EXAMPLE
    .\scan-red.ps1

.EXAMPLE
    .\scan-red.ps1 -Vigilar -Intervalo 300

.EXAMPLE
    .\scan-red.ps1 -Autorizar 74-A7-EA-30-75-3F
#>
[CmdletBinding()]
param(
    [string]$Config,
    [string]$Red,
    [int]$TimeoutMs,
    [int]$Inicio,
    [int]$Fin,
    [string]$Carpeta,
    [string]$Csv,
    [string]$Html,
    [int[]]$Puertos,
    [int]$TimeoutPuertoMs,
    [int]$Intervalo,
    [int]$Veces,
    [string[]]$Autorizar,
    [switch]$EscanearPuertos,
    [switch]$SinPuertos,
    [switch]$Vigilar,
    [switch]$SinCsv,
    [switch]$SinHtml,
    [switch]$SinHistorial,
    [switch]$SinEstado,
    [switch]$SinFabricante,
    [switch]$SinNombres,
    [switch]$NetBios,
    [switch]$ResumenHistorial
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ------------------------------------------------------------------
# Cargar librerias
# ------------------------------------------------------------------
$raiz = $PSScriptRoot

foreach ($archivo in @('Common', 'Config', 'Discovery', 'Ports', 'History', 'Report', 'Notify')) {
    $rutaLib = Join-Path $raiz "lib\$archivo.ps1"
    if (Test-Path $rutaLib) {
        . $rutaLib
    }
    else {
        Write-Host ("  Falta el archivo requerido: {0}" -f $rutaLib) -ForegroundColor Red
        return
    }
}

# ------------------------------------------------------------------
# Configuracion (defaults < config.json < parametros de linea de comandos)
# ------------------------------------------------------------------
$rutaConfig = if ($Config) { $Config } else { Join-Path $raiz 'config.json' }

if ($Config -and -not (Test-Path $rutaConfig)) {
    Write-Host ("  No existe el archivo de configuracion: {0}" -f $rutaConfig) -ForegroundColor Red
    return
}

$cfg = Get-ScanConfig -Ruta $rutaConfig

if ($PSBoundParameters.ContainsKey('Red')) { $cfg.Red = $Red }
if ($PSBoundParameters.ContainsKey('TimeoutMs')) { $cfg.TimeoutMs = $TimeoutMs }
if ($PSBoundParameters.ContainsKey('Inicio')) { $cfg.Inicio = $Inicio }
if ($PSBoundParameters.ContainsKey('Fin')) { $cfg.Fin = $Fin }
if ($PSBoundParameters.ContainsKey('Carpeta')) { $cfg.CarpetaReportes = $Carpeta }
if ($PSBoundParameters.ContainsKey('Puertos')) { $cfg.Puertos = $Puertos }
if ($PSBoundParameters.ContainsKey('TimeoutPuertoMs')) { $cfg.TimeoutPuertoMs = $TimeoutPuertoMs }
if ($PSBoundParameters.ContainsKey('Intervalo')) { $cfg.Intervalo = $Intervalo }
if ($PSBoundParameters.ContainsKey('Veces')) { $cfg.Veces = $Veces }

if ($EscanearPuertos) { $cfg.EscanearPuertos = $true }
if ($SinPuertos) { $cfg.EscanearPuertos = $false }
if ($Vigilar) { $cfg.Vigilar = $true }
if ($SinCsv) { $cfg.GenerarCsv = $false }
if ($SinHtml) { $cfg.GenerarHtml = $false }
if ($SinHistorial) { $cfg.GuardarHistorial = $false }
if ($SinEstado) { $cfg.CompararEstado = $false }
if ($SinFabricante) { $cfg.UsarFabricantes = $false }

if ([int]$cfg.Intervalo -lt 10) { $cfg.Intervalo = 10 }
if ([int]$cfg.Veces -lt 0) { $cfg.Veces = 0 }

# ------------------------------------------------------------------
# Rutas de trabajo
# ------------------------------------------------------------------
$carpeta = Resolve-CarpetaReportes -Carpeta $cfg.CarpetaReportes

$rutaEstado = Join-Path $carpeta 'estado-anterior.json'
$rutaEstadisticas = Join-Path $carpeta 'historial-resumen.json'
$rutaHistorialCsv = Join-Path $carpeta 'historial.csv'
$rutaCacheOui = Join-Path $HOME '.scan-red-oui-cache.json'

$cacheOui = @{}
if (Test-Path $rutaCacheOui) {
    try {
        (Get-Content $rutaCacheOui -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $cacheOui[$_.Name] = $_.Value }
    }
    catch { $cacheOui = @{} }
}

function Resolve-RutaSalida {
    param(
        [string]$Ruta,
        [string]$Carpeta,
        [string]$Prefijo,
        [datetime]$Fecha,
        [string]$Extension
    )

    if (-not $Ruta) {
        return (Join-Path $Carpeta ("{0}-{1:yyyyMMdd-HHmmss}.{2}" -f $Prefijo, $Fecha, $Extension))
    }
    if (-not [System.IO.Path]::IsPathRooted($Ruta)) {
        return (Join-Path $Carpeta $Ruta)
    }
    if (Test-Path $Ruta -PathType Container) {
        return (Join-Path $Ruta ("{0}-{1:yyyyMMdd-HHmmss}.{2}" -f $Prefijo, $Fecha, $Extension))
    }
    return $Ruta
}

# ------------------------------------------------------------------
# Acciones rapidas: autorizar MACs / resumen de historial
# ------------------------------------------------------------------
if ($Autorizar) {
    $lista = @($cfg.ListaBlanca)
    $agregadas = @()
    $invalidas = 0

    foreach ($m in $Autorizar) {
        $normalizada = ConvertTo-MacNormalizada -Mac $m
        if ($normalizada -notmatch '^([0-9A-F]{2}-){5}[0-9A-F]{2}$') {
            $invalidas++
            Write-Host ("  MAC invalida (se ignora): {0}" -f $m) -ForegroundColor Yellow
            continue
        }
        if ($lista -notcontains $normalizada) {
            $lista += $normalizada
            $agregadas += $normalizada
        }
    }

    $cfg.ListaBlanca = $lista
    Save-ScanConfig -Config $cfg -Ruta $rutaConfig

    if ($agregadas.Count -gt 0) {
        Write-Host ("  MAC(s) autorizada(s): {0}" -f ($agregadas -join ', ')) -ForegroundColor Green
    }
    elseif ($invalidas -eq 0) {
        Write-Host "  Esas MAC(s) ya estaban autorizadas." -ForegroundColor Yellow
    }
    Write-Host ("  Configuracion guardada en: {0}" -f $rutaConfig) -ForegroundColor DarkGray
    return
}

if ($ResumenHistorial) {
    $stats = Read-Estadisticas -Ruta $rutaEstadisticas
    Write-Host ""
    Write-Host ("  Resumen historico ({0} escaneos)" -f $stats.Escaneos) -ForegroundColor Cyan
    Write-Host ""
    Show-ResumenHistorial -Estadisticas $stats
    Write-Host ""
    return
}

# ------------------------------------------------------------------
# Bucle principal
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  Scan-Red - escaner de red local" -ForegroundColor Cyan
Write-Host ("  Red: {0}.{1} - {0}.{2} | Reportes: {3}" -f $cfg.Red, $cfg.Inicio, $cfg.Fin, $carpeta) -ForegroundColor DarkGray
Write-Host ""

$iteracion = 0
$primeraVuelta = $true

do {
    $iteracion++
    $horaInicio = Get-Date
    $ahoraTexto = $horaInicio.ToString('yyyy-MM-dd HH:mm:ss')

    # Estado del escaneo anterior
    $estadoAnterior = @{}
    $hayEstado = $false
    if ($cfg.CompararEstado -and (Test-Path $rutaEstado)) {
        $estadoAnterior = Read-Estado -Ruta $rutaEstado
        $hayEstado = $true
    }

    Write-Host ("  [{0}] Escaneando..." -f $ahoraTexto) -ForegroundColor Cyan

    $filas = @(Get-Dispositivos -Opciones $cfg -CacheOui $cacheOui -SinNombres:$SinNombres -NetBios:$NetBios)

    # Autorizacion y MAC aleatoria
    foreach ($f in $filas) {
        if (-not $f.MAC) {
            $f.Autorizado = '-'
        }
        elseif (@($cfg.ListaBlanca) -contains $f.MAC) {
            $f.Autorizado = 'Si'
        }
        else {
            $f.Autorizado = 'No'
        }
        $f.MacAleatoria = Test-MacAleatoria -Mac $f.MAC
    }

    # Comparacion con el estado anterior (agrupando por MAC)
    $clavesActuales = @{}
    $nuevos = [System.Collections.Generic.List[object]]::new()
    $cambiosIp = [System.Collections.Generic.List[object]]::new()
    $estadoNuevo = @{}

    foreach ($f in $filas) {
        $f.Clave = if ($f.MAC) { $f.MAC } else { "IP:$($f.IP)" }
        $f.UltimoVisto = $ahoraTexto
    }

    foreach ($grupo in ($filas | Group-Object Clave)) {
        $clave = $grupo.Name
        $ipsActuales = @($grupo.Group | ForEach-Object { $_.IP } | Sort-Object { [version]$_ })
        $primeraVez = $ahoraTexto
        $cambio = 'NUEVO'

        if ($estadoAnterior.ContainsKey($clave)) {
            $cambio = 'Conocido'
            $primeraVez = [string]$estadoAnterior[$clave].PrimeraVez

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

    # Sin comparacion de estado no tiene sentido hablar de nuevos/desaparecidos
    if (-not $cfg.CompararEstado) {
        $nuevos.Clear()
        $cambiosIp.Clear()
        $desaparecidos = @()
        foreach ($f in $filas) { $f.Cambio = '-' }
    }

    # Historial y presencia
    if ($cfg.GuardarHistorial) {
        $stats = Read-Estadisticas -Ruta $rutaEstadisticas
        Update-Estadisticas -Estadisticas $stats -Filas $filas
        Save-Estadisticas -Estadisticas $stats -Ruta $rutaEstadisticas
        Add-Historial -Ruta $rutaHistorialCsv -Filas $filas -Fecha $ahoraTexto
    }

    $duracion = (Get-Date) - $horaInicio
    $activos = @($filas | Where-Object { $_.Estado -eq 'Activo' })
    $autorizados = @($filas | Where-Object { $_.Autorizado -eq 'Si' })

    # ------------------------------------------------------------------
    # Salida en consola
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host ("  Equipo: {0}" -f [System.Net.Dns]::GetHostName()) -ForegroundColor DarkGray
    Write-Host ("  Activos: {0} | En ARP: {1} | Autorizados: {2} | Nuevos: {3} | Desaparecidos: {4} | {5:N1} s" -f `
            $activos.Count, $filas.Count, $autorizados.Count, @($nuevos).Count, @($desaparecidos).Count, $duracion.TotalSeconds) -ForegroundColor Yellow

    if (-not $hayEstado -and $cfg.CompararEstado) {
        Write-Host "  Linea base creada (primer escaneo con estado)." -ForegroundColor DarkGray
    }
    Write-Host ""

    if ($primeraVuelta -or -not $cfg.Vigilar) {
        Show-TablaDispositivos -Filas $filas
        if ($cfg.CompararEstado) {
            Show-AlertasConsola -Nuevos $nuevos -Desaparecidos $desaparecidos -CambiosIp $cambiosIp
        }
    }
    else {
        Show-AlertasConsola -Nuevos $nuevos -Desaparecidos $desaparecidos -CambiosIp $cambiosIp
    }

    # ------------------------------------------------------------------
    # Notificaciones (solo si habia estado previo con el que comparar)
    # ------------------------------------------------------------------
    if ($hayEstado) {
        $alertados = Send-Alertas -Nuevos $nuevos -Cfg $cfg -Carpeta $carpeta
        if ($alertados -gt 0) {
            Write-Host ("  Alertas enviadas: {0}" -f $alertados) -ForegroundColor DarkGray
        }
    }

    # ------------------------------------------------------------------
    # Reportes (en modo vigilancia solo cuando hay cambios)
    # ------------------------------------------------------------------
    $huboCambios = (@($nuevos).Count -gt 0) -or (@($desaparecidos).Count -gt 0) -or (@($cambiosIp).Count -gt 0)
    $generar = (-not $cfg.Vigilar) -or $primeraVuelta -or $huboCambios

    if ($generar) {
        if ($cfg.GenerarCsv) {
            $rutaCsv = Resolve-RutaSalida -Ruta $Csv -Carpeta $carpeta -Prefijo 'scan-red' -Fecha $horaInicio -Extension 'csv'
            Export-CsvReporte -Filas $filas -Ruta $rutaCsv
            Write-Host ("  CSV : {0}" -f $rutaCsv) -ForegroundColor Green
        }

        if ($cfg.GenerarHtml) {
            $rutaHtml = Resolve-RutaSalida -Ruta $Html -Carpeta $carpeta -Prefijo 'reporte' -Fecha $horaInicio -Extension 'html'
            Export-HtmlReporte -Filas $filas -Nuevos $nuevos -Desaparecidos $desaparecidos -CambiosIp $cambiosIp `
                -Opciones $cfg -DuracionSeg $duracion.TotalSeconds -Ruta $rutaHtml -Equipo ([System.Net.Dns]::GetHostName())
            Write-Host ("  HTML: {0}" -f $rutaHtml) -ForegroundColor Green
        }
    }

    # ------------------------------------------------------------------
    # Persistir estado y cache
    # ------------------------------------------------------------------
    if ($cfg.CompararEstado) {
        Save-Estado -Estado $estadoNuevo -Ruta $rutaEstado
    }

    try {
        $cacheOui | ConvertTo-Json | Set-Content -Path $rutaCacheOui -Encoding UTF8
    }
    catch { }

    Write-Host ""

    $primeraVuelta = $false

    if (-not $cfg.Vigilar) { break }
    if ([int]$cfg.Veces -gt 0 -and $iteracion -ge [int]$cfg.Veces) { break }

    Write-Host ("  Proximo escaneo en {0} s (Ctrl+C para salir)." -f $cfg.Intervalo) -ForegroundColor DarkGray
    Start-Sleep -Seconds ([int]$cfg.Intervalo)
} while ($true)
