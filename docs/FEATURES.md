# Premium-OS — Feature Guide

Every feature, how to reach it, and how it behaves.

---

## 1. Themes & Theme Creator

**Where:** menu → `1 Themes` · CLI `bash main.sh theme …` · web → *Themes*

- 5 curated presets: **dark, light, neon, minimal, dracula**
- **Visual Theme Creator** (`theme_creator_ui`)
  - Interactive color picker with 18-swatch palette grid + free HEX / `R,G,B` input
  - **Live preview** — a rendered terminal mock updates as you edit
  - **Color harmony suggestions** — complementary & analogous computed from your pick
  - Font chooser — 15 curated monospace fonts with size slider (8–28 px)
  - Save as template → auto-listed in the theme browser
  - **Export theme code** — copy-ready shell snippet
- Apply is instant (<1 s) and stored in the active profile + settings.
- Themes are JSON (`config/themes/*.json` = built-ins, `~/.premium-os/themes/` = yours).

## 2. Multi-Profile System

**Where:** menu → `2 Profiles` · CLI `bash main.sh profile …`

A profile bundles: theme, shell type, aliases, hotkeys, startup commands, banner.

| Action | Function |
|---|---|
| Create / Switch / Delete | `create_profile` `switch_profile` `delete_profile` |
| Duplicate / Rename | `duplicate_profile` `rename_profile` |
| Import / Export | JSON `.profile.json` files |
| Merge | overlay one profile's theme+aliases onto the active one |
| Preview | `profile_preview <name>` |

Safety rails:
- `default` profile cannot be deleted or renamed
- Corrupt profiles are rejected on switch (JSON validated first)
- Unsafe names (`;`, spaces, …) are rejected to prevent path/command injection

## 3. Performance Monitor

**Where:** menu → `3 Performance` · CLI `bash main.sh perf …` · web → *Performance*

Live (2 s refresh): **CPU %**, **RAM (MB/%)**, **process count**, **session+system uptime**,
**terminal benchmark (cmds/s)**, **cache usage**.

- Unicode sparklines & color-coded gauges (green <60 % · yellow <85 % · red ≥85 %)
- Rolling history in `~/.premium-os/history/perf/<date>.csv` (last 1 h / 24 h queries)
- CSV export: `bash main.sh perf csv`

Implementation reads `/proc/stat`, `/proc/meminfo`, `/proc/uptime` directly — Termux-safe.

## 4. Backup & Restore (.poz)

**Where:** menu → `4 Backup & Sync` · CLI `bash main.sh backup …`

- `.poz` = gzipped tar with `manifest.json` (format marker + metadata)
- Contents: profiles, custom themes, settings, snippets, hotkeys
- **Encrypted backups**: `--encrypt` uses AES-256-CBC with PBKDF2 (`openssl`)
- **Verification**: integrity + manifest check (`backup_verification`)
- **Preview/explorer**: inspect contents before restoring
- **Rollback**: every restore snapshots the pre-state; `rollback_restore` undoes it
- **Retention**: `backup.max_backups` enforced automatically (default 10)
- **Portable config**: single `<1 MB` `tar.gz` export/import for USB/hand-off
- Auto-backup option runs (max) once per day at Premium-OS start

## 5. Auto-Cleanup

**Where:** menu → `5 Cleanup` · CLI `bash main.sh cleanup [auto]`

- **Dry-run first** — shows exactly what will be freed
- Selective: command history · POS temp files · POS cache · package cache (`apt clean/autoclean`)
- History is truncated (not deleted) and a backup copy is kept in POS cache
- `.secure` crypto material is never touched
- Freed-space report + post-cleanup verification
- Scheduling preference recorded for daily/weekly reminders

## 6. Startup Optimizer

**Where:** menu → `9 Optimizer` · CLI `bash main.sh optimize …`

- Measure rc-source time (`benchmark_startup`, ms precision)
- **Scan** flags slow patterns: network calls at boot, heavy version managers (nvm/pyenv/conda), splash programs, repeated command substitutions
- **One-click apply** appends an idempotent, marked block to your rc (history tuning, prompt-safe `less`, `checkwinsize`)
- Before/after comparison with recorded state
- Safe revert: the block is delimited by `# >>> pos-optimize >>>` markers

## 7. Command Snippets

**Where:** menu → `7 Snippets` · CLI `bash main.sh snippet …`

- Categories, search, one-click copy (Termux clipboard when available), explicit-confirm execute
- Ships with 10 starter snippets (Git/System/Dev/Package)
- Storage: `~/.premium-os/snippets.json` (jq-backed)

## 8. Hotkeys

**Where:** menu → `8 Hotkeys` · CLI `bash main.sh hotkey …`

- Free-text combos (`Ctrl+Shift+P`), normalized automatically
- **Conflict detection** (refuses rebinding), **reserved combo protection** (`Ctrl+C/Z/D/L/Q/S`)
- Test mode shows mapping without executing
- Export for sharing; storage `hotkeys.conf`

## 9. Smart Suggestions

**Where:** menu → `10 Smart Suggestions` · CLI `bash main.sh suggest`

- Time-aware (bright themes 07–19 h, dark otherwise) + task-aware (usage-pattern classifier reads recent history: `dev | system | general`)
- Confidence score shown (45–95 %)
- Learns accepts/rejects in `history/smart-prefs.json` — themes rejected 3× stop being offered
- Suggestions are **never forced** — always a "Try this?" prompt
- Weekly rotation option; weather hook is opt-in only (telemetry off by default)

## 10. Plugins

**Where:** menu → `11 Plugins` · CLI `bash main.sh plugin …` · web → *Plugins*

- Sandboxed execution (subshell, 10 s timeout, closed stdin)
- Dangerous-pattern scan rejects `rm -rf /`, fork bombs, `mkfs`, …
- Manifest-validated (name/version/author/description required)
- Hook API: `theme:applied`, `profile:switched`, `startup:init`, `backup:created`,
  `restore:complete`, `cleanup:complete`, `system:optimized`, `plugin:installed`, `update:available`, `ui:render`
- Enable/disable without uninstall; curated offline marketplace view
- See [PLUGIN-GUIDE.md](PLUGIN-GUIDE.md)

## 11. Visual FX

**Where:** menu → `6 Visual FX`

- 5 icon themes (Neon/Glassmorphism/Minimalist/Retro/Gradient) with preview glyphs
- Gradient playground (4 live-rendered true-color ramps)
- Border style gallery (clean modern / bold double / retro dotted)
- Emoji banner composer with 16-emoji picker grid

## 12. Cyber Lock

**Where:** menu → `14 Cyber Lock` · CLI `bash main.sh lock`

- Salted **SHA-256** password lock at app start (per-install random salt at `~/.premium-os/.salt`)
- 3 attempts → denial; change/disable flows verify first
- Passwords never stored in plain text

## 13. Web Dashboard

**Where:** menu → `12 Web Dashboard` · CLI `bash main.sh dashboard`

- Zero-dependency Node server on `localhost:8080` (Termux-friendly Light Setup Mode)
- Full REST surface + live WebSocket push (performance every 2 s)
- Glassmorphism neon UI, light/dark toggle, PWA offline cache
- Mobile (<600 px: bottom nav, single column) · Tablet (2 col) · Desktop (grid + side nav)
