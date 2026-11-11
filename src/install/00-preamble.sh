#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 2026111102
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026111102"
readonly SB_SUPPORT_MAX_VERSION="1.14.4"
# A single IPv6 wildcard socket accepts IPv4 and IPv6 in sing-box on Linux.
readonly SB_DEFAULT_LISTEN_ADDRESS="::"
readonly SB_CONFIG_SCHEMA_1_14_MIN_VERSION="1.14.0"
readonly AGENT_OUTPUT_SCHEMA_VERSION="1"
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly UI_COMPACT_MAX_WIDTH=72
# Resolve the account home independently of sudo/HOME and systemd environments.
SB_ROOT_HOME=$(getent passwd 0 | cut -d: -f6)
readonly SB_ROOT_HOME
readonly SB_DATA_ROOT="${SB_ROOT_HOME}/.sing-box-vps"
readonly SB_PROJECT_DIR="${SB_DATA_ROOT}/runtime"
readonly SBV_LINK_PATH="/usr/local/bin/sbv"
readonly SINGBOX_LINK_PATH="/usr/local/bin/sing-box"
readonly SINGBOX_SERVICE_LINK_PATH="/etc/systemd/system/sing-box.service"
readonly SBV_LOG_FILE="${SB_DATA_ROOT}/logs/sbv.log"
readonly SB_KEY_FILE="${SB_PROJECT_DIR}/reality.key"
readonly SB_WARP_KEY_FILE="${SB_PROJECT_DIR}/warp.key"
readonly SB_WARP_REGISTRATION_PENDING_FILE="${SB_PROJECT_DIR}.warp-registration.pending.json"
readonly SB_WARP_ROUTE_SETTINGS_FILE="${SB_PROJECT_DIR}/warp-routing.env"
readonly SB_WARP_DOMAINS_FILE="${SB_PROJECT_DIR}/warp-domains.txt"
readonly SB_WARP_REMOTE_RULESETS_FILE="${SB_PROJECT_DIR}/warp-remote-rule-sets.txt"
readonly SB_WARP_LOCAL_RULESET_DIR="${SB_PROJECT_DIR}/rule-set/warp"
readonly SB_ROUTING_POLICY_FILE="${SB_PROJECT_DIR}/routing-policy.json"
readonly SB_ROUTING_TRANSACTION_DIR="${SB_PROJECT_DIR}.rules-write.lock"
readonly SB_ROUTING_PREVIOUS_DIR="${SB_PROJECT_DIR}.rules-previous"
readonly SB_STACK_STATE_FILE="${SB_PROJECT_DIR}/stack-mode.env"
readonly SB_MEDIA_CHECK_DIR="${SB_DATA_ROOT}/modules/media-check"
readonly SB_MEDIA_CHECK_SCRIPT="${SB_MEDIA_CHECK_DIR}/region_restriction_check.sh"
readonly SB_PROTOCOL_STATE_DIR="${SB_PROJECT_DIR}/protocols"
readonly SB_PROTOCOL_INDEX_FILE="${SB_PROTOCOL_STATE_DIR}/index.env"
readonly SB_COMPONENT_STATE_FILE="${SB_PROJECT_DIR}/components.json"
readonly SB_COMPONENT_TRANSACTION_DIR="${SB_PROJECT_DIR}.component-write.lock"
readonly SB_COMPONENT_STATE_SCHEMA_VERSION="1"
readonly MANAGED_REDIRECT_POLICY_CHAIN_PREFIX="SBVR_"
readonly MANAGED_REDIRECT_POLICY_COMMENT_PREFIX="sbv-redirect-"
readonly MANAGED_TPROXY_POLICY_CHAIN_PREFIX="SBVT_"
readonly MANAGED_TPROXY_POLICY_COMMENT_PREFIX="sbv-tproxy-"
readonly SB_REALITY_QOS_FILTER_STATE_FILE="${SB_PROJECT_DIR}/reality-qos.filters"
readonly SB_REALITY_QOS_FILTER_PREF_START="32001"
readonly SB_REALITY_QOS_BURST="512k"
readonly SB_ACME_DATA_DIR="${SB_PROJECT_DIR}/acme"
readonly SINGBOX_BIN_PATH="${SB_DATA_ROOT}/bin/sing-box"
readonly SB_NAIVE_LIBRARY_MARKER="${SB_PROJECT_DIR}/libcronet.sha256"
readonly SBV_BIN_PATH="${SB_DATA_ROOT}/bin/sbv"
readonly SBV_UPDATE_URL="https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh"
readonly SBV_SCRIPT_MIN_SIZE="1024"
readonly SBV_ARTIFACT_MIN_SIZE="128"
readonly SBV_CURL_CONNECT_TIMEOUT="10"
readonly SBV_CURL_MAX_TIME="60"
readonly SBV_CURL_RETRY_COUNT="2"
readonly SBV_CURL_RETRY_DELAY="1"
readonly SBV_CURL_STDERR_MAX_BYTES="4096"
readonly SINGBOX_CONFIG_DIR="${SB_PROJECT_DIR}"
readonly SINGBOX_CONFIG_FILE="${SB_PROJECT_DIR}/config.json"
readonly SINGBOX_SERVICE_FILE="${SB_DATA_ROOT}/systemd/sing-box.service"
readonly SB_UPGRADE_BACKUP_ROOT="${SB_DATA_ROOT}/backups/upgrades"
readonly WARP_AI_ROUTE_DOMAINS_JSON='["gemini.google.com","aistudio.google.com","generativelanguage.googleapis.com","copilot.microsoft.com"]'
readonly WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON='["openai.com","chatgpt.com","oaistatic.com","oaiusercontent.com","anthropic.com","claude.ai","perplexity.ai","x.ai","cursor.com","cursor.sh","google.com","googleapis.com","gstatic.com","googleusercontent.com","gvt1.com","recaptcha.net"]'
readonly WARP_STREAM_ROUTE_DOMAINS_JSON='[]'
readonly WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON='["netflix.com","nflxvideo.net","nflximg.net","nflxext.com","nflxso.net","disneyplus.com","disney-plus.net","dssott.com","bamgrid.com","hulu.com","huluim.com","hulustream.com","max.com","primevideo.com","amazonvideo.com","media-amazon.com"]'
readonly MEDIA_CHECK_BACKEND_NAME="RegionRestrictionCheck"
readonly MEDIA_CHECK_BACKEND_AUTHOR="1-stream"
readonly MEDIA_CHECK_BACKEND_REPO_URL="https://github.com/1-stream/RegionRestrictionCheck"
readonly MEDIA_CHECK_BACKEND_SCRIPT_URL="https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/main/check.sh"
readonly SB_HIGH_PORT_MIN="60000"
readonly SB_HIGH_PORT_MAX="65535"
readonly SB_REALITY_CHECKER_VERSION="0.3.0"
readonly SB_REALITY_CHECKER_COMMIT="fc1c06ef4f46b81ad05b0aa2bf24378c64833682"
readonly SB_REALITY_CHECKER_SHA256="f2446d5bc75ed77289a29adf8d85bc87efdbfa289e6a926f806b54b0fd79c1a3"
readonly SB_REALITY_CHECKER_URL="https://raw.githubusercontent.com/KnowSky404/reality-target-checker/${SB_REALITY_CHECKER_COMMIT}/reality-target-checker.sh"
readonly SB_REALITY_DISCOVER_SHA256="f806106efff7f3cbe219175d4f0c09f388d5304158d0e0d43e9220fefea6374d"
readonly SB_REALITY_SOURCES_SHA256="de028f4eec658eba6f789b30a51d558d9565337fccb02c2358ae76643f0ff33c"
# Institution locations, not hosting/IP guarantees. Every candidate still needs
# a fresh DNS-scoped checker result and explicit consent for ancillary warnings.
# Development evidence: docs/verification/reality-region-candidates.json.
# Pools contain at most five verified seeds; never pad them with failing sites.
# Fields: region|category|institution|domain. Official sources live in the Wiki.
readonly SB_REALITY_REGION_CANDIDATES=(
  'HK|bank|汇丰香港|www.hsbc.com.hk'
  'HK|bank|东亚银行|www.hkbea.com'
  'HK|government|香港政府一站通|www.gov.hk'
  'HK|university|香港大学|www.hku.hk'
  'HK|university|香港城市大学|www.cityu.edu.hk'
  'US-LAX|bank|City National Bank|www.cnb.com'
  'US-LAX|bank|Preferred Bank|www.preferredbank.com'
  'US-LAX|government|City of Los Angeles|lacity.gov'
  'US-LAX|university|UCLA|www.ucla.edu'
  'US-LAX|university|University of Southern California|www.usc.edu'
  'DE-FRA|bank|Deutsche Bank|www.db.com'
  'DE-FRA|bank|Frankfurter Volksbank Rhein/Main|www.frankfurter-volksbank.de'
  'DE-FRA|government|Stadt Frankfurt am Main|frankfurt.de'
  'DE-FRA|university|Goethe University Frankfurt|www.uni-frankfurt.de'
  'DE-FRA|university|Frankfurt School of Finance & Management|www.frankfurt-school.de'
  'JP-TYO|bank|SMBC信托银行|www.smbctb.co.jp'
  'JP-TYO|bank|SBI新生银行|www.sbishinseibank.co.jp'
  'JP-TYO|government|东京都政府|www.metro.tokyo.lg.jp'
  'JP-TYO|university|庆应义塾大学|www.keio.ac.jp'
  'JP-TYO|university|早稻田大学|www.waseda.jp'
  'KR-SEL|bank|渣打银行韩国|www.sc.co.kr'
  'KR-SEL|university|首尔大学|www.snu.ac.kr'
  'KR-SEL|university|汉阳大学|www.hanyang.ac.kr'
)
# Runtime capability source of truth. Fields are decoded by protocol_registry_json.
# IDs/aliases are data; dispatch below always calls explicit, literal handlers.
# The legacy vless alias intentionally remains the REALITY preset.
readonly SB_PROTOCOL_REGISTRY=(
  'vless-reality|vless+reality|vless-reality|vless|reality|inbound|vless|VLESS + REALITY|vless-in|1||vless|tcp|tcp,udp|1.13.0|true|none|vless|tcp_loopback|{"multi_instance":true,"per_instance_outbound":["default","direct","warp"],"qos":{"upload_mbps":true,"download_mbps":true},"share_link":true,"qr":true,"subman_sync":true}|vless,vless+reality|build_vless_inbound_json,build_vless_reality_route_rules_json,build_client_vless_reality_outbounds,save_vless_reality_state,prompt_vless_reality_install,prompt_vless_reality_update'
  'vless-plain|vless|vless-plain|vless|plain|inbound|vless|VLESS|vless-plain-in|10||vless|tcp,udp|tcp,udp|1.13.0|true|optional|vless|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"transports":["none","http","ws","grpc","quic"],"listen_transport_projection":true,"share_link":true,"subman_sync":true}|vless-plain|build_vless_plain_inbound_json,build_vless_plain_route_rules_json,build_client_vless_plain_outbounds,save_vless_plain_state,prompt_vless_plain_install,prompt_vless_plain_update,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'mixed|mixed|mixed|mixed|plain|inbound|mixed|Mixed (HTTP/HTTPS/SOCKS)|mixed-in|2|||tcp|tcp,udp|1.13.0|true|none|http,socks5|tcp_loopback|{"multi_instance":true,"per_instance_outbound":["default","direct","warp"],"http":true,"socks5":true,"authentication":true,"share_links":["http","socks5"],"qr":false,"subman_sync":false}||build_mixed_inbound_json,save_mixed_state,prompt_mixed_install,prompt_mixed_update,build_client_mixed_outbounds,load_mixed_structured_instance,apply_mixed_instance_change'
  'hy2|hy2|hysteria2|hysteria2|tls|inbound|hysteria2|Hysteria2|hy2-in|3||hysteria2|udp|tcp,udp|1.13.0|true|optional|hysteria2|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"tls_modes":["acme_http01","acme_cloudflare_dns01","manual"],"bandwidth":true,"obfs":true,"masquerade":true,"share_link":true,"qr":true,"subman_sync":true,"structured_instance_management":true}|hysteria2|build_hy2_inbound_json,build_hy2_certificate_provider_json,build_client_hy2_outbound,save_hy2_state,prompt_hy2_install,prompt_hy2_update,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'anytls|anytls|anytls|anytls|tls|inbound|anytls|AnyTLS|anytls-in|4|||tcp|tcp,udp|1.13.0|true|optional||tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"tls_modes":["acme_http01","acme_cloudflare_dns01","manual"],"standard_share_uri":false,"outbound_example":true,"qr":false,"subman_sync":false}||build_anytls_inbound_json,build_anytls_certificate_provider_json,build_client_anytls_outbound,save_anytls_state,prompt_anytls_install,prompt_anytls_update,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'socks|socks|socks|socks|plain|inbound|socks|SOCKS|socks-in|5|||tcp|tcp,udp|1.13.0|true|none|socks5|tcp_loopback|{"multi_instance":true,"per_instance_outbound":["default","direct","warp"],"socks5":true,"authentication":true,"share_links":["socks5"],"qr":false,"subman_sync":false}||build_socks_inbound_json,save_socks_state,prompt_socks_install,prompt_socks_update,build_client_socks_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'http|http|http|http|plain-or-tls|inbound|http|HTTP Proxy|http-in|6|||tcp|tcp|1.13.0|true|none|http|tcp_loopback|{"multi_instance":true,"per_instance_outbound":["default","direct","warp"],"http":true,"tls":true,"tls_modes":["disabled","manual_certificate"],"tls_share_links":false,"authentication":true,"share_links":["http"],"qr":false,"subman_sync":false}||build_http_inbound_json,save_http_state,prompt_http_install,prompt_http_update,build_client_http_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'shadowsocks|shadowsocks|shadowsocks|shadowsocks|aead-and-2022|inbound|shadowsocks|Shadowsocks|ss-in|7||ss|tcp,udp|tcp,udp|1.13.0|true|none|ss|tcp_loopback|{"multi_instance":true,"multi_user":true,"listen_network_selection":true,"per_instance_outbound":["default","direct","warp"],"authentication":true,"share_links":["ss"],"qr":false,"subman_sync":true}|ss|build_shadowsocks_inbound_json,save_shadowsocks_state,prompt_shadowsocks_install,prompt_shadowsocks_update,build_client_shadowsocks_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'trojan|trojan|trojan|trojan|tls|inbound|trojan|Trojan|trojan-in|8||trojan|tcp,udp|tcp,udp|1.13.0|true|optional|trojan|tcp_loopback|{"multi_instance":true,"authentication":true,"tls":true,"transports":["none","http","ws","grpc","quic"],"listen_transport_projection":true,"subman_sync":true}|trojan|build_trojan_inbound_json,save_trojan_state,prompt_trojan_install,prompt_trojan_update,build_client_trojan_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'vmess|vmess|vmess|vmess|tls|inbound|vmess|VMess|vmess-in|9||vmess|tcp,udp|tcp,udp|1.13.0|true|optional|vmess|tcp_loopback|{"multi_instance":true,"authentication":true,"tls":true,"transports":["none","http","ws","grpc","quic"],"listen_transport_projection":true,"subman_sync":true}|vmess|build_vmess_inbound_json,save_vmess_state,prompt_vmess_install,prompt_vmess_update,build_client_vmess_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'snell|snell|snell|snell|psk|inbound|snell|Snell|snell-in|11|||tcp|tcp|1.14.0|true|none|snell|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"versions":[5,6],"v5_obfs_modes":["none","http"],"v6_modes":["","default","unshaped","unsafe-raw"],"udp_via_tcp_packet_api":true,"standard_share_uri":false,"qr":false,"subman_sync":false,"structured_instance_management":true}|snell|build_snell_inbound_json,save_snell_state,prompt_snell_install,prompt_snell_update,build_client_snell_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'tuic|tuic|tuic|tuic|tls-quic|inbound|tuic|TUIC|tuic-in|12|||udp|tcp,udp|1.13.0|true|optional|tuic|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"tls_modes":["manual_certificate"],"quic":true,"congestion_control":["cubic","new_reno","bbr"],"udp_relay_modes":["native","quic"],"udp_over_stream":true,"zero_rtt_handshake":true,"heartbeat":true,"standard_share_uri":false,"qr":false,"subman_sync":false,"structured_instance_management":true}|tuic|build_tuic_inbound_json,save_tuic_state,prompt_tuic_install,prompt_tuic_update,build_client_tuic_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'hysteria|hysteria|hysteria|hysteria|tls-quic|inbound|hysteria|Hysteria|hysteria-in|13|||udp|tcp,udp|1.13.0|true|optional|hysteria|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"tls_modes":["manual_certificate"],"bandwidth":true,"obfs":true,"quic":true,"standard_share_uri":false,"qr":false,"subman_sync":false,"structured_instance_management":true}|hysteria|build_hysteria_inbound_json,save_hysteria_state,prompt_hysteria_install,prompt_hysteria_update,build_client_hysteria_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'naive|naive|naive|naive|tls-quic|inbound|naive|NaiveProxy|naive-in|14|||tcp,udp|tcp,udp|1.13.0|true|optional|naive|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"tls":true,"network":["tcp","udp"],"listen_network_selection":true,"quic_congestion_control":["bbr","cubic","reno"],"standard_share_uri":false,"qr":false,"subman_sync":false,"structured_instance_management":true,"outbound_runtime":"with_naive_outbound+libcronet"}|naive|build_naive_inbound_json,save_naive_state,prompt_naive_install,prompt_naive_update,build_client_naive_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
  'shadowtls|shadowtls|shadowtls|shadowtls|tls-wrapper|inbound|shadowtls|ShadowTLS|shadowtls-in|15|||tcp|tcp|1.13.0|true|optional|shadowtls|tcp_loopback|{"multi_instance":true,"multi_user":true,"authentication":true,"versions":[1,2,3],"handshake":true,"detour":true,"wildcard_sni":["off","authed","all"],"standard_share_uri":false,"qr":false,"subman_sync":false,"structured_instance_management":true,"composite":true}|shadowtls|build_shadowtls_inbound_json,save_shadowtls_state,prompt_shadowtls_install,prompt_shadowtls_update,build_client_shadowtls_outbounds,load_plain_proxy_structured_instance,apply_plain_proxy_instance_change'
)
# Runtime component registry for the non-proxy protocol surface.  These
# records deliberately remain separate from SB_PROTOCOL_REGISTRY: advanced
# inbounds, endpoints and outbounds are not share-link protocols and must not
# accidentally enter the protocol index or instance menus.
readonly SB_COMPONENT_REGISTRY=(
  'direct-inbound|inbound|direct|Direct inbound|1.13.0|builtin|{"listen":true,"network":["tcp","udp"],"loop_prevention":true}'
  'tun-inbound|inbound|tun|TUN inbound|1.13.0|builtin|{"l3":true,"auto_route":true,"strict_route":true,"loop_prevention":true}'
  'redirect-inbound|inbound|redirect|Redirect inbound|1.13.0|builtin|{"listen":true,"linux_macos":true,"loop_prevention":true,"optional_host_policy":{"backend":"iptables","family":"ipv4","transport":["tcp"],"scope":"explicit_interface_and_destination_ports"}}'
  'tproxy-inbound|inbound|tproxy|TProxy inbound|1.13.0|builtin|{"listen":true,"network":["tcp","udp"],"linux":true,"loop_prevention":true,"optional_host_policy":{"backend":"iptables+iproute2","family":"ipv4","transport":["tcp","udp"],"scope":"explicit_interface_and_destination_ports"}}'
  'cloudflared-inbound|inbound|cloudflared|Cloudflared inbound|1.14.0|with_cloudflared|{"tunnel":true,"token_required":true,"account_mutation":false}'
  'wireguard-endpoint|endpoint|wireguard|WireGuard endpoint|1.11.0|with_wireguard|{"endpoint":true,"modern_endpoint":true,"typed_config":true,"peers":true,"allowed_ips":true,"udp_nat":true,"dialer":true,"listen_network":["udp"]}'
  'tailscale-endpoint|endpoint|tailscale|Tailscale endpoint|1.12.0|with_tailscale|{"endpoint":true,"typed_config":true,"auth_external":true,"routes":true,"relay":true,"ssh_server":true,"dialer":true,"listen_network":["udp"]}'
  'openconnect-endpoint|endpoint|openconnect|OpenConnect endpoint|1.14.0|with_openconnect|{"endpoint":true,"typed_config":true,"client_only":true,"auth_external":true,"tls":true,"udp_nat":true,"dialer":true,"listen_network":["udp"]}'
  'openvpn-client-endpoint|endpoint|openvpn-client|OpenVPN client endpoint|1.14.0|with_openvpn|{"endpoint":true,"typed_config":true,"client_only":true,"auth_external":true,"tls":true,"static_key":true,"routes":true,"udp_nat":true,"dialer":true,"listen_network":["udp","tcp"]}'
  'openvpn-server-endpoint|endpoint|openvpn-server|OpenVPN server endpoint|1.14.0|with_openvpn|{"endpoint":true,"typed_config":true,"server":true,"tls":true,"static_key":true,"users":true,"push":true,"udp_nat":true,"listen_network":["tcp","udp"]}'
  'ssh-outbound|outbound|ssh|SSH outbound|1.14.0|builtin|{"dialer":true,"credentials":true}'
  'tor-outbound|outbound|tor|Tor outbound|1.13.0|builtin|{"dialer":true,"dependency_external":true,"runtime_modes":["external","embedded_unverified"]}'
  'direct-outbound|outbound|direct|Direct outbound|1.13.0|builtin|{"dialer":true}'
  'bridge-outbound|outbound|bridge|Bridge outbound|1.14.0|builtin|{"l3":true,"requires_privilege":true}'
  'selector-outbound|outbound|selector|Selector group|1.13.0|builtin|{"group":true,"members_required":true,"members_unique":true}'
  'urltest-outbound|outbound|urltest|URLTest group|1.13.0|builtin|{"group":true,"members_required":true,"members_unique":true}'
  'block-outbound|outbound|block|Block outbound|1.13.0|builtin|{"terminal":true}'
  'socks-outbound|outbound|socks|SOCKS outbound|1.13.0|builtin|{"dialer":true}'
  'http-outbound|outbound|http|HTTP outbound|1.13.0|builtin|{"dialer":true}'
  'shadowsocks-outbound|outbound|shadowsocks|Shadowsocks outbound|1.13.0|builtin|{"dialer":true}'
  'vmess-outbound|outbound|vmess|VMess outbound|1.13.0|builtin|{"dialer":true}'
  'trojan-outbound|outbound|trojan|Trojan outbound|1.13.0|builtin|{"dialer":true}'
  'naive-outbound|outbound|naive|NaiveProxy outbound|1.13.0|with_naive_outbound|{"dialer":true,"network":["tcp","udp"],"tls_required":true,"quic":true,"quic_congestion_control":["bbr","bbr2","cubic","reno"],"udp_over_tcp":true,"external_runtime":"libcronet"}'
  'hysteria2-outbound|outbound|hysteria2|Hysteria2 outbound|1.13.0|with_quic|{"dialer":true,"network":["tcp","udp"],"tls_required":true,"obfs_types":["salamander","gecko"],"realm":true,"quic":true,"bbr_profiles":["conservative","standard","aggressive"]}'
  'hysteria-outbound|outbound|hysteria|Hysteria outbound|1.13.0|with_quic|{"dialer":true,"network":["tcp","udp"],"tls_required":true,"auth_fields":["auth","auth_str"],"bandwidth":true,"obfs":true,"quic":true}'
  'tuic-outbound|outbound|tuic|TUIC outbound|1.13.0|with_quic|{"dialer":true,"network":["tcp","udp"],"tls_required":true,"congestion_control":["cubic","new_reno","bbr"],"udp_relay_modes":["native","quic"],"udp_over_stream":true,"zero_rtt_handshake":true,"heartbeat":true,"quic":true}'
  'vless-outbound|outbound|vless|VLESS outbound|1.13.0|builtin|{"dialer":true}'
  'anytls-outbound|outbound|anytls|AnyTLS outbound|1.14.0|builtin|{"dialer":true}'
  'snell-outbound|outbound|snell|Snell outbound|1.14.0|builtin|{"dialer":true,"versions":[4,6],"obfs_modes":["none","http"],"shaping_modes":["default","unshaped","unsafe-raw"],"udp_via_tcp_packet_api":true}'
  'shadowtls-outbound|outbound|shadowtls|ShadowTLS outbound|1.13.0|builtin|{"dialer":true,"network":["tcp"],"tls_required":true,"versions":[1,2,3],"password_versions":[2,3]}'
  'certificate-provider-acme|certificate_provider|acme|ACME certificate provider|1.14.0|builtin|{"provider":true,"domains":true,"dns01":true,"external_account":true,"http_client_reference":true}'
  'http-client-shared|http_client|shared|Shared HTTP client|1.14.0|builtin|{"shared":true,"referenceable":true,"versions":[1,2,3],"http2":true,"http3":true,"tls":true,"dialer":true}'
  'resolved-service|service|resolved|Resolved service|1.13.0|builtin|{"service":true,"listen":true,"tcp":true,"udp":true,"linux":true,"dbus":true}'
  'network-namespace-default|network_namespace|default|Default network namespace|1.14.0|builtin|{"namespace":true,"path_required":true}'
  'network-namespace-unshare|network_namespace|unshare|Unshare network namespace|1.14.0|builtin|{"namespace":true,"path_required":false}'
  'route-rule-set-inline|rule_set|inline|Inline route rule set|1.13.0|builtin|{"rules":true,"matcher_only":true,"max_rules":128,"max_tags_per_record":1}'
  'route-rule-set-local|rule_set|local|Local route rule set|1.13.0|builtin|{"format":["source","binary"],"path_reference":true,"owns_file":false,"max_tags_per_record":1}'
  'route-rule-set-remote|rule_set|remote|Remote route rule set|1.13.0|builtin|{"format":["source","binary"],"http_url":true,"initial_path":true,"update_interval":true,"http_client_reference":true,"http_client_reference_minimum_core":"1.14.0","download_detour":false,"max_tags_per_record":1}'
)
# --- Global Variables ---
SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
SB_PROTOCOL="vless+reality"
SB_INSTANCE_ID=""
SB_NODE_NAME="$(hostname)-vless"
SB_PORT="443"
SB_UUID=""
SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""
SB_SHORT_ID_1=""
SB_SHORT_ID_2=""
SB_SNI=""
SB_MIXED_AUTH_ENABLED="y"
SB_MIXED_USERNAME=""
SB_MIXED_PASSWORD=""
SB_MIXED_INSTANCE_ID=""
SB_MIXED_INBOUND_TAG=""
SB_MIXED_LISTEN_ADDRESS=""
SB_MIXED_STORE_REVISION="0"
SB_HTTP_TLS_JSON=""
SB_SHADOWSOCKS_AUTH_JSON=""
SB_SHADOWSOCKS_NETWORK_JSON=""
SB_TROJAN_AUTH_JSON='[]'
SB_TROJAN_TLS_JSON='{"enabled":false}'
SB_TROJAN_TRANSPORT_JSON='{"type":"none"}'
SB_TROJAN_CLIENT_TRUST="certificate"
SB_VMESS_AUTH_JSON='[]'
SB_VMESS_TLS_JSON='{"enabled":false}'
SB_VMESS_TRANSPORT_JSON='{"type":"none"}'
SB_VMESS_CLIENT_TRUST="certificate"
SB_VLESS_PLAIN_AUTH_JSON='[]'
SB_VLESS_PLAIN_TLS_JSON='{"enabled":false}'
SB_VLESS_PLAIN_TRANSPORT_JSON='{"type":"none"}'
SB_VLESS_PLAIN_CLIENT_TRUST="system"
SB_SNELL_VERSION="6"
SB_SNELL_PSK=""
SB_SNELL_USER_JSON='[]'
SB_SNELL_OBFS_MODE=""
SB_SNELL_OBFS_HOST=""
SB_SNELL_MODE=""
SB_TUIC_AUTH_JSON='[]'
SB_TUIC_TLS_JSON='{"enabled":false}'
SB_TUIC_CLIENT_TRUST="system"
SB_TUIC_CONGESTION_CONTROL="bbr"
SB_TUIC_AUTH_TIMEOUT_SECONDS="3"
SB_TUIC_HEARTBEAT_SECONDS="10"
SB_TUIC_ZERO_RTT_HANDSHAKE="n"
SB_TUIC_UDP_RELAY_MODE="native"
SB_TUIC_UDP_OVER_STREAM="n"
SB_HYSTERIA_AUTH_JSON='[]'
SB_HYSTERIA_TLS_JSON='{"enabled":false}'
SB_HYSTERIA_CLIENT_TRUST="system"
SB_HYSTERIA_UP_MBPS="100"
SB_HYSTERIA_DOWN_MBPS="100"
SB_HYSTERIA_OBFS_ENABLED="n"
SB_HYSTERIA_OBFS_PASSWORD=""
SB_HYSTERIA_QUIC_JSON='{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'
SB_NAIVE_AUTH_JSON='[]'
SB_NAIVE_TLS_JSON='{"enabled":false}'
SB_NAIVE_CLIENT_TRUST="system"
SB_NAIVE_NETWORK_JSON='["tcp","udp"]'
SB_NAIVE_QUIC_CONGESTION_CONTROL="bbr"
SB_NAIVE_QUIC="n"
SB_NAIVE_INSECURE_CONCURRENCY="0"
SB_NAIVE_STREAM_RECEIVE_WINDOW=""
SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=""
SB_NAIVE_EXTRA_HEADERS_JSON='{}'
SB_SHADOWTLS_VERSION=3
SB_SHADOWTLS_PASSWORD=""
SB_SHADOWTLS_AUTH_JSON='[]'
SB_SHADOWTLS_HANDSHAKE_JSON='{"server":"","server_port":443}'
SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON='{}'
SB_SHADOWTLS_STRICT_MODE="n"
SB_SHADOWTLS_WILDCARD_SNI="off"
SB_SHADOWTLS_DETOUR_TAG=""
SB_SHADOWTLS_DETOUR_PORT=""
SB_SHADOWTLS_CLIENT_TRUST="system"
SB_SHADOWTLS_CLIENT_TLS_JSON='{"enabled":true,"server_name":"","certificate_path":""}'
SB_HY2_DOMAIN=""
SB_HY2_PASSWORD=""
SB_HY2_USER_NAME=""
SB_HY2_UP_MBPS=""
SB_HY2_DOWN_MBPS=""
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE=""
SB_HY2_OBFS_PASSWORD=""
SB_HY2_TLS_MODE="acme"
SB_HY2_ACME_MODE="http"
SB_HY2_ACME_EMAIL=""
SB_HY2_ACME_DOMAIN=""
SB_HY2_ACME_EXTRA_JSON='{}'
SB_HY2_DNS_PROVIDER="cloudflare"
SB_HY2_CF_API_TOKEN=""
SB_HY2_CERT_PATH=""
SB_HY2_KEY_PATH=""
SB_HY2_MASQUERADE=""
SB_ANYTLS_DOMAIN=""
SB_ANYTLS_PASSWORD=""
SB_ANYTLS_USER_NAME=""
SB_ANYTLS_TLS_MODE="acme"
SB_ANYTLS_ACME_MODE="http"
SB_ANYTLS_ACME_EMAIL=""
SB_ANYTLS_ACME_DOMAIN=""
SB_ANYTLS_ACME_EXTRA_JSON='{}'
SB_ANYTLS_DNS_PROVIDER="cloudflare"
SB_ANYTLS_CF_API_TOKEN=""
SB_ANYTLS_CERT_PATH=""
SB_ANYTLS_KEY_PATH=""
SB_ADVANCED_ROUTE="n"
SB_ENABLE_WARP="n"
SB_WARP_ROUTE_MODE="selective"
SB_OUTBOUND_POLICY="default"
SB_INBOUND_STACK_MODE=""
SB_OUTBOUND_STACK_MODE=""
SB_WARP_CUSTOM_DOMAINS_JSON='[]'
SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
SB_WARP_LOCAL_RULE_SETS_JSON='[]'
SB_WARP_REMOTE_RULE_SETS_JSON='[]'
SB_WARP_RULE_SET_TAGS_JSON='[]'
SUBMAN_API_URL=""
SUBMAN_API_TOKEN=""
SUBMAN_NODE_PREFIX=""
SUBMAN_EXPECTED_GIST_ID=""
SUBMAN_LAST_HTTP_STATUS=""
SUBMAN_LAST_ERROR_CODE=""
SUBMAN_LAST_ERROR_DISPOSITION=""
SUBMAN_LAST_RETRY_AFTER=""
SUBMAN_LAST_REVISION=""
SUBMAN_LAST_NODE_ID=""
SUBMAN_LAST_GIST_ID=""
SUBMAN_LAST_OUTCOME=""

