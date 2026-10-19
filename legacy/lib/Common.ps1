# Funciones compartidas por Scan-Red.

function ConvertTo-MacNormalizada {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return '' }

    $hex = ($Mac -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($hex.Length -eq 12) {
        return ($hex -replace '(..)(?=.)', '$1-')
    }
    return $Mac.ToUpper()
}

# Una MAC es "aleatoria/localmente administrada" si el bit 0x02 del primer octeto esta activo.
function Test-MacAleatoria {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return $false }

    $partes = $Mac -split '-'
    if ($partes.Count -lt 1) { return $false }

    try {
        $primerOcteto = [Convert]::ToByte($partes[0], 16)
        return (($primerOcteto -band 0x02) -ne 0)
    }
    catch { return $false }
}

function Get-NombreServicio {
    param([int]$Puerto)

    switch ($Puerto) {
        21 { 'FTP' }
        22 { 'SSH' }
        23 { 'Telnet' }
        25 { 'SMTP' }
        53 { 'DNS' }
        80 { 'HTTP' }
        110 { 'POP3' }
        135 { 'RPC' }
        139 { 'NetBIOS' }
        143 { 'IMAP' }
        443 { 'HTTPS' }
        445 { 'SMB' }
        554 { 'RTSP' }
        587 { 'SMTP' }
        631 { 'IPP' }
        993 { 'IMAPS' }
        995 { 'POP3S' }
        1433 { 'SQL Server' }
        3306 { 'MySQL' }
        3389 { 'RDP' }
        5000 { 'UPnP' }
        5432 { 'PostgreSQL' }
        8000 { 'HTTP-alt' }
        8080 { 'HTTP-alt' }
        8443 { 'HTTPS-alt' }
        8554 { 'RTSP-alt' }
        9100 { 'Impresora' }
        34567 { 'DVR' }
        37777 { 'Dahua' }
        default { '' }
    }
}

function ConvertTo-HtmlSeguro {
    param([string]$Texto)

    if ($null -eq $Texto) { return '' }
    return ($Texto -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-MensajeError {
    param($Error)

    if ($Error -and $Error.Exception) { return $Error.Exception.Message }
    return [string]$Error
}
