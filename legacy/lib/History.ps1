# Estado anterior, historial acumulado y estadisticas de presencia.

function Read-Estado {
    param([string]$Ruta)

    $estado = @{}
    if (Test-Path $Ruta) {
        try {
            (Get-Content $Ruta -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $estado[$_.Name] = $_.Value }
        }
        catch { $estado = @{} }
    }
    return $estado
}

function Save-Estado {
    param([hashtable]$Estado, [string]$Ruta)

    try { $Estado | ConvertTo-Json -Depth 6 | Set-Content -Path $Ruta -Encoding UTF8 } catch { }
}

function Add-Historial {
    param([string]$Ruta, $Filas, [string]$Fecha)

    $objetos = foreach ($f in $Filas) {
        [pscustomobject]@{
            Fecha      = $Fecha
            IP         = $f.IP
            MAC        = $f.MAC
            Nombre     = $f.Nombre
            Fabricante = $f.Fabricante
            Autorizado = $f.Autorizado
            Puertos    = (@($f.Puertos) -join ',')
            Estado     = $f.Estado
        }
    }

    if (Test-Path $Ruta) {
        $objetos | Export-Csv -Path $Ruta -NoTypeInformation -Encoding UTF8 -Append
    }
    else {
        $objetos | Export-Csv -Path $Ruta -NoTypeInformation -Encoding UTF8
    }
}

function Read-Estadisticas {
    param([string]$Ruta)

    $stats = [pscustomobject]@{
        Escaneos     = 0
        Dispositivos = @{}
    }

    if (Test-Path $Ruta) {
        try {
            $json = Get-Content $Ruta -Raw -ErrorAction Stop | ConvertFrom-Json
            $stats.Escaneos = [int]$json.Escaneos
            if ($json.Dispositivos) {
                $json.Dispositivos.PSObject.Properties | ForEach-Object {
                    $stats.Dispositivos[$_.Name] = [pscustomobject]@{
                        Veces       = [int]$_.Value.Veces
                        PrimeraVez  = [string]$_.Value.PrimeraVez
                        UltimoVisto = [string]$_.Value.UltimoVisto
                        Nombre      = [string]$_.Value.Nombre
                        Fabricante  = [string]$_.Value.Fabricante
                    }
                }
            }
        }
        catch { }
    }

    return $stats
}

function Save-Estadisticas {
    param($Estadisticas, [string]$Ruta)

    try { $Estadisticas | ConvertTo-Json -Depth 6 | Set-Content -Path $Ruta -Encoding UTF8 } catch { }
}

# Suma un escaneo y recalcula la presencia de cada dispositivo.
function Update-Estadisticas {
    param($Estadisticas, $Filas)

    $Estadisticas.Escaneos = [int]$Estadisticas.Escaneos + 1
    $grupos = $Filas | Group-Object { if ($_.MAC) { $_.MAC } else { "IP:$($_.IP)" } }

    foreach ($g in $grupos) {
        $clave = $g.Name

        $primera = ''
        foreach ($f in $g.Group) {
            if ($f.PrimeraVez) { $primera = $f.PrimeraVez; break }
        }

        if (-not $Estadisticas.Dispositivos.ContainsKey($clave)) {
            $Estadisticas.Dispositivos[$clave] = [pscustomobject]@{
                Veces       = 0
                PrimeraVez  = $primera
                UltimoVisto = ''
                Nombre      = ''
                Fabricante  = ''
            }
        }

        $d = $Estadisticas.Dispositivos[$clave]
        $d.Veces = [int]$d.Veces + 1
        $d.UltimoVisto = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        foreach ($f in $g.Group) {
            if ($f.Nombre) { $d.Nombre = $f.Nombre }
            if ($f.Fabricante -and $f.Fabricante -ne 'Desconocido') { $d.Fabricante = $f.Fabricante }
        }

        $presencia = [int][math]::Round(100 * $d.Veces / $Estadisticas.Escaneos)
        foreach ($f in $g.Group) { $f.Presencia = $presencia }
    }
}

function Show-ResumenHistorial {
    param($Estadisticas)

    if (-not $Estadisticas -or $Estadisticas.Escaneos -eq 0) {
        Write-Host "  Todavia no hay historial guardado." -ForegroundColor DarkGray
        return
    }

    $filas = foreach ($k in $Estadisticas.Dispositivos.Keys) {
        $d = $Estadisticas.Dispositivos[$k]
        [pscustomobject]@{
            MAC         = $k
            Nombre      = $d.Nombre
            Fabricante  = $d.Fabricante
            Presencia   = ([int][math]::Round(100 * $d.Veces / $Estadisticas.Escaneos)).ToString() + '%'
            Veces       = $d.Veces
            PrimeraVez  = $d.PrimeraVez
            UltimoVisto = $d.UltimoVisto
        }
    }

    $filas | Sort-Object { [int]($_.Presencia -replace '%', '') } -Descending |
        Format-Table -AutoSize | Out-Host
}
