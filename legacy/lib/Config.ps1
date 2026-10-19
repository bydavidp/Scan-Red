# Carga, fusion y guardado de configuracion.

function Get-ConfigPorDefecto {
    return [pscustomobject]@{
        Red                 = '192.168.1'
        TimeoutMs           = 800
        Inicio              = 1
        Fin                 = 254
        CarpetaReportes     = 'Reportes-Red'
        GenerarCsv          = $true
        GenerarHtml         = $true
        GuardarHistorial    = $true
        CompararEstado      = $true
        UsarFabricantes     = $true
        EscanearPuertos     = $true
        Puertos             = @(22, 80, 443, 554, 3389, 8000, 8080, 8443, 37777)
        TimeoutPuertoMs     = 250
        Vigilar             = $false
        Intervalo           = 300
        Veces               = 0
        ListaBlanca         = @()
        IgnorarMacAleatoria = $true
        Notificaciones      = [pscustomobject]@{
            Toast             = $true
            SoloNoAutorizados = $true
            Telegram          = [pscustomobject]@{
                Activo      = $false
                BotToken    = ''
                BotTokenEnv = 'SCANRED_TELEGRAM_TOKEN'
                ChatId      = ''
            }
            Email             = [pscustomobject]@{
                Activo      = $false
                Servidor    = 'smtp.gmail.com'
                Puerto      = 587
                UsarSsl     = $true
                Usuario     = ''
                Password    = ''
                PasswordEnv = 'SCANRED_SMTP_PASS'
                Para        = ''
            }
        }
    }
}

# Fusiona recursivamente los valores de $Extra sobre $Base (solo propiedades existentes).
function Merge-Config {
    param($Base, $Extra)

    foreach ($p in $Extra.PSObject.Properties) {
        $prop = $Base.PSObject.Properties[$p.Name]
        if (-not $prop) { continue }
        if ($null -eq $p.Value) { continue }

        if ($prop.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) {
            Merge-Config -Base $prop.Value -Extra $p.Value
        }
        else {
            $prop.Value = $p.Value
        }
    }
}

function Get-ScanConfig {
    param([string]$Ruta)

    $cfg = Get-ConfigPorDefecto
    if ($Ruta -and (Test-Path $Ruta)) {
        try {
            $json = Get-Content $Ruta -Raw -ErrorAction Stop | ConvertFrom-Json
            Merge-Config -Base $cfg -Extra $json
        }
        catch {
            Write-Host ("  Aviso: no se pudo leer {0}: {1}" -f $Ruta, (Get-MensajeError $_)) -ForegroundColor Yellow
        }
    }
    return $cfg
}

function Save-ScanConfig {
    param($Config, [string]$Ruta)

    $Config | ConvertTo-Json -Depth 8 | Set-Content -Path $Ruta -Encoding UTF8
}

function Resolve-CarpetaReportes {
    param([string]$Carpeta)

    if ([string]::IsNullOrWhiteSpace($Carpeta)) { $Carpeta = 'Reportes-Red' }

    if (-not [System.IO.Path]::IsPathRooted($Carpeta)) {
        $Carpeta = Join-Path $HOME $Carpeta
    }

    if (-not (Test-Path $Carpeta)) {
        New-Item -ItemType Directory -Path $Carpeta -Force | Out-Null
    }

    return $Carpeta
}
