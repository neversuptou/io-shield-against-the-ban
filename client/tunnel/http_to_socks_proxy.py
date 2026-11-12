"""Loopback-only HTTP CONNECT proxy that forwards every upstream socket via SOCKS5.

Claude Code supports HTTP(S) proxy variables but not SOCKS directly. This bridge
lets it use the existing SSH SOCKS listener without exposing a new network port.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from urllib.parse import urlsplit

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 18082
SOCKS_HOST = "127.0.0.1"
SOCKS_PORT = 18081
MAX_HEADER_BYTES = 64 * 1024

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


async def socks_connect(host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
    reader, writer = await asyncio.open_connection(SOCKS_HOST, SOCKS_PORT)
    try:
        writer.write(b"\x05\x01\x00")
        await writer.drain()
        if await reader.readexactly(2) != b"\x05\x00":
            raise ConnectionError("SSH SOCKS proxy rejected unauthenticated negotiation")

        host_bytes = host.encode("idna")
        if len(host_bytes) > 255:
            raise ValueError(f"Hostname is too long for SOCKS5: {host!r}")
        request = b"\x05\x01\x00\x03" + bytes([len(host_bytes)]) + host_bytes + port.to_bytes(2, "big")
        writer.write(request)
        await writer.drain()

        version, status, _reserved, address_type = await reader.readexactly(4)
        if version != 5 or status != 0:
            raise ConnectionError(f"SSH SOCKS proxy rejected {host}:{port} (status {status})")
        if address_type == 1:
            reply_size = 4
        elif address_type == 3:
            reply_size = (await reader.readexactly(1))[0]
        elif address_type == 4:
            reply_size = 16
        else:
            raise ConnectionError(f"SSH SOCKS proxy returned unknown address type {address_type}")
        await reader.readexactly(reply_size + 2)
        return reader, writer
    except BaseException:
        writer.close()
        with contextlib.suppress(Exception):
            await writer.wait_closed()
        raise


async def relay(source: asyncio.StreamReader, target: asyncio.StreamWriter) -> None:
    try:
        while data := await source.read(64 * 1024):
            target.write(data)
            await target.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        with contextlib.suppress(Exception):
            target.write_eof()


async def proxy_connection(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
    peer = client_writer.get_extra_info("peername")
    upstream_writer: asyncio.StreamWriter | None = None
    try:
        raw_headers = await client_reader.readuntil(b"\r\n\r\n")
        if len(raw_headers) > MAX_HEADER_BYTES:
            raise ValueError("HTTP proxy request headers exceed 64 KiB")
        header_text = raw_headers.decode("iso-8859-1")
        lines = header_text.split("\r\n")
        method, target, version = lines[0].split(" ", 2)

        if method.upper() == "CONNECT":
            host, separator, port_text = target.rpartition(":")
            if not separator or not host or not port_text.isdigit():
                raise ValueError("CONNECT target must be host:port")
            upstream_reader, upstream_writer = await socks_connect(host.strip("[]"), int(port_text))
            client_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await client_writer.drain()
        else:
            parsed = urlsplit(target)
            if parsed.scheme != "http" or not parsed.hostname:
                raise ValueError("Only absolute http:// URLs are supported for non-CONNECT requests")
            upstream_reader, upstream_writer = await socks_connect(parsed.hostname, parsed.port or 80)
            path = parsed.path or "/"
            if parsed.query:
                path += "?" + parsed.query
            forwarded_headers = [line for line in lines[1:] if not line.lower().startswith("proxy-connection:")]
            request = "\r\n".join([f"{method} {path} {version}", *forwarded_headers]).encode("iso-8859-1")
            upstream_writer.write(request)
            await upstream_writer.drain()

        await asyncio.gather(relay(client_reader, upstream_writer), relay(upstream_reader, client_writer))
    except (ConnectionError, ValueError, UnicodeError, asyncio.LimitOverrunError, asyncio.IncompleteReadError) as exc:
        logging.warning("Rejected proxy request from %s: %s", peer, exc)
        with contextlib.suppress(Exception):
            client_writer.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
            await client_writer.drain()
    finally:
        if upstream_writer is not None:
            upstream_writer.close()
            with contextlib.suppress(Exception):
                await upstream_writer.wait_closed()
        client_writer.close()
        with contextlib.suppress(Exception):
            await client_writer.wait_closed()


async def main() -> None:
    server = await asyncio.start_server(proxy_connection, LISTEN_HOST, LISTEN_PORT, limit=MAX_HEADER_BYTES)
    logging.info("HTTP CONNECT proxy listening on %s:%s via SOCKS %s:%s", LISTEN_HOST, LISTEN_PORT, SOCKS_HOST, SOCKS_PORT)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
