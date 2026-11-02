#!/usr/bin/env python3
"""Isolated loopback probes for FQDN filtering; never dial public test answers."""

import http.server
import json
import pathlib
import re
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time


core, policy_file, custom_policies_file, scope_rules_file = sys.argv[1:]
policy = json.loads(pathlib.Path(policy_file).read_text())
custom_policies = json.loads(pathlib.Path(custom_policies_file).read_text())
scope_rules = json.loads(pathlib.Path(scope_rules_file).read_text())
assert policy["protection_rules"][0]["action"] == "resolve"
marker = b"sbv-private-domain-marker"


class Marker(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(marker)

    def log_message(self, *_args):
        pass


httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Marker)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dns.bind(("127.0.0.1", 0))
dns.settimeout(0.2)
stop = threading.Event()


def dns_loop():
    while not stop.is_set():
        try:
            query, peer = dns.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            if stop.is_set():
                break
            raise
        offset, labels = 12, []
        while query[offset]:
            length = query[offset]
            labels.append(query[offset + 1 : offset + length + 1].decode("ascii"))
            offset += length + 1
        offset += 1
        qtype = struct.unpack("!H", query[offset : offset + 2])[0]
        name = ".".join(labels)
        if name.startswith("mixed."):
            addresses = ["1.1.1.1", "127.0.0.1"]
        elif name.startswith("reversed."):
            addresses = ["127.0.0.1", "1.1.1.1"]
        elif name.startswith("last."):
            addresses = ["9.9.9.9"]
        else:
            addresses = ["1.1.1.1"]
        if qtype != 1:
            addresses = []
        response = query[:2] + struct.pack("!HHHHH", 0x8180, 1, len(addresses), 0, 0)
        response += query[12 : offset + 4]
        for address in addresses:
            response += b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 30, 4) + socket.inet_aton(address)
        dns.sendto(response, peer)


threading.Thread(target=dns_loop, daemon=True).start()


