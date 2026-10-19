"""Escaner TCP por paquetes SYN (requiere scapy y permisos elevados)."""

from __future__ import annotations

import asyncio
import logging
import random
from collections.abc import Iterable

from ..models import HostResult, PortResult
from .legal import is_external_ip, require_authorization

logger = logging.getLogger(__name__)


class SynScanner:
    """Escaneo SYN con scapy.

    Necesita permisos de administrador/root y, en Windows, Npcap instalado.
    Se importa de forma perezosa para que el resto del paquete funcione sin scapy.
    """

    def __init__(
        self,
        timeout: float = 2.0,
        authorized: bool = False,
        only_public: bool = False,
    ) -> None:
        require_authorization(authorized)
        try:
            import scapy.all  # noqa: F401
        except ImportError as exc:  # pragma: no cover - depende del entorno
            raise RuntimeError(
                "El motor SYN requiere scapy. Instala con: "
                "pip install 'scan-red[syn]' y ejecuta como administrador."
            ) from exc

        if timeout <= 0:
            raise ValueError("timeout debe ser mayor que 0")
        self.timeout = timeout
        self.only_public = only_public

    @staticmethod
    def _normalize_ports(ports: Iterable[int]) -> list[int]:
        normalized: list[int] = []
        for raw in ports:
            port = int(raw)
            if not 1 <= port <= 65535:
                raise ValueError(f"Puerto fuera de rango: {port}")
            normalized.append(port)
        return normalized

    def _scan_sync(self, ip: str, ports: list[int]) -> HostResult:
        from scapy.all import IP, TCP, sr  # import local: dependencia opcional

        packets = [
            IP(dst=ip)
            / TCP(
                sport=random.randint(1024, 65535),
                dport=port,
                flags="S",
            )
            for port in ports
        ]

        try:
            answered, _ = sr(packets, timeout=self.timeout, verbose=0)
        except PermissionError as exc:
            raise RuntimeError(
                "El motor SYN requiere permisos de administrador/root (y Npcap en Windows)."
            ) from exc
        except OSError as exc:
            raise RuntimeError(
                f"No se pudo enviar paquetes SYN. Verifica Npcap/permisos: {exc}"
            ) from exc

        states = {port: PortResult(port, "filtered") for port in ports}
        for _sent, received in answered:
            if not received.haslayer(TCP):
                continue
            tcp = received[TCP]
            port = int(tcp.sport)
            if port not in states:
                continue
            flags = int(tcp.flags)
            if flags & 0x02 and flags & 0x10:  # SYN + ACK
                states[port] = PortResult(port, "open")
            elif flags & 0x04:  # RST
                states[port] = PortResult(port, "closed")

        return HostResult(ip=ip, tcp=[states[port] for port in ports])

    async def scan_host(self, ip: str, ports: Iterable[int]) -> HostResult:
        if self.only_public and not is_external_ip(ip):
            logger.warning("IP %s no es publica, se omite.", ip)
            return HostResult(ip=ip)
        port_list = self._normalize_ports(ports)
        return await asyncio.to_thread(self._scan_sync, ip, port_list)

    async def scan_hosts(self, ips: Iterable[str], ports: Iterable[int]) -> dict[str, HostResult]:
        port_list = self._normalize_ports(ports)
        results: dict[str, HostResult] = {}
        ip_list = list(ips)
        for index, ip in enumerate(ip_list, start=1):
            results[ip] = await self.scan_host(ip, port_list)
            if index % 10 == 0:
                logger.info("SYN: %d/%d hosts", index, len(ip_list))
        return results
