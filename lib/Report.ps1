# Presentacion de resultados: consola, CSV y HTML.

function Show-TablaDispositivos {
    param($Filas)

    if (-not $Filas -or @($Filas).Count -eq 0) {
        Write-Host "  No se encontraron dispositivos." -ForegroundColor DarkGray
        return
    }

    $Filas |
        Select-Object IP, MAC, Nombre, Fabricante, Autorizado, PuertosTexto, Estado, Cambio |
        Format-Table -AutoSize | Out-Host
}

function Show-AlertasConsola {
    param($Nuevos, $Desaparecidos, $CambiosIp)

    $hay = $false

    if ($Nuevos -and @($Nuevos).Count -gt 0) {
        $hay = $true
        Write-Host "  [!] DISPOSITIVOS NUEVOS:" -ForegroundColor Yellow
        foreach ($n in @($Nuevos)) {
            $etiqueta = if (-not $n.MAC) { '(sin MAC)' }
                        elseif ($n.Autorizado -eq 'Si') { '(autorizado)' }
                        elseif ($n.MacAleatoria) { '(MAC aleatoria)' }
                        else { '(NO autorizado)' }
            Write-Host ("      {0,-15} {1,-18} {2} {3}" -f $n.IP, $n.MAC, $n.Fabricante, $etiqueta) -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($Desaparecidos -and @($Desaparecidos).Count -gt 0) {
        $hay = $true
        Write-Host "  [i] DESAPARECIDOS:" -ForegroundColor DarkYellow
        foreach ($d in @($Desaparecidos)) {
            Write-Host ("      {0,-15} {1,-18} {2}  (visto: {3})" -f $d.IP, $d.MAC, $d.Fabricante, $d.UltimoVisto) -ForegroundColor DarkYellow
        }
        Write-Host ""
    }

    if ($CambiosIp -and @($CambiosIp).Count -gt 0) {
        $hay = $true
        Write-Host "  [i] CAMBIOS DE IP:" -ForegroundColor DarkCyan
        foreach ($c in @($CambiosIp)) {
            Write-Host ("      {0} -> {1}   {2}" -f $c.Antes, $c.Ahora, $c.Fabricante) -ForegroundColor DarkCyan
        }
        Write-Host ""
    }

    if (-not $hay) {
        Write-Host "  Sin cambios respecto al escaneo anterior." -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Export-CsvReporte {
    param($Filas, [string]$Ruta)

    $Filas |
        Select-Object IP, MAC, Nombre, Fabricante, Autorizado,
            @{ Name = 'MacAleatoria'; Expression = { if ($_.MacAleatoria) { 'Si' } else { 'No' } } },
            PuertosTexto, Estado, Ms, Cambio, PrimeraVez, UltimoVisto, Presencia |
        Export-Csv -Path $Ruta -NoTypeInformation -Encoding UTF8
}

function Export-HtmlReporte {
    param(
        $Filas,
        $Nuevos,
        $Desaparecidos,
        $CambiosIp,
        $Opciones,
        [double]$DuracionSeg,
        [string]$Ruta,
        [string]$Equipo
    )

    $css = @'
:root {
  --bg:#f5f7fb; --card:#ffffff; --text:#1f2430; --muted:#6b7280; --line:#e5e7eb;
  --ok:#16a34a; --warn:#d97706; --bad:#dc2626; --info:#2563eb;
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; }
header { background:#111827; color:#fff; padding:28px 24px; }
header h1 { margin:0 0 4px; font-size:24px; letter-spacing:.5px; }
header p { margin:0; color:#9ca3af; font-size:14px; }
main { max-width:1280px; margin:0 auto; padding:24px; }
.cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; margin-bottom:20px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:16px;
  box-shadow:0 1px 2px rgba(16,24,40,.05); }
.card .num { display:block; font-size:28px; font-weight:700; }
.card .lbl { color:var(--muted); font-size:13px; }
.seccion { background:var(--card); border:1px solid var(--line); border-radius:12px;
  padding:18px; margin-bottom:20px; box-shadow:0 1px 2px rgba(16,24,40,.05); }
.seccion h2 { margin:0 0 12px; font-size:16px; }
.muted { color:var(--muted); }
.lista-alertas { margin:0; padding-left:18px; }
.lista-alertas li { margin:6px 0; }
.tabla-wrap { overflow-x:auto; }
table { width:100%; border-collapse:collapse; font-size:13px; }
th, td { text-align:left; padding:9px 10px; border-bottom:1px solid var(--line); white-space:nowrap; }
th { color:var(--muted); font-weight:600; font-size:12px; text-transform:uppercase; letter-spacing:.4px; }
tbody tr:hover { background:#f9fafb; }
.badge { display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; font-weight:600; }
.b-ok { background:#dcfce7; color:#166534; }
.b-no { background:#fee2e2; color:#991b1b; }
.b-nuevo { background:#fef3c7; color:#92400e; }
.b-info { background:#dbeafe; color:#1e40af; }
.b-gray { background:#f3f4f6; color:#374151; }
.dot { display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:6px; }
.d-ok { background:var(--ok); }
.d-warn { background:var(--warn); }
footer { color:var(--muted); font-size:12px; text-align:center; padding:24px; }
@media (max-width:600px) { header { padding:20px 16px; } main { padding:16px; } }
'@

    $total = @($Filas).Count
    $activos = @($Filas | Where-Object { $_.Estado -eq 'Activo' }).Count
    $autorizados = @($Filas | Where-Object { $_.Autorizado -eq 'Si' }).Count
    $nuevosN = @($Nuevos).Count
    $desapN = @($Desaparecidos).Count
    $redTexto = '{0}.{1} - {0}.{2}' -f $Opciones.Red, $Opciones.Inicio, $Opciones.Fin
    $fechaTexto = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $puertosTexto = if ($Opciones.EscanearPuertos) { 'si' } else { 'no' }

    $plantilla = '<tr><td><strong>{0}</strong></td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td><td>{9}</td></tr>'

    $filasHtml = foreach ($f in $Filas) {
        $macH = ConvertTo-HtmlSeguro $f.MAC
        if ($f.MacAleatoria) { $macH = $macH + ' <span class="badge b-info">aleatoria</span>' }

        $autH = if ($f.Autorizado -eq 'Si') { '<span class="badge b-ok">Si</span>' }
                elseif ($f.Autorizado -eq 'No') { '<span class="badge b-no">No</span>' }
                else { '<span class="badge b-gray">-</span>' }

        $camH = if ($f.Cambio -eq 'NUEVO') { '<span class="badge b-nuevo">NUEVO</span>' }
                else { '<span class="badge b-gray">Conocido</span>' }

        $estH = if ($f.Estado -eq 'Activo') { '<span class="dot d-ok"></span>Activo' }
                else { '<span class="dot d-warn"></span>Solo ARP' }

        $puertosH = if ($f.PuertosTexto) { ConvertTo-HtmlSeguro $f.PuertosTexto } else { '<span class="muted">-</span>' }
        $presH = if ($f.Presencia -ne '') { "$($f.Presencia)%" } else { '<span class="muted">-</span>' }

        $plantilla -f (ConvertTo-HtmlSeguro $f.IP), $macH, (ConvertTo-HtmlSeguro $f.Nombre), (ConvertTo-HtmlSeguro $f.Fabricante), $autH, $puertosH, $estH, $camH, $presH, (ConvertTo-HtmlSeguro $f.PrimeraVez)
    }

    $tablaHtml = (@($filasHtml) -join "`n")

    $items = [System.Collections.Generic.List[string]]::new()

    foreach ($n in @($Nuevos)) {
        $items.Add('<li><span class="badge b-nuevo">NUEVO</span> ' + (ConvertTo-HtmlSeguro $n.IP) + ' &middot; ' + (ConvertTo-HtmlSeguro $n.MAC) + ' &middot; ' + (ConvertTo-HtmlSeguro $n.Fabricante) + '</li>')
    }
    foreach ($d in @($Desaparecidos)) {
        $items.Add('<li><span class="badge b-gray">DESAPARECIDO</span> ' + (ConvertTo-HtmlSeguro $d.IP) + ' &middot; ' + (ConvertTo-HtmlSeguro $d.MAC) + ' &middot; ' + (ConvertTo-HtmlSeguro $d.Fabricante) + ' <span class="muted">(visto: ' + (ConvertTo-HtmlSeguro $d.UltimoVisto) + ')</span></li>')
    }
    foreach ($c in @($CambiosIp)) {
        $items.Add('<li><span class="badge b-info">CAMBIO IP</span> ' + (ConvertTo-HtmlSeguro $c.Antes) + ' &rarr; ' + (ConvertTo-HtmlSeguro $c.Ahora) + ' &middot; ' + (ConvertTo-HtmlSeguro $c.Fabricante) + '</li>')
    }

    $alertasHtml = ''
    if ($items.Count -gt 0) {
        $listaHtml = $items -join "`n"
        $alertasHtml = @"
  <section class="seccion">
    <h2>Cambios detectados</h2>
    <ul class="lista-alertas">
$listaHtml
    </ul>
  </section>
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scan-Red - Reporte de red</title>
<style>
$css
</style>
</head>
<body>
<header>
  <h1>Scan-Red</h1>
  <p>Reporte de red local &middot; $(ConvertTo-HtmlSeguro $Equipo) &middot; $fechaTexto</p>
</header>
<main>
  <section class="cards">
    <div class="card"><span class="num">$total</span><span class="lbl">Dispositivos</span></div>
    <div class="card"><span class="num">$activos</span><span class="lbl">Activos</span></div>
    <div class="card"><span class="num">$autorizados</span><span class="lbl">Autorizados</span></div>
    <div class="card"><span class="num">$nuevosN</span><span class="lbl">Nuevos</span></div>
    <div class="card"><span class="num">$desapN</span><span class="lbl">Desaparecidos</span></div>
  </section>
  <section class="seccion">
    <p class="muted">Red: $(ConvertTo-HtmlSeguro $redTexto) &middot; Duracion: $([math]::Round($DuracionSeg, 1)) s &middot; Puertos: $puertosTexto</p>
  </section>
$alertasHtml
  <section class="seccion">
    <h2>Dispositivos</h2>
    <div class="tabla-wrap">
      <table>
        <thead>
          <tr><th>IP</th><th>MAC</th><th>Nombre</th><th>Fabricante</th><th>Autorizado</th><th>Puertos</th><th>Estado</th><th>Cambio</th><th>Presencia</th><th>Primera vez</th></tr>
        </thead>
        <tbody>
$tablaHtml
        </tbody>
      </table>
    </div>
  </section>
</main>
<footer>Generado por Scan-Red &middot; Usa esta herramienta solo en redes que administres o tengas permiso.</footer>
</body>
</html>
"@

    Set-Content -Path $Ruta -Value $html -Encoding UTF8
}
