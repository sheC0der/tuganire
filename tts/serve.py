"""Starts the service on one socket that accepts both IPv6 (Railway's private
network) and IPv4 (health checks, local Docker). uvicorn's own --host :: listens
on IPv6 only."""

import asyncio
import os
import socket

import uvicorn


def main() -> None:
    port = int(os.environ.get("PORT", "8000"))
    sock = socket.create_server(("::", port), family=socket.AF_INET6, dualstack_ipv6=True)
    config = uvicorn.Config("app:create_app", factory=True)
    asyncio.run(uvicorn.Server(config).serve(sockets=[sock]))


if __name__ == "__main__":
    main()
