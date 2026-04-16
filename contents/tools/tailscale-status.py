#!/usr/bin/env python3
"""Status helper for the Tailscale Monitor Plasma applet.

Runs `tailscale status --json` and extracts key information.
Outputs a single JSON line consumed by the QML DataSource.
"""

import json
import socket
import subprocess
import sys

# Ports to probe on online peers
SERVICE_PORTS = {
    "ssh": 22,
    "vnc": 5900,
    "rdp": 3389,
    "nomachine": 4000,
    "http": 80,
    "https": 443,
}
PROBE_TIMEOUT = 0.3  # seconds per port


def check_port(ip, port):
    """Quick TCP connect check. Returns True if port is open."""
    try:
        s = socket.create_connection((ip, port), timeout=PROBE_TIMEOUT)
        s.close()
        return True
    except (OSError, socket.timeout):
        return False


def detect_vnc_server(ip, port=5900):
    """Detect VNC server type. Returns 'realvnc', 'other', or None."""
    try:
        s = socket.create_connection((ip, port), timeout=PROBE_TIMEOUT)
        # Server sends RFB version string
        banner = s.recv(12)
        # Reply with same version to proceed to security types
        s.sendall(banner)
        # Read security type count and types
        data = s.recv(64)
        s.close()
        if len(data) > 1:
            num_types = data[0]
            sec_types = list(data[1:1 + num_types])
            # Type 30 = RealVNC authentication
            if 30 in sec_types:
                return "realvnc"
            return "other"
    except Exception:
        pass
    return None


def probe_services(ip):
    """Check which services are available on a peer."""
    services = {}
    for name, port in SERVICE_PORTS.items():
        if name == "vnc":
            vnc_type = detect_vnc_server(ip, port)
            services["vnc"] = vnc_type is not None
            services["vnc_type"] = vnc_type or ""
        else:
            services[name] = check_port(ip, port)
    return services


def main():
    info = {
        "connected": False,
        "hostname": None,
        "dns_name": None,
        "tailscale_ip": None,
        "tailscale_ipv6": None,
        "tailnet": None,
        "exit_node": None,
        "version": None,
        "relay": None,
        "online_peers": 0,
        "total_peers": 0,
        "peers": [],
    }

    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            print(json.dumps(info))
            return

        data = json.loads(result.stdout)
    except Exception:
        print(json.dumps(info))
        return

    state = data.get("BackendState", "")
    info["connected"] = state == "Running"
    info["version"] = data.get("Version", "")

    # Self info
    self_node = data.get("Self", {})
    info["hostname"] = self_node.get("HostName", "")
    dns = self_node.get("DNSName", "")
    info["dns_name"] = dns.rstrip(".")
    info["relay"] = self_node.get("Relay", "")

    # HTTPS cert domains
    cert_domains = set(data.get("CertDomains") or [])
    info["https_url"] = "https://" + info["dns_name"] if info["dns_name"] in cert_domains else ""

    ips = data.get("TailscaleIPs", [])
    if len(ips) >= 1:
        info["tailscale_ip"] = ips[0]
    if len(ips) >= 2:
        info["tailscale_ipv6"] = ips[1]

    # Tailnet
    tailnet = data.get("CurrentTailnet", {})
    info["tailnet"] = tailnet.get("Name", "")
    magic_dns = tailnet.get("MagicDNSEnabled", False)

    # Peers
    peers_map = data.get("Peer", {})
    exit_node_name = None
    peers = []
    online_count = 0

    for _key, peer in peers_map.items():
        hostname = peer.get("HostName", "?")
        dns_name = peer.get("DNSName", "").rstrip(".")
        # Display name: first part of DNS name (the Tailscale name)
        display_name = dns_name.split(".")[0] if dns_name else hostname
        online = peer.get("Online", False)
        os_name = peer.get("OS", "")
        peer_ips = peer.get("TailscaleIPs", [])
        ip = peer_ips[0] if peer_ips else ""
        is_exit = peer.get("ExitNode", False)
        relay = peer.get("Relay", "")

        if online:
            online_count += 1
        if is_exit:
            exit_node_name = display_name

        https_url = "https://" + dns_name if (magic_dns and dns_name) else ""

        # Probe services on online peers
        services = {}
        if online and ip:
            services = probe_services(ip)

        peers.append({
            "name": display_name,
            "dns_name": dns_name,
            "https_url": https_url,
            "ip": ip,
            "os": os_name,
            "online": online,
            "exit_node": is_exit,
            "relay": relay,
            "services": services,
            "vnc_type": services.get("vnc_type", ""),
        })

    # Sort: online first, then alphabetically
    peers.sort(key=lambda p: (not p["online"], p["name"].lower()))

    info["peers"] = peers
    info["online_peers"] = online_count
    info["total_peers"] = len(peers)
    info["exit_node"] = exit_node_name

    print(json.dumps(info))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(json.dumps({"connected": False, "error": True}))
