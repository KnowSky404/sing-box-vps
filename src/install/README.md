# Installer sources

[中文开发说明](../../docs/wiki/Development.md#模块化源码与单文件构建)

Maintain the installer in these 49 Bash source fragments. The explicit order in
`manifest.txt` preserves the original definitions, global state and entrypoint.
Each fragment contains complete shell constructs and is under 2,000 lines at
the initial split. Fragments are build inputs; do not execute or download them
individually. The manifest defines concatenation order; `43-launcher.sh` runs the
entrypoint after all modules have been defined.

The root `install.sh` is a committed, generated standalone artifact. Bootstrap,
self-update, the global `sbv` command, tests and Docker continue to consume it
without loading adjacent source files. A downloaded `install.sh` still works on
its own, with the same runtime dependencies.

## Editing and checking

From the repository root:

```bash
# Edit the relevant src/install module, then regenerate the artifact.
bash scripts/build-install.sh

# Read-only consistency check; also selected by the verification planner.
bash scripts/build-install.sh --check

# Isolated build/publication regressions.
bash tests/install_build.sh

# Review the complete task diff and choose behavior-appropriate verification.
bash dev/verification/run.sh --plan --base origin/main
```

Commit the source and generated artifact together. Do not edit `install.sh`
directly. Update the version in `00-preamble.sh` and the root README once per
delivery, following AGENTS.md; the builder copies that metadata unchanged.
When adding or splitting a module, update the manifest explicitly. Each entry
must be a local basename such as `23-ui-and-network-menus.sh`; duplicates,
missing/unlisted modules and symlinks are rejected. The manifest is data and is
never sourced as shell code. The builder checks each fragment and the assembled
script with `bash -n` before replacing the artifact atomically. A failed build
keeps the previous artifact; an identical build does not rewrite it. `--check`
uses temporary storage outside the checkout and never publishes an artifact.

## Finding the relevant module

| Modules | Responsibility |
| --- | --- |
| `00` | Script version, constants, registries and initial globals |
| `01`–`04` | Common helpers, stack state, naming, registries and protocol/SubMan state |
| `05`–`08` | Protocol prompts, instance records and installation workflows |
| `09`–`12` | Defaults, media/WARP assets, script/core updates and host resources |
| `13` | Protocol configuration renderers |
| `14`–`19` | Component schemas, state and transparent-network resources |
| `20`–`22` | Config ownership, transactions, graph validation, generation and uninstall |
| `23`–`24` | Terminal UI, network menus and protocol management |
| `25`–`28` | Addresses, share links, SubMan, per-node outbound materials and display |
| `29`–`33` | Agent upgrades, status, service commands, instance transactions and dispatch |
| `34`–`38` | Node inventory, typed stores, adapters, snapshots, takeover and recovery |
| `39` | Top-level installation and management entrypoints |
| `40`–`42` | Routing policy, application/recovery transactions and the unified menu |
| `43` | Final source-versus-execution guard |
| `44`–`45` | Embedded operation catalog and guarded Agent routing commands (assembled before the launcher) |
| `46`–`48` | Private storage, SELinux, legacy migration/recovery and entrypoint gates |

This first split intentionally preserves byte order and behavior. Functions may
still call helpers in later modules; all definitions are assembled before the
final entrypoint runs. It introduces no dynamic module loader or new config/state
format. Future behavior changes still need the focused checks required by
AGENTS.md section 4.2, including configuration or runtime validation when affected.
