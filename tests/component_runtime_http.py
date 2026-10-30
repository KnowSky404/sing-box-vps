import http.server,json,pathlib,socket,sys,time
port, directory= int(sys.argv[1]),pathlib.Path(sys.argv[2])
class Handler(http.server.BaseHTTPRequestHandler):
 def do_HEAD(self): self.do_GET()
 def do_GET(self):
  peer=self.client_address[0]
  if self.path=='/health':
   if peer=='127.0.0.2' and (directory/'fail-a').exists():
    self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   if peer=='127.0.0.3': time.sleep(0.2)
  if self.path=='/rules.json':
   body=b'{"version":3,"rules":[{"domain":["runtime.example"]}]}'
   if self.headers.get('X-Component-Marker')!='shared-client-v1' or peer!='127.0.0.2':
    self.send_error(403);return
   (directory/'shared-request.json').write_text(json.dumps({'peer':peer,'version':self.request_version,'header':self.headers['X-Component-Marker']}))
  else: body=peer.encode()
  self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def log_message(self,*args): pass
http.server.ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()
