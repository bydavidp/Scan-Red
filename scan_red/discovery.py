"""Descubrimiento de dispositivos: ping, ARP, DNS/NetBIOS y fabricantes."""

from __future__ import annotations

import asyncio
import json
import logging
import platform
import re
import socket
import time
from pathlib import Path

import aiohttp

from .models import Device

logger = logging.getLogger(__name__)

_IPV4_RE = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")
_MAC_RE = re.compile(
    r"\b([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5}"
    r"|[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4})\b"
)
_BROADCAST_MACS = {"00-00-00-00-00-00", "FF-FF-FF-FF-FF-FF"}
_DEFAULT_CACHE = Path.home() / ".scan-red-oui-cache.json"


# ---------------------------------------------------------------------------
# Utilidades de red / formato
# ---------------------------------------------------------------------------
def validate_red(red: str) -> None:
    """Valida un prefijo de red de 3 octetos, ej: 192.168.1."""
    parts = red.split(".")
    if len(parts) != 3 or any(not part.isdigit() or not 0 <= int(part) <= 255 for part in parts):
        raise ValueError("La red debe tener 3 octetos validos (0-255), ej: 192.168.1")


def ip_sort_key(ip: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in ip.split("."))
    except ValueError:
        return (999, 999, 999, 999)


def ip_in_range(ip: str, red: str, inicio: int, fin: int) -> bool:
    prefix = f"{red}."
    if not ip.startswith(prefix):
        return False
    rest = ip[len(prefix) :]
    if not rest.isdigit():
        return False
    return inicio <= int(rest) <= fin


def normalize_mac(mac: str) -> str:
    """Normaliza cualquier formato de MAC a AA-BB-CC-DD-EE-FF."""
    hex_chars = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(hex_chars) != 12:
        return mac.upper()
    return "-".join(hex_chars[index : index + 2] for index in range(0, 12, 2)).upper()


def mac_to_oui(mac: str) -> str | None:
    normalized = normalize_mac(mac).replace("-", "")
    if len(normalized) != 12:
        return None
    return normalized[:6]


def parse_arp_table(text: str) -> dict[str, str]:
    """Extrae {ip: mac} de `arp -a` (Windows/Linux) o `ip neigh`."""
    table: dict[str, str] = {}
    for line in text.splitlines():
        ip_match = _IPV4_RE.search(line)
        mac_match = _MAC_RE.search(line)
        if not ip_match or not mac_match:
            continue

        ip = ip_match.group(1)
        mac = normalize_mac(mac_match.group(1))
        if mac in _BROADCAST_MACS:
            continue
        if ip.startswith(("224.", "239.")) or ip == "255.255.255.255":
            continue
        table[ip] = mac
    return table


# ---------------------------------------------------------------------------
# Ping sweep
# ---------------------------------------------------------------------------
async def _ping(ip: str, timeout_ms: int) -> int | None:
    """Devuelve el RTT en ms o None. Usa el ping nativo del sistema."""
    system = platform.system().lower()
    if system == "windows":
        command = ["ping", "-n", "1", "-w", str(timeout_ms), ip]
    elif system == "darwin":
        command = ["ping", "-c", "1", "-W", str(timeout_ms), ip]
    else:
        seconds = max(1, round(timeout_ms / 1000))
        command = ["ping", "-c", "1", "-W", str(seconds), ip]

    start = time.monotonic()
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        return None

    try:
        output, _ = await asyncio.wait_for(process.communicate(), timeout=timeout_ms / 1000 + 1.5)
    except asyncio.TimeoutError:
        process.kill()
        await process.wait()
        return None

    if process.returncode != 0:
        return None

    text = output.decode(errors="ignore")
    if system == "windows" and not re.search(r"TTL[=:]\s*\d+", text, re.IGNORECASE):
        return None

    match = re.search(r"[=<]\s*([0-9]+(?:[.,][0-9]+)?)\s*ms", text, re.IGNORECASE)
    if match:
        raw = match.group(1).replace(",", ".")
        try:
            return int(round(float(raw)))
        except ValueError:
            pass

    return int((time.monotonic() - start) * 1000)


async def ping_sweep(
    red: str,
    inicio: int,
    fin: int,
    timeout_ms: int,
    concurrency: int = 64,
) -> dict[str, int]:
    """Ping sweep concurrente. Devuelve {ip: rtt_ms}."""
    semaphore = asyncio.Semaphore(concurrency)

    async def probe(ip: str) -> tuple[str, int | None]:
        async with semaphore:
            return ip, await _ping(ip, timeout_ms)

    results = await asyncio.gather(*(probe(f"{red}.{octet}") for octet in range(inicio, fin + 1)))
    return {ip: rtt for ip, rtt in results if rtt is not None}


# ---------------------------------------------------------------------------
# Tabla ARP
# ---------------------------------------------------------------------------
async def arp_table() -> dict[str, str]:
    """{ip: mac} segun la tabla ARP/neighbor del sistema."""
    system = platform.system().lower()
    if system == "windows":
        commands = [["arp", "-a"]]
    elif system == "linux":
        commands = [["ip", "neigh"], ["arp", "-an"]]
    else:
        commands = [["arp", "-an"]]

    for command in commands:
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            output, _ = await asyncio.wait_for(process.communicate(), timeout=5)
        except (FileNotFoundError, OSError, asyncio.TimeoutError):
            continue

        table = parse_arp_table(output.decode(errors="ignore"))
        if table:
            return table

    return {}


