from __future__ import annotations

import asyncio
import socket

import pytest

from scan_red.portscanner.connect import ConnectScanner
from scan_red.portscanner.syn import SynScanner


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def test_connect_scanner_requires_authorization() -> None:
    with pytest.raises(PermissionError):
        ConnectScanner(authorized=False)


def test_syn_scanner_requires_authorization() -> None:
    with pytest.raises(PermissionError):
        SynScanner(authorized=False)


def test_connect_scanner_detects_open_and_closed_ports() -> None:
    async def scenario() -> None:
        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
            writer.close()
            await writer.wait_closed()

        server = await asyncio.start_server(handle, "127.0.0.1", 0)
        open_port = int(server.sockets[0].getsockname()[1])
        closed_port = _free_port()

        try:
            scanner = ConnectScanner(timeout=0.5, rate_limit_pps=None, authorized=True)
            result = await scanner.scan_host("127.0.0.1", [open_port, closed_port])
            states = {item.port: item.state for item in result.tcp}
            assert states[open_port] == "open"
            assert states[closed_port] in {"closed", "filtered"}
            assert open_port in result.open_ports
        finally:
            server.close()
            await server.wait_closed()

    asyncio.run(scenario())


def test_connect_scanner_scan_hosts() -> None:
    async def scenario() -> None:
        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
            writer.close()
            await writer.wait_closed()

        server = await asyncio.start_server(handle, "127.0.0.1", 0)
        open_port = int(server.sockets[0].getsockname()[1])
        try:
            scanner = ConnectScanner(timeout=0.5, rate_limit_pps=None, authorized=True)
            results = await scanner.scan_hosts(["127.0.0.1"], [open_port])
            assert results["127.0.0.1"].open_ports == [open_port]
        finally:
            server.close()
            await server.wait_closed()

    asyncio.run(scenario())


def test_connect_scanner_only_public_skips_private_ips() -> None:
    async def scenario() -> None:
        scanner = ConnectScanner(
            timeout=0.2,
            rate_limit_pps=None,
            authorized=True,
            only_public=True,
        )
        result = await scanner.scan_host("192.168.1.1", [80])
        assert result.tcp == []

    asyncio.run(scenario())


def test_connect_scanner_rejects_invalid_ports() -> None:
    with pytest.raises(ValueError):
        ConnectScanner._normalize_ports([0])
    with pytest.raises(ValueError):
        ConnectScanner._normalize_ports([65536])
