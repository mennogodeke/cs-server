#!/usr/bin/env python3
"""Minimal interactive Source RCON client for the tunnel `gameday rcon` opens.

Usage:
    ./bin/gameday rcon              # in one terminal, leave it running
    ./bin/gameday-rcon-client.py    # in another terminal
"""
import socket
import struct
import subprocess
import sys

HOST = "127.0.0.1"
PORT = 27016


def send_packet(sock, id_, type_, body):
    payload = struct.pack("<ii", id_, type_) + body.encode() + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(payload)) + payload)


def recv_packet(sock):
    size = struct.unpack("<i", sock.recv(4))[0]
    data = b""
    while len(data) < size:
        data += sock.recv(size - len(data))
    id_, type_ = struct.unpack("<ii", data[:8])
    body = data[8:-2].decode(errors="replace")
    return id_, type_, body


def main():
    password = subprocess.run(
        ["terraform", "-chdir=terraform/session", "output", "-raw", "rcon_password"],
        capture_output=True, text=True, check=False,
    ).stdout.strip()
    if not password:
        password = input("RCON password: ").strip()

    sock = socket.create_connection((HOST, PORT), timeout=5)
    send_packet(sock, 1, 3, password)  # SERVERDATA_AUTH
    id_, _type, _body = recv_packet(sock)
    if id_ == -1:
        print("AUTH FAILED — wrong password?")
        sys.exit(1)
    print(f"Connected to {HOST}:{PORT}. Type RCON commands, Ctrl-D to quit.")

    req_id = 2
    while True:
        try:
            cmd = input("rcon> ").strip()
        except EOFError:
            break
        if not cmd:
            continue
        send_packet(sock, req_id, 2, cmd)  # SERVERDATA_EXECCOMMAND
        _id, _type, body = recv_packet(sock)
        print(body)
        req_id += 1


if __name__ == "__main__":
    main()