def probe(workspace, name, *, resolve=True, controlled_dns=False, domain="localhost", final="direct", rendered=None, isolated_egress=False, inbound_tag="probe-in"):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    dns_server = {"type": "local", "tag": "local-dns"}
    if controlled_dns:
        dns_server = {"type": "udp", "tag": "local-dns", "server": "127.0.0.1", "server_port": dns.getsockname()[1]}
    rules = [{"inbound": [inbound_tag], "action": "sniff"}] + (
        policy["protection_rules"] if rendered is None else rendered["rules"]
    )
    if not resolve:
        rules = [rule for rule in rules if rule["action"] != "resolve"]
    outbounds = [{"type": "direct", "tag": "direct", "domain_resolver": "local-dns"}, {"type": "block", "tag": "block"}]
    if isolated_egress:
        # Exercise real route matching for public answers and both outbound
        # tags, while making every possible dial stay inside the process.
        # This does not claim a real WARP tunnel or public connectivity test.
        outbounds = [{"type": "block", "tag": tag} for tag in ("direct", "warp-ep", "block")]
    config = {
        "log": {"level": "debug"},
        "dns": {"servers": [dns_server], "strategy": "ipv4_only"},
        "inbounds": [{"type": "mixed", "tag": inbound_tag, "listen": "127.0.0.1", "listen_port": port}],
        "outbounds": outbounds,
        "route": {"rule_set": (policy if rendered is None else rendered)["rule_sets"], "rules": rules, "final": final, "default_domain_resolver": "local-dns"},
    }
    config_file = workspace / (name + ".json")
    config_file.write_text(json.dumps(config))
    subprocess.run([core, "check", "-c", str(config_file)], check=True, capture_output=True)
    log_file = workspace / (name + ".log")
    with log_file.open("w") as log:
        process = subprocess.Popen([core, "run", "-c", str(config_file)], stdout=log, stderr=log)
        try:
            for _ in range(60):
                if process.poll() is not None:
                    raise AssertionError(log_file.read_text())
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.05):
                        break
                except OSError:
                    time.sleep(0.05)
            else:
                raise AssertionError("isolated proxy did not start")
            result = subprocess.run(
                ["curl", "--noproxy", "", "--max-time", "3", "--silent", "--show-error", "--proxy", f"socks5h://127.0.0.1:{port}", f"http://{domain}:{httpd.server_port}/"],
                capture_output=True,
            )
        finally:
            process.terminate()
            try:
                process.wait(5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    return result, log_file.read_text()


try:
    with tempfile.TemporaryDirectory(prefix="sbv-private-runtime.", dir="/tmp") as temporary:
        workspace = pathlib.Path(temporary)
        result, _ = probe(workspace, "without-resolve", resolve=False)
        assert result.returncode == 0 and result.stdout == marker, "control did not reproduce unresolved FQDN bypass"
        result, log = probe(workspace, "localhost-private")
        assert result.returncode != 0 and marker not in result.stdout
        assert re.search(r"match\[\d+\].*ip_is_private=true", log), log
        # The fallback is block, so even a failing assertion cannot make a
        # connection to the public address returned by this local DNS server.
        result, log = probe(workspace, "mixed-private-public", controlled_dns=True, domain="mixed.fixture.invalid", final="block")
        assert result.returncode != 0 and re.search(r"match\[\d+\].*ip_is_private=true", log), log
        result, log = probe(workspace, "domain-retained", controlled_dns=True, domain="ads.fixture.invalid", final="block")
        assert result.returncode != 0 and re.search(r"match\[\d+\].*sbv-adblock-inline", log), log
        result, log = probe(workspace, "ad-exception", controlled_dns=True, domain="allow.ads.fixture.invalid", final="block")
        assert result.returncode != 0 and not re.search(r"match\[\d+\].*sbv-adblock-inline", log), log

        # Core acceptance alone does not prove logical-rule scope. The exact
        # managed ad+allow condition must leave an independent listener alone.
        ad_rule = next(rule for rule in policy["protection_rules"] if rule.get("type") == "logical")
        assert "inbound" not in ad_rule and ad_rule["rules"][0] == {"inbound": ["probe-in"]}
        for domain in ("ads.fixture.invalid", "allow.ads.fixture.invalid"):
            result, log = probe(workspace, "operator-" + domain, controlled_dns=True, domain=domain,
                                final="block", isolated_egress=True, inbound_tag="operator-in")
            assert result.returncode != 0 and not re.search(r"match\[\d+\].*sbv-adblock-inline", log), log
        result, log = probe(workspace, "operator-private-control", inbound_tag="operator-in")
        assert result.returncode == 0 and result.stdout == marker, log

        # These unsafe manual rules explain why the installer must reject
        # conflicting order: the real core routes to the owned loopback marker
        # before private filtering. Positive and proven AND scopes do not.
        for category, manual_rules in scope_rules.items():
            for index, manual_rule in enumerate(manual_rules):
                rendered = {"rule_sets": policy["rule_sets"], "rules": [manual_rule] + policy["protection_rules"]}
                result, log = probe(workspace, f"manual-{category}-{index}", rendered=rendered)
                if category == "overlap":
                    assert result.returncode == 0 and result.stdout == marker, (manual_rule, log)
                else:
                    assert result.returncode != 0 and marker not in result.stdout, (manual_rule, log)
                    assert re.search(r"match\[\d+\].*ip_is_private=true", log), log

        result, _ = probe(workspace, "custom-without-resolve", rendered=custom_policies["reject-cidr"], resolve=False)
        assert result.returncode == 0 and result.stdout == marker, "custom CIDR control did not reproduce FQDN bypass"
        for name, rendered in custom_policies.items():
            assert rendered["protection_rules"] == [], "private=false unexpectedly enabled private/ad filtering"
            for domain, controlled_dns, public in (
                ("127.0.0.1", False, False),
                ("localhost", False, False),
                ("mixed.fixture.invalid", True, False),
                ("reversed.fixture.invalid", True, False),
                ("public.fixture.invalid", True, True),
            ):
                cidr = "1.1.1.0/24" if public else "127.0.0.0/8"
                index = next(
                    index + 1 for index, rule in enumerate(rendered["rules"])
                    if rule.get("ip_cidr") == [cidr] or rule.get("rule_set") == ["sbv-rule-ip-source"]
                )
                result, log = probe(workspace, name + "-" + domain, rendered=rendered,
                                    controlled_dns=controlled_dns, domain=domain, final="block", isolated_egress=True)
                assert result.returncode != 0 and marker not in result.stdout
                assert f"match[{index}]" in log, (name, domain, log)
                if domain not in ("127.0.0.1",):
                    assert "resolved [" in log, (name, domain, log)

            # A terminal domain rule before the IP stage must not acquire a
            # new DNS dependency. A domain rule after resolution must still
            # see the original hostname when no CIDR matched any answer.
            for domain in ("first.fixture.invalid", "last.fixture.invalid"):
                index = next(index + 1 for index, rule in enumerate(rendered["rules"])
                             if rule.get("domain") == [domain])
                result, log = probe(workspace, name + "-" + domain, rendered=rendered,
                                    controlled_dns=True, domain=domain, final="block", isolated_egress=True)
                assert result.returncode != 0 and f"match[{index}]" in log, (name, domain, log)
                if domain.startswith("first.") or not name.endswith("-cidr"):
                    assert "resolved [" not in log, (name, domain, log)
                else:
                    assert "resolved [9.9.9.9]" in log, (name, domain, log)
finally:
    stop.set()
    httpd.shutdown()
    httpd.server_close()
    dns.close()

print("Private/custom IP routing, mixed DNS answers, direct/WARP/reject actions, source/binary sets and domain precedence runtime probes passed")
