# Escaneo TCP de puertos (conexiones asincronas en paralelo).

function Invoke-PortScanMultiple {
    param(
        [string[]]$Ips,
        [int[]]$Puertos,
        [int]$TimeoutMs = 250
    )

    $resultado = @{}
    foreach ($ip in $Ips) {
        $resultado[$ip] = [System.Collections.Generic.List[int]]::new()
    }

    $conexiones = foreach ($ip in $Ips) {
        foreach ($p in $Puertos) {
            $cliente = [System.Net.Sockets.TcpClient]::new()
            try {
                [pscustomobject]@{
                    IP      = $ip
                    Puerto  = $p
                    Cliente = $cliente
                    Tarea   = $cliente.ConnectAsync($ip, $p)
                }
            }
            catch {
                $cliente.Dispose()
            }
        }
    }

    foreach ($c in $conexiones) {
        try {
            if ($c.Tarea.Wait($TimeoutMs) -and $c.Cliente.Connected) {
                $resultado[$c.IP].Add($c.Puerto)
            }
        }
        catch { }
        finally { $c.Cliente.Dispose() }
    }

    foreach ($ip in $Ips) {
        $resultado[$ip] = @($resultado[$ip] | Sort-Object -Unique)
    }

    return $resultado
}
