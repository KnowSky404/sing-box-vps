"""Throwaway TCP/UDP marker service for controlled VPN acceptance."""
import http.server
import json
import socket
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"marker": self.path, "peer": self.client_address[0]}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def udp():
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.bind(("0.0.0.0", 21911))
    while True:
        payload, peer = listener.recvfrom(4096)
        listener.sendto(json.dumps({"marker": payload.decode(), "peer": peer[0]}).encode(), peer)


threading.Thread(target=udp, daemon=True).start()
http.server.ThreadingHTTPServer(("0.0.0.0", 21910), Handler).serve_forever()
