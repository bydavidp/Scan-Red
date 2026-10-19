"""Escaner TCP por conexion completa (connect scan)."""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Iterable

from ..models import HostResult, PortResult
from .legal import is_external_ip, require_authorization

logger = logging.getLogger(__name__)


class ConnectScanner:
    """Escanea puertos TCP abriendo conexiones reales.

    No requiere privilegios de administrador, pero deja rastro en los logs
    del host escaneado. Usar solo en redes autorizadas.
    """

    def __init__(
        self,
        timeout: float = 1.0,
        max_concurrency: int = 200,
        rate_limit_pps: float | None = 500.0,
        authorized: bool = False,
        only_public: bool = False,
    ) -> None:
        require_authorization(authorized)
        if timeout <= 0:
            raise ValueError("timeout debe ser mayor que 0")
        if max_concurrency <= 0:
            raise ValueError("max_concurrency debe ser mayor que 0")

        self.timeout = timeout
        self.max_concurrency = max_concurrency
        self.rate_limit_pps = rate_limit_pps
        self.only_public = only_public
        self._sem: asyncio.Semaphore | None = None
        self._rate_lock = asyncio.Lock()
        self._last_ts = 0.0

    # ------------------------------------------------------------------
    # Utilidades internas
    # ------------------------------------------------------------------
    @staticmethod
    def _normalize_ports(ports: Iterable[int]) -> list[int]:
        normalized: list[int] = []
        for raw in ports:
            port = int(raw)
            if not 1 <= port <= 65535:
                raise ValueError(f"Puerto fuera de rango: {port}")
            normalized.append(port)
        return normalized

    def _ensure_semaphore(self) -> None:
        if self._sem is None:
            self._sem = asyncio.Semaphore(self.max_concurrency)

    async def _acquire_rate(self) -> None:
        if not self.rate_limit_pps:
            return
        async with self._rate_lock:
            interval = 1.0 / self.rate_limit_pps
            now = time.monotonic()
            wait = interval - (now - self._last_ts)
            if wait > 0:
                await asyncio.sleep(wait)
            self._last_ts = time.monotonic()

    async def _check_port(self, ip: str, port: int) -> PortResult:
        assert self._sem is not None
        await self._acquire_rate()
        async with self._sem:
            writer: asyncio.StreamWriter | None = None
            try:
                _, writer = await asyncio.wait_for(
                    asyncio.open_connection(ip, port), timeout=self.timeout
                )
                return PortResult(port, "open")
            except asyncio.TimeoutError:
                return PortResult(port, "filtered")
            except ConnectionRefusedError:
                return PortResult(port, "closed")
            except OSError:
                return PortResult(port, "error")
            finally:
                if writer is not None:
                    writer.close()
                    try:
                        await writer.wait_closed()
                    except Exception:  # noqa: BLE001 - cierre best-effort
                        pass

    # ------------------------------------------------------------------
    # API publica
    # ------------------------------------------------------------------
    async def scan_host(self, ip: str, ports: Iterable[int]) -> HostResult:
        """Escanea todos los puertos indicados de un host."""
        if self.only_public and not is_external_ip(ip):
            logger.warning("IP %s no es publica, se omite.", ip)
            return HostResult(ip=ip)

        port_list = self._normalize_ports(ports)
        self._ensure_semaphore()
        results = await asyncio.gather(*(self._check_port(ip, port) for port in port_list))
        return HostResult(ip=ip, tcp=list(results))

    async def scan_hosts(self, ips: Iterable[str], ports: Iterable[int]) -> dict[str, HostResult]:
        """Escanea una lista explicita de IPs (las del ping sweep)."""
        ip_list = list(ips)
        if not ip_list:
            return {}

        port_list = self._normalize_ports(ports)
        self._ensure_semaphore()

        tasks = [asyncio.create_task(self.scan_host(ip, port_list)) for ip in ip_list]
        results: dict[str, HostResult] = {}
        for done, future in enumerate(asyncio.as_completed(tasks), start=1):
            result = await future
            results[result.ip] = result
            if done % 25 == 0:
                logger.info("Puertos: %d/%d hosts", done, len(tasks))
        return results
