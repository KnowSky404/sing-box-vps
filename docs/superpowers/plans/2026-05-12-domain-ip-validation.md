# Domain IP Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a default-blocking but overridable domain-to-public-IP validation prompt for Hysteria2 and AnyTLS domains.

**Architecture:** Keep validation as reusable Bash helpers in `install.sh`, with prompt flows calling one protocol-aware wrapper immediately after domain input. Tests source a rewritten install script and stub network lookups so behavior is deterministic.

**Tech Stack:** Bash, existing shell test harness, `getent`/`dig`/`nslookup` fallback design.

---

### Task 1: Add Deterministic Install-Flow Coverage

**Files:**
- Create: `tests/hy2_anytls_domain_ip_validation.sh`
- Modify later: `install.sh`

- [ ] **Step 1: Write the failing shell test**

Create `tests/hy2_anytls_domain_ip_validation.sh` with cases that source a testable `install.sh`, stub `get_public_ip_candidates` and `resolve_domain_ip_candidates`, and exercise:

- matching Hysteria2 install domain continues.
- mismatched Hysteria2 install domain rejects default answer and accepts the next domain.
- mismatched AnyTLS install domain accepts explicit `y`.
- shared Hysteria2 domain reused by AnyTLS is validated for both protocols.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/hy2_anytls_domain_ip_validation.sh`

Expected: FAIL because the validation helpers and prompt calls do not exist yet.

### Task 2: Implement Domain/IP Validation Helpers

**Files:**
- Modify: `install.sh`
- Test: `tests/hy2_anytls_domain_ip_validation.sh`

- [ ] **Step 1: Add reusable helpers**

Add Bash helpers near existing common utility functions:

- `normalize_ip_list`
- `get_public_ip_candidates`
- `resolve_domain_ip_candidates`
- `ip_lists_have_match`
- `confirm_domain_ip_mismatch`
- `validate_tls_domain_points_to_server`

The wrapper returns success when matched or user confirms, and failure when the user accepts the default reject answer.

- [ ] **Step 2: Wire install and update prompts**

Call `validate_tls_domain_points_to_server` after assigning:

- `SB_HY2_DOMAIN`
- `SB_ANYTLS_DOMAIN`

In install loops, reset the domain to empty and continue on validation failure. In update flows, preserve the old domain when a newly entered domain is rejected.

- [ ] **Step 3: Run focused test**

Run: `bash tests/hy2_anytls_domain_ip_validation.sh`

Expected: PASS.

### Task 3: Update Version Metadata And Required Verification

**Files:**
- Modify: `install.sh`
- Modify: `README.md`

- [ ] **Step 1: Bump version once**

Update both the top comment and `SCRIPT_VERSION` in `install.sh` from `2026051201` to `2026051202`.

Update README script version from `2026051201` to `2026051202`.

- [ ] **Step 2: Run focused and metadata tests**

Run:

```bash
bash tests/hy2_anytls_domain_ip_validation.sh
bash tests/version_metadata_is_consistent.sh
bash tests/readme_mentions_current_versions.sh
```

Expected: all pass.

- [ ] **Step 3: Run project verification for changed files**

Run: `bash dev/verification/run.sh --changed-file install.sh --changed-file README.md --changed-file tests/hy2_anytls_domain_ip_validation.sh`

Expected: pass, including remote verification if the changed-file rules require it.

