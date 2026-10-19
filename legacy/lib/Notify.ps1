# Notificaciones: toast de Windows, Telegram y email.

function Send-Toast {
    param([string]$Titulo, [string]$Mensaje)

    $ok = $false

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $tituloXml = [System.Security.SecurityElement]::Escape($Titulo)
        $mensajeXml = [System.Security.SecurityElement]::Escape($Mensaje)
        $xml = "<toast><visual><binding template=`"ToastGeneric`"><text>$tituloXml</text><text>$mensajeXml</text></binding></visual></toast>"

        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        $ok = $true
    }
    catch { }

    # Respaldo: globo de la bandeja del sistema (funciona en PowerShell 7)
    if (-not $ok) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            $ni = New-Object System.Windows.Forms.NotifyIcon
            $ni.Icon = [System.Drawing.SystemIcons]::Information
            $ni.Visible = $true
            $ni.ShowBalloonTip(6000, $Titulo, $Mensaje, [System.Windows.Forms.ToolTipIcon]::Warning)
            Start-Sleep -Milliseconds 2000
            $ni.Dispose()
            $ok = $true
        }
        catch { }
    }

    return $ok
}

function Send-Telegram {
    param([string]$Token, [string]$ChatId, [string]$Mensaje)

    if (-not $Token -or -not $ChatId) { return $false }

    try {
        if ($Mensaje.Length -gt 4000) { $Mensaje = $Mensaje.Substring(0, 3990) + '...' }
        $body = @{
            chat_id                  = $ChatId
            text                     = $Mensaje
            disable_web_page_preview = $true
        }
        Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$Token/sendMessage" `
            -Body $body -TimeoutSec 10 | Out-Null
        return $true
    }
    catch { return $false }
}

function Send-EmailAlerta {
    param($Cfg, [string]$Asunto, [string]$Mensaje)

    try {
        if (-not $Cfg.Servidor -or -not $Cfg.Para) { return $false }

        $password = $Cfg.Password
        if (-not $password -and $Cfg.PasswordEnv) {
            $password = [Environment]::GetEnvironmentVariable($Cfg.PasswordEnv)
        }

        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = New-Object System.Net.Mail.MailAddress($Cfg.Usuario)
        foreach ($destino in ($Cfg.Para -split '[,;]')) {
            if ($destino.Trim()) { $mail.To.Add($destino.Trim()) }
        }
        $mail.Subject = $Asunto
        $mail.Body = $Mensaje

        $smtp = New-Object System.Net.Mail.SmtpClient($Cfg.Servidor, [int]$Cfg.Puerto)
        $smtp.EnableSsl = [bool]$Cfg.UsarSsl
        $smtp.Timeout = 15000
        if ($Cfg.Usuario) {
            $smtp.Credentials = New-Object System.Net.NetworkCredential($Cfg.Usuario, $password)
        }

        $smtp.Send($mail)
        $smtp.Dispose()
        $mail.Dispose()
        return $true
    }
    catch { return $false }
}

# Envia alertas de dispositivos nuevos segun la configuracion y registra en alertas.log.
function Send-Alertas {
    param($Nuevos, $Cfg, [string]$Carpeta)

    $destacar = @($Nuevos | Where-Object {
            $_.MAC -and
            ((-not $Cfg.Notificaciones.SoloNoAutorizados) -or $_.Autorizado -ne 'Si') -and
            ((-not $Cfg.IgnorarMacAleatoria) -or (-not $_.MacAleatoria))
        })

    if ($destacar.Count -eq 0) { return 0 }

    $lineas = foreach ($d in $destacar) {
        $partes = @($d.IP)
        if ($d.MAC) { $partes += $d.MAC }
        if ($d.Fabricante -and $d.Fabricante -ne 'Desconocido') { $partes += $d.Fabricante }
        if ($d.PuertosTexto) { $partes += $d.PuertosTexto }
        $partes -join ' | '
    }

    $mensaje = "Dispositivo(s) nuevo(s) en la red:`n" + ($lineas -join "`n")
    $asunto = "Scan-Red: $($destacar.Count) dispositivo(s) nuevo(s)"

    try {
        $log = Join-Path $Carpeta 'alertas.log'
        $texto = "[{0}] {1}`n{2}`n" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $asunto, $mensaje
        Add-Content -Path $log -Value $texto -Encoding UTF8
    }
    catch { }

    $n = $Cfg.Notificaciones

    if ($n.Toast) {
        Send-Toast -Titulo $asunto -Mensaje ($lineas -join "`n") | Out-Null
    }

    if ($n.Telegram -and $n.Telegram.Activo) {
        $token = $n.Telegram.BotToken
        if (-not $token -and $n.Telegram.BotTokenEnv) {
            $token = [Environment]::GetEnvironmentVariable($n.Telegram.BotTokenEnv)
        }
        Send-Telegram -Token $token -ChatId $n.Telegram.ChatId -Mensaje $mensaje | Out-Null
    }

    if ($n.Email -and $n.Email.Activo) {
        Send-EmailAlerta -Cfg $n.Email -Asunto $asunto -Mensaje $mensaje | Out-Null
    }

    return $destacar.Count
}