# --- Return-based update transaction context ---
SBV_UPDATE_OPERATION=""
SBV_UPDATE_STAGE=""
SBV_UPDATE_ERROR_CODE=""
SBV_UPDATE_ERROR_MESSAGE=""
SBV_UPDATE_ERROR_DETAIL=""
SBV_UPDATE_COMMAND_EXIT_CODE="0"
SBV_UPDATE_HINT=""
SBV_UPDATE_CHANGED="false"
SBV_UPDATE_ROLLBACK_ATTEMPTED="false"
SBV_UPDATE_ROLLED_BACK="false"
SBV_UPDATE_ROLLBACK_OK="false"
SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED="false"
SBV_UPDATE_CURRENT_VERSION=""
SBV_UPDATE_CANDIDATE_VERSION=""
SBV_UPDATE_TARGET_PATH="${SBV_BIN_PATH}"
SBV_UPDATE_LOG_FILE="${SBV_LOG_FILE}"
SBV_UPDATE_TARGET_EXISTS="false"
SBV_UPDATE_TARGET_WAS_EXECUTABLE="false"
SBV_UPDATE_TARGET_MODE=""
SBV_UPDATE_TARGET_UID=""
SBV_UPDATE_TARGET_GID=""
SBV_UPDATE_TARGET_HASH=""
SBV_UPDATE_TARGET_VERSION=""
SBV_UPDATE_EXPECTED_MODE=""
SBV_UPDATE_EXPECTED_UID=""
SBV_UPDATE_EXPECTED_GID=""
SBV_UPDATE_CANDIDATE_PATH=""
SBV_UPDATE_CANDIDATE_HASH=""
SBV_UPDATE_CURL_STDERR_PATH=""
SBV_UPDATE_BACKUP_PATH=""
SBV_UPDATE_ROLLBACK_PATH=""
SBV_UPDATE_LOCK_PATH=""
SBV_UPDATE_LOCK_HELD="false"
SBV_UPDATE_COMMITTED="false"
SBV_UPDATE_NOOP="false"
SBV_UPDATE_PRESERVE_ARTIFACTS="false"
SBV_UPDATE_SIGNAL_NAME=""
SBV_UPDATE_SIGNAL_CODE="0"
SBV_UPDATE_TRAP_ACTIVE="false"
SBV_UPDATE_TRAP_RUNNING="false"
SBV_UPDATE_PREVIOUS_INT_TRAP=""
SBV_UPDATE_PREVIOUS_TERM_TRAP=""
SBV_UPDATE_PREVIOUS_HUP_TRAP=""
SBV_UPDATE_PREVIOUS_ERR_TRAP=""
SBV_VALIDATED_SCRIPT_VERSION=""
SBV_SCRIPT_VALIDATION_CODE=""
SBV_SCRIPT_VALIDATION_DETAIL=""
