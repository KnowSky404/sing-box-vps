# HY2 automatic certificates in instance management

新增 HY2 协议、创建实例和修改实例支持 ACME HTTP-01、Cloudflare DNS-01 与手动证书。新建默认 ACME、监听 `0.0.0.0` 接受外部 IPv4 连接；修改默认保留已有模式和地址。DNS Token 隐藏输入，ACME 客户端使用系统信任；手动证书继续支持显式证书信任。

The existing schema-1 JSON store gains an optional ACME TLS variant without changing existing manual records. It stores `tls:{enabled:true,server_name,acme:{...}}` and requires `client_trust:"system"`. The renderer selects inline certificate providers on sing-box 1.14+ and inline ACME on 1.13.x. Each instance retains its own domains, challenge options and credentials. Exported clients and ordinary Agent summaries never include ACME credentials. No ACME process or package is installed separately.

Legacy ACME/provider nodes are collected losslessly when creating a second instance. Unique provider mappings, existing identity, additional domains, custom storage, Cloudflare zone tokens and supported extensions are preserved. Unsupported fields, conflicting TLS sources, invalid ALPN and ambiguous mappings fail before publication. Existing CAS, backup, candidate checks, firewall journal, postcheck and rollback remain the write boundary. The generator-owned legacy provider is removed only after its final reference disappears; unrelated shared providers remain intact. Removing an instance does not remove certificates or the ACME cache.

HTTP-01 needs DNS pointing to the VPS and public TCP 80 reachable and usable for validation and renewal. DNS-01 needs Cloudflare DNS permissions and does not require those A/AAAA records or TCP 80. HY2 data traffic still uses its configured UDP port. The implementation does not expand firewall access for the CA challenge or claim public issuance based on service startup.

## Focused verification

Use `SINGBOX_BINARY_114` for the actual 1.14.x core and `SINGBOX_BINARY_113` for optional 1.13.x checks:

```bash
bash tests/hy2_instance_acme.sh
bash tests/hy2_instance_acme_menu.sh
bash tests/hy2_instance_acme_lifecycle.sh
bash tests/hy2_install_prompt_guidance.sh
bash tests/structured_hy2_instance_management.sh
```

These cover the additional-install entry, HTTP/DNS choices, unchanged edit defaults, hidden token input, both runtime formats, complete intake, Agent/client/SubMan materials, invalid options, legacy adoption, create/replace/delete, stale revision rejection, real core validation failure and service-restart rollback. Related manual-TLS, legacy ACME, configuration, state and sharing tests provide the scoped cross-protocol regression checks.

`tests/hy2_instance_acme_runtime.sh` requires a fresh disposable verification Docker container, an official sing-box build with ACME/QUIC, Python, OpenSSL and a separately supplied [Pebble](https://github.com/letsencrypt/pebble) executable. Copy `install.sh` and the runtime test into a repository-shaped directory, then run:

```bash
SBV_HY2_ACME_RUNTIME=1 PEBBLE_BINARY=/usr/local/bin/pebble \
  bash tests/hy2_instance_acme_runtime.sh
```

The test uses a private HTTPS trust file, a local CA, actual HTTP-01 validation on port 80, two HY2 instances, verified QUIC/TLS proxy transfers through the container non-loopback IPv4 address, cache reuse after restart, and deletion isolation. It never disables certificate verification or uses a public CA or real Cloudflare token. Keep `/tmp/hy2-acme-runtime` as the artifact bundle before removing the container. Set `HY2_ACME_LEGACY_BASELINE=1` for the legacy-provider adoption variant. This proves isolated issuance and data flow; real Cloudflare DNS-01 issuance, public reachability and production deployment remain separate acceptance boundaries.
