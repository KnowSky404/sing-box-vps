# AnyTLS Inbound Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AnyTLS inbound support to `install.sh` with interactive install/update flows, persisted protocol state, config generation, and node info output.

**Architecture:** Extend the existing single-file protocol framework already used for `vless+reality`, `mixed`, and `hy2`. Reuse the per-protocol state file model, add AnyTLS-specific TLS fields, and render node info as parameter summary plus outbound JSON example because the official sing-box docs do not define a standard share URI.

**Tech Stack:** Bash, jq, existing shell test harnesses

---

### Task 1: Add failing regression tests

**Files:**
- Modify: `tests/blank_protocol_selection_installs_all_available.sh`
- Create: `tests/install_anytls_protocol_creates_state.sh`
- Create: `tests/multi_protocol_anytls_config_generation.sh`
- Create: `tests/view_node_info_renders_anytls_details.sh`

- [ ] **Step 1: Write failing tests for protocol selection and AnyTLS flows**
- [ ] **Step 2: Run the focused shell tests and confirm they fail for missing AnyTLS support**

### Task 2: Wire AnyTLS into protocol state and interactive prompts

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add AnyTLS protocol identifiers, display names, state save/load branches, defaults, and install/update prompts**
- [ ] **Step 2: Re-run the install/state regression test and make it pass**

### Task 3: Generate AnyTLS config and render node info

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add AnyTLS inbound JSON generation, route rules, legacy config parsing, and node info rendering**
- [ ] **Step 2: Re-run config generation and node info regression tests and make them pass**

### Task 4: Refresh version metadata and docs

**Files:**
- Modify: `install.sh`
- Modify: `README.md`

- [ ] **Step 1: Bump `SCRIPT_VERSION` once for this conversation turn and document AnyTLS in the readme**
- [ ] **Step 2: Run the focused regression suite plus version/readme consistency checks**
