"""Interfaz de linea de comandos de Scan-Red."""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from datetime import datetime
from pathlib import Path

from . import __version__
from .discovery import discover, validate_red
from .exporters import export_csv, export_json
from .history import apply_history, load_history, now_iso, save_history
from .models import Device
from .portscanner import ConnectScanner, SynScanner

LEGAL_EPILOG = """\
Aviso de uso:
  Usa esta herramienta solo en redes que administres o para las que tengas
  autorizacion escrita. El flag --autorizado es obligatorio.

Ejemplos:
  scan-red --autorizado
  scan-red --red 192.168.0 --inicio 1 --fin 100 --autorizado
  scan-red --autorizado --puertos 22,80,443,3389
  scan-red --autorizado --puertos 80,443 --motor-puertos syn
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="scan-red",
        description="Escaner de red local (LAN + puertos TCP).",
        epilog=LEGAL_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Parametros equivalentes a la version PowerShell
    parser.add_argument(
        "-Red",
        "--red",
        dest="red",
        default="192.168.1",
        metavar="PREFIJO",
        help="Prefijo de red de 3 octetos (por defecto 192.168.1).",
    )
    parser.add_argument(
        "-Inicio",
        "--inicio",
        dest="inicio",
        type=int,
        default=1,
        metavar="N",
        help="Primer octeto del rango (por defecto 1).",
    )
    parser.add_argument(
        "-Fin",
        "--fin",
        dest="fin",
        type=int,
        default=254,
        metavar="N",
        help="Ultimo octeto del rango (por defecto 254).",
    )
    parser.add_argument(
        "-TimeoutMs",
        "--timeout-ms",
        dest="timeout_ms",
        type=int,
        default=800,
        metavar="MS",
        help="Espera por ping en milisegundos (por defecto 800).",
    )
    parser.add_argument(
        "-Carpeta",
        "--carpeta",
        dest="carpeta",
        default=str(Path.home() / "Reportes-Red"),
        metavar="RUTA",
        help="Carpeta de reportes (por defecto ~/Reportes-Red).",
    )
    parser.add_argument(
        "-Csv",
        "--csv",
        dest="csv",
        default=None,
        metavar="RUTA",
        help="Nombre o ruta del CSV (relativo = dentro de -Carpeta).",
    )
    parser.add_argument(
        "--json",
        dest="json_path",
        default=None,
        metavar="RUTA",
        help="Exportar tambien a JSON.",
    )
    parser.add_argument(
        "-SinCsv",
        "--sin-csv",
        dest="sin_csv",
        action="store_true",
        help="No generar CSV.",
    )
    parser.add_argument(
        "-SinHistorial",
        "--sin-historial",
        dest="sin_historial",
        action="store_true",
        help="No leer ni guardar el estado anterior.",
    )
    parser.add_argument(
        "-SinFabricante",
        "--sin-fabricante",
        dest="sin_fabricante",
        action="store_true",
        help="No consultar fabricantes por OUI (funciona sin internet).",
    )
    parser.add_argument(
        "--netbios",
        dest="netbios",
        action="store_true",
        help="Probar NetBIOS cuando el DNS inverso falla (Windows).",
    )

    # Extension: escaneo de puertos
    parser.add_argument(
        "--puertos",
        dest="puertos",
        default="",
        metavar="LISTA",
        help="Puertos TCP a escanear. Ej: 22,80,443 o 1-1024. Vacio = no escanear.",
    )
    parser.add_argument(
        "--motor-puertos",
        dest="motor_puertos",
        choices=("connect", "syn"),
        default="connect",
        help="Motor de escaneo: connect (sin privilegios) o syn (scapy).",
    )
    parser.add_argument(
        "--timeout-puerto",
        dest="timeout_puerto",
        type=float,
        default=1.0,
        metavar="SEG",
        help="Timeout por conexion TCP en segundos (por defecto 1.0).",
    )
    parser.add_argument(
        "--solo-publicas",
        dest="solo_publicas",
        action="store_true",
        help="Omitir IPs privadas/reservadas (solo hosts publicos).",
    )

    # Legal / diagnostico
    parser.add_argument(
        "--autorizado",
        dest="autorizado",
        action="store_true",
        help="Confirmacion legal obligatoria.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        dest="verbose",
        action="count",
        default=0,
        help="Mas detalle (-v info, -vv debug).",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )
    return parser


def parse_ports(text: str) -> list[int]:
    """Convierte '22,80,443' o '1-1024' en una lista ordenada de puertos."""
    if not text or not text.strip():
        return []

    ports: set[int] = set()
    for piece in text.split(","):
        piece = piece.strip()
        if not piece:
            continue
        try:
            if "-" in piece:
                start_text, end_text = piece.split("-", 1)
                start, end = int(start_text), int(end_text)
                if start > end:
                    raise ValueError(f"Rango invertido: {piece}")
                ports.update(range(start, end + 1))
            else:
                ports.add(int(piece))
        except ValueError as exc:
            raise ValueError(f"Lista de puertos invalida: {piece}") from exc

    for port in ports:
        if not 1 <= port <= 65535:
            raise ValueError(f"Puerto fuera de rango: {port}")

    return sorted(ports)


def _short(value: str | None, width: int) -> str:
    text = (value or "").strip()
    if len(text) <= width:
        return text
    return text[: max(0, width - 1)] + "~"


def _print_table(devices: list[Device]) -> None:
    if not devices:
        print("(sin dispositivos)")
        return

    header = (
        f"{'IP':<16}{'MAC':<19}{'Nombre':<20}{'Fabricante':<24}{'Estado':<10}{'Cambio':<9}PUERTOS"
    )
    print(header)
    print("-" * len(header))
    for device in devices:
        ports = ",".join(str(port) for port in device.puertos_abiertos)
        print(
            f"{device.ip:<16}"
            f"{_short(device.mac or '-', 18):<19}"
            f"{_short(device.nombre, 18):<20}"
            f"{_short(device.fabricante, 22):<24}"
            f"{device.estado:<10}"
            f"{device.cambio:<9}"
            f"{ports}"
        )


def _resolve_output(value: str | None, report_dir: Path, default_name: str) -> Path | None:
    if value is None:
        return None
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = report_dir / path
    if path.is_dir():
        path = path / default_name
    return path


async def _run(args: argparse.Namespace) -> int:
    level = (
        logging.DEBUG
        if args.verbose >= 2
        else logging.INFO
        if args.verbose == 1
        else logging.WARNING
    )
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    if not args.autorizado:
        print(
            "ERROR: debes pasar --autorizado confirmando que administras "
            "la red o tienes permiso escrito.",
            file=sys.stderr,
        )
        return 2

    try:
        validate_red(args.red)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if not (1 <= args.inicio <= args.fin <= 254):
        print(
            "ERROR: rango invalido. Debe cumplir 1 <= inicio <= fin <= 254.",
            file=sys.stderr,
        )
        return 2

    if args.timeout_ms <= 0:
        print("ERROR: -TimeoutMs debe ser mayor que 0.", file=sys.stderr)
        return 2

    if args.timeout_puerto <= 0:
        print("ERROR: --timeout-puerto debe ser mayor que 0.", file=sys.stderr)
        return 2

    report_dir = Path(args.carpeta).expanduser()
    try:
        report_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(
            f"ERROR: no se pudo crear la carpeta {report_dir}: {exc}",
            file=sys.stderr,
        )
        return 2

    # Parsear puertos y construir el motor antes del escaneo lento: asi un
    # error de configuracion (o la falta de scapy) falla rapido.
    ports: list[int] = []
    scanner: ConnectScanner | SynScanner | None = None
    if args.puertos:
        try:
            ports = parse_ports(args.puertos)
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2

        try:
            if args.motor_puertos == "syn":
                scanner = SynScanner(
                    timeout=args.timeout_puerto,
                    authorized=True,
                    only_public=args.solo_publicas,
                )
            else:
                scanner = ConnectScanner(
                    timeout=args.timeout_puerto,
                    authorized=True,
                    only_public=args.solo_publicas,
                )
        except (RuntimeError, PermissionError) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2

    print(f"Scan-Red {__version__}")
    print(f"Red: {args.red}.{args.inicio} - {args.red}.{args.fin}")
    print(f"Reportes: {report_dir}")
    print("Escaneando ...", flush=True)

    devices = await discover(
        args.red,
        args.inicio,
        args.fin,
        args.timeout_ms,
        sin_fabricante=args.sin_fabricante,
        netbios=args.netbios,
    )

    # ------------------------------------------------------------------
    # Historial / deteccion de cambios
    # ------------------------------------------------------------------
    history_path = report_dir / "estado-anterior.json"
    missing: list[dict[str, object]] = []

    if args.sin_historial:
        timestamp = now_iso()
        for device in devices:
            device.cambio = "-"
            device.primera_vez = None
            device.ultimo_visto = timestamp
    else:
        history = load_history(history_path)
        missing = apply_history(devices, history)
        if not history:
            print("Linea base creada (primer escaneo con estado).")

    # ------------------------------------------------------------------
    # Escaneo de puertos (el motor ya se valido antes del descubrimiento)
    # ------------------------------------------------------------------
    if scanner is not None and ports:
        ips = [device.ip for device in devices]
        if ips:
            print(
                f"Puertos: {len(ports)} puerto(s) en {len(ips)} host(s) ({args.motor_puertos}) ...",
                flush=True,
            )
            try:
                results = await scanner.scan_hosts(ips, ports)
            except (RuntimeError, PermissionError) as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return 2

            for device in devices:
                result = results.get(device.ip)
                if result is not None:
                    device.puertos_abiertos = result.open_ports
        else:
            print("Puertos: no hay hosts activos para escanear.")

    # ------------------------------------------------------------------
    # Salida por consola
    # ------------------------------------------------------------------
    print()
    _print_table(devices)

    activos = sum(1 for device in devices if device.estado == "Activo")
    nuevos = sum(1 for device in devices if device.cambio == "NUEVO")
    print()
    print(
        f"Total: {len(devices)} | Activos: {activos} | Nuevos: {nuevos} | "
        f"Desaparecidos: {len(missing)}"
    )

    if missing:
        print("\nDesaparecidos:")
        for item in missing:
            ip = item.get("ip") or item.get("key") or "?"
            mac = item.get("mac") or ""
            fabricante = item.get("fabricante") or ""
            print(f"  {str(ip):<16}{str(mac):<19}{fabricante}")

    with_ports = [device for device in devices if device.puertos_abiertos]
    if with_ports:
        print("\nPuertos abiertos:")
        for device in with_ports:
            ports = ",".join(str(port) for port in device.puertos_abiertos)
            print(f"  {device.ip:<16}{ports}")

    # ------------------------------------------------------------------
    # Exportacion
    # ------------------------------------------------------------------
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    if not args.sin_csv:
        csv_path = _resolve_output(args.csv, report_dir, f"red-{stamp}.csv")
        if csv_path is None:
            csv_path = report_dir / f"red-{stamp}.csv"
        try:
            export_csv(devices, csv_path)
        except OSError as exc:
            print(f"ERROR: no se pudo escribir {csv_path}: {exc}", file=sys.stderr)
            return 1
        print(f"\nCSV : {csv_path}")

    if args.json_path:
        json_path = _resolve_output(args.json_path, report_dir, f"red-{stamp}.json")
        if json_path is not None:
            try:
                export_json(devices, json_path)
            except OSError as exc:
                print(
                    f"ERROR: no se pudo escribir {json_path}: {exc}",
                    file=sys.stderr,
                )
                return 1
            print(f"JSON: {json_path}")

    if not args.sin_historial:
        try:
            save_history(history_path, devices)
        except OSError as exc:
            print(
                f"ERROR: no se pudo guardar el estado {history_path}: {exc}",
                file=sys.stderr,
            )
            return 1

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        print("\nCancelado.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
