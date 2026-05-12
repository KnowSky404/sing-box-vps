# Domain IP Validation Design

## Goal

When users enter a Hysteria2 or AnyTLS domain, the installer should warn before continuing if that domain does not resolve to the current server's public outbound IP address.

## Scope

- Validate domains entered during Hysteria2 install and update flows.
- Validate domains entered during AnyTLS install and update flows.
- Validate a reused shared TLS domain before a later protocol silently accepts it.
- Do not add package dependencies.
- Do not block advanced deployments permanently; users can explicitly continue after seeing the mismatch.

## Behavior

After a non-empty Hysteria2 or AnyTLS domain is entered, the script resolves the local public outbound IP addresses and the domain's A/AAAA records.

If any resolved domain IP matches any local public outbound IP, the prompt continues normally.

If the domain cannot be resolved, or if the resolved IPs do not match the local public outbound IPs, the script prints:

- The protocol name.
- The entered domain.
- The local public outbound IPs found.
- The domain IPs found, or a clear unresolved marker.
- A warning that ACME HTTP-01 or client connections may fail.

The default answer is to reject the domain and return to the domain prompt. If the user enters `y`, the script accepts the domain and continues. This keeps the common path safe while still allowing CDN, reverse proxy, DNS-01, and manual certificate deployments.

## Implementation Notes

- Add small reusable helpers in `install.sh`:
  - Get public outbound IPs from the existing public IP detection path.
  - Resolve domain IPs with system tools already expected on common Linux hosts.
  - Compare IP lists exactly.
  - Prompt for explicit continuation on mismatch.
- Keep the helper independent of sing-box configuration generation.
- Use the helper in `prompt_hy2_install`, `prompt_anytls_install`, `prompt_hy2_update`, and `prompt_anytls_update`.

## Test Strategy

- Add shell tests that stub public IP and domain resolution helpers.
- Cover matching domains continuing without confirmation.
- Cover mismatched domains being rejected by default and prompting again.
- Cover mismatched domains continuing when the user confirms with `y`.
- Cover shared domain reuse for Hysteria2 plus AnyTLS.

