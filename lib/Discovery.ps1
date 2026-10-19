# Descubrimiento de dispositivos: ping, ARP, nombres y fabricantes.

function Invoke-PingSweep {
    param(
        [string]$Red,
        [int]$Inicio,
        [int]$Fin,
        [int]$TimeoutMs
    )

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

    return $msPorIp
}

function Get-MacPorIp {
    param([string]$Red)

    $macPorIp = @{}

    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -like "$Red.*" -and
                $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and
                $_.LinkLayerAddress -ne 'FF-FF-FF-FF-FF-FF' -and
                $_.State -in @('Reachable', 'Stale', 'Delay', 'Probe', 'Permanent')
            } |
            ForEach-Object { $macPorIp[$_.IPAddress] = (ConvertTo-MacNormalizada $_.LinkLayerAddress) }
    }
    else {
        foreach ($linea in (arp -a)) {
            if ($linea -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:-[0-9a-fA-F]{2}){5})') {
                $macPorIp[$Matches[1]] = (ConvertTo-MacNormalizada $Matches[2])
            }
        }
    }

    return $macPorIp
}

function Resolve-NombreHost {
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

function Resolve-Fabricante {
    param([string]$Mac, [hashtable]$Cache)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return '' }

    $oui = ($Mac -replace '-', '').ToUpper()
    if ($oui.Length -lt 6) { return '' }
    $oui = $oui.Substring(0, 6)

    if ($Cache.ContainsKey($oui)) { return $Cache[$oui] }

    $fabricante = ''

    try {
        $r = Invoke-RestMethod -Uri "https://api.macvendors.com/$oui" -TimeoutSec 8 `
            -Headers @{ 'User-Agent' = 'scan-red-ps/2.0' }
        if ($r) { $fabricante = "$r".Trim() }
    }
    catch { }

    if (-not $fabricante) {
        try {
            $r2 = Invoke-RestMethod -Uri "https://api.maclookup.app/v2/macs/$oui" -TimeoutSec 8
            if ($r2.found -and $r2.company) { $fabricante = $r2.company }
        }
        catch { }
    }

    if (-not $fabricante) { $fabricante = 'Desconocido' }

    $Cache[$oui] = $fabricante
    Start-Sleep -Milliseconds 1100
    return $fabricante
}

function Get-Dispositivos {
    param(
        $Opciones,
        [hashtable]$CacheOui,
        [switch]$SinNombres,
        [switch]$NetBios
    )

    $msPorIp = Invoke-PingSweep -Red $Opciones.Red -Inicio $Opciones.Inicio -Fin $Opciones.Fin -TimeoutMs $Opciones.TimeoutMs
    $macPorIp = Get-MacPorIp -Red $Opciones.Red

    $todas = ($msPorIp.Keys + $macPorIp.Keys) | Sort-Object -Unique | Sort-Object { [version]$_ }

    $filas = @(foreach ($ip in $todas) {
            [pscustomobject]@{
                IP           = $ip
                MAC          = if ($macPorIp.ContainsKey($ip)) { $macPorIp[$ip] } else { '' }
                Nombre       = ''
                Fabricante   = ''
                Autorizado   = '-'
                MacAleatoria = $false
                Puertos      = @()
                PuertosTexto = ''
                Estado       = if ($msPorIp.ContainsKey($ip)) { 'Activo' } else { 'Solo ARP' }
                Ms           = if ($msPorIp.ContainsKey($ip)) { $msPorIp[$ip] } else { $null }
                Clave        = ''
                Cambio       = ''
                PrimeraVez   = ''
                UltimoVisto  = ''
                Presencia    = ''
            }
        })

    # Nombres por DNS inverso (en paralelo) y, opcionalmente, NetBIOS
    if (-not $SinNombres) {
        $tareasDns = @{}
        foreach ($f in $filas) {
            try { $tareasDns[$f.IP] = [System.Net.Dns]::GetHostEntryAsync($f.IP) } catch { }
        }

        foreach ($f in $filas) {
            $nombre = $null
            if ($tareasDns.ContainsKey($f.IP)) {
                try {
                    if ($tareasDns[$f.IP].Wait(1500)) {
                        $e = $tareasDns[$f.IP].Result
                        if ($e -and $e.HostName) { $nombre = ($e.HostName -split '\.')[0] }
                    }
                }
                catch { }
            }
            if (-not $nombre -and $NetBios) {
                $nombre = Resolve-NombreNetBios -Ip $f.IP
            }
            if ($nombre) { $f.Nombre = $nombre }
        }
    }

    # Fabricante por OUI
    if ($Opciones.UsarFabricantes) {
        foreach ($f in $filas) {
            if ($f.MAC) { $f.Fabricante = Resolve-Fabricante -Mac $f.MAC -Cache $CacheOui }
        }
    }

    # Escaneo de puertos TCP
    $puertos = @()
    if ($Opciones.Puertos) { $puertos = @($Opciones.Puertos) }

    if ($Opciones.EscanearPuertos -and $puertos.Count -gt 0) {
        $ips = @($filas | ForEach-Object { $_.IP })
        $mapa = Invoke-PortScanMultiple -Ips $ips -Puertos ([int[]]$puertos) -TimeoutMs $Opciones.TimeoutPuertoMs

        foreach ($f in $filas) {
            $abiertos = @()
            if ($mapa.ContainsKey($f.IP)) { $abiertos = @($mapa[$f.IP]) }

            $f.Puertos = $abiertos
            $partes = foreach ($p in $abiertos) {
                $servicio = Get-NombreServicio -Puerto $p
                if ($servicio) { "$p ($servicio)" } else { "$p" }
            }
            $f.PuertosTexto = ($partes -join ', ')
        }
    }

    return $filas
}