# ---------------------------------------------------------------------------
# DNS inverso / NetBIOS
# ---------------------------------------------------------------------------
async def reverse_dns(ip: str, timeout: float = 1.0) -> str | None:
    loop = asyncio.get_running_loop()
    try:
        result = await asyncio.wait_for(
            loop.run_in_executor(None, socket.gethostbyaddr, ip),
            timeout=timeout,
        )
        return result[0]
    except (socket.herror, socket.gaierror, OSError, UnicodeError, asyncio.TimeoutError):
        return None


async def netbios_name(ip: str) -> str | None:
    """Nombre NetBIOS en Windows (nbtstat -A). En otros SO devuelve None."""
    if platform.system().lower() != "windows":
        return None

    try:
        process = await asyncio.create_subprocess_exec(
            "nbtstat",
            "-A",
            ip,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        output, _ = await asyncio.wait_for(process.communicate(), timeout=2.0)
    except (FileNotFoundError, OSError, asyncio.TimeoutError):
        return None

    for line in output.decode(errors="ignore").splitlines():
        match = re.match(r"^\s*(\S+)\s+<00>\s+UNIQUE", line, re.IGNORECASE)
        if match:
            return match.group(1)
    return None


# ---------------------------------------------------------------------------
# Fabricante por OUI (con cache y rate limit)
# ---------------------------------------------------------------------------
class OuiResolver:
    def __init__(
        self,
        cache_path: Path | None = None,
        rate_pps: float | None = 1.0,
    ) -> None:
        self.cache_path = cache_path or _DEFAULT_CACHE
        self.rate_pps = rate_pps
        self._cache: dict[str, str | None] = {}
        self._lock = asyncio.Lock()
        self._last = 0.0

        if self.cache_path.exists():
            try:
                raw = json.loads(self.cache_path.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    self._cache = {
                        str(key): (str(value) if value is not None else None)
                        for key, value in raw.items()
                    }
            except (OSError, ValueError):
                logger.warning("Cache OUI corrupta, se ignora.")

    async def _throttle(self) -> None:
        if not self.rate_pps:
            return
        async with self._lock:
            wait = (1.0 / self.rate_pps) - (time.monotonic() - self._last)
            if wait > 0:
                await asyncio.sleep(wait)
            self._last = time.monotonic()

    async def resolve(self, mac: str, session: aiohttp.ClientSession) -> str | None:
        oui = mac_to_oui(mac)
        if not oui:
            return None
        if oui in self._cache:
            return self._cache[oui]

        await self._throttle()
        endpoints = (
            f"https://api.macvendors.com/{oui}",
            f"https://api.maclookup.app/v2/macs/{oui}",
        )
        for url in endpoints:
            try:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=4)) as response:
                    if response.status != 200:
                        continue
                    if "maclookup" in url:
                        data = await response.json(content_type=None)
                        vendor = (data.get("company") or "").strip()
                        if not data.get("found"):
                            continue
                    else:
                        vendor = (await response.text()).strip()
                    if vendor and "not found" not in vendor.lower():
                        vendor = vendor.splitlines()[0].strip()
                        self._cache[oui] = vendor
                        return vendor
            except (aiohttp.ClientError, asyncio.TimeoutError, ValueError, TypeError):
                continue

        self._cache[oui] = None
        return None

    def save(self) -> None:
        try:
            self.cache_path.write_text(
                json.dumps(self._cache, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
        except OSError:
            logger.warning("No se pudo guardar la cache OUI en %s", self.cache_path)


# ---------------------------------------------------------------------------
# Pipeline completo
# ---------------------------------------------------------------------------
async def discover(
    red: str,
    inicio: int,
    fin: int,
    timeout_ms: int,
    sin_fabricante: bool = False,
    netbios: bool = False,
) -> list[Device]:
    validate_red(red)

    pings = await ping_sweep(red, inicio, fin, timeout_ms)
    arp = await arp_table()

    ips = set(pings)
    ips.update(ip for ip in arp if ip_in_range(ip, red, inicio, fin))

    devices = [
        Device(
            ip=ip,
            mac=arp.get(ip),
            ms=pings.get(ip),
            estado="Activo" if ip in pings else "Solo ARP",
        )
        for ip in sorted(ips, key=ip_sort_key)
    ]
    if not devices:
        return devices

    logger.info("Descubiertos %d dispositivos", len(devices))

    # DNS inverso en paralelo
    names = await asyncio.gather(*(reverse_dns(device.ip) for device in devices))
    for device, name in zip(devices, names, strict=True):
        device.nombre = name

    # NetBIOS solo para los que no resolvieron por DNS
    if netbios:
        pending = [device for device in devices if not device.nombre]
        if pending:
            netbios_names = await asyncio.gather(*(netbios_name(device.ip) for device in pending))
            for device, name in zip(pending, netbios_names, strict=True):
                device.nombre = name

    # Fabricantes (secuencial por el rate limit)
    if not sin_fabricante:
        resolver = OuiResolver()
        try:
            async with aiohttp.ClientSession() as session:
                for device in devices:
                    if device.mac:
                        device.fabricante = await resolver.resolve(device.mac, session)
        finally:
            resolver.save()

    return devices
