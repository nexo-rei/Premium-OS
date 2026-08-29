# Changelog

All notable changes to Premium-OS. Format follows *Keep a Changelog*.

## [1.0.0] — 2024

### Added
- **Core platform**: modular bash architecture (`core/` init·utils·config·theme·profile·security)
- **Multi-profile system**: CRUD, duplicate/rename/merge, import/export, active indicator
- **Visual Theme Creator**: live terminal preview, color picker (HEX/RGB), harmony suggestions,
  font catalog (15 fonts), JSON save/export
- 5 theme presets: dark · light · neon · minimal · dracula
- **Performance monitor**: CPU/RAM/uptime/processes/benchmark, sparklines, gauges, CSV export,
  rolling history
- **.poz backup system**: one-click create/verify/preview/restore with AES-256 option,
  rollback snapshots, retention policy, portable export
- **Auto-cleanup**: dry-run, selective targets, freed-space report, schedule
- **Startup optimizer**: rc-time measurement, slow-pattern scanner, one-click safe tweaks,
  before/after compare
- **Snippets library**: categories, search, clipboard copy, confirm-execute, seeded defaults
- **Hotkeys**: registry with conflict + reserved-combo protection, test mode, export
- **Smart suggestions**: time/task-aware theme recommendations with learning (local-only,
  opt-in telemetry posture)
- **Plugin system**: manifest-driven, sandboxed, hook API, static danger-scan, marketplace view
- **Visual FX panel**: icon themes, gradient playground, border gallery, emoji banner
- **Cyber Lock**: salted SHA-256 app lock + AES-256 backup encryption
- **Responsive animated menu UI**: mobile/tablet/desktop layouts, transitions, spinner/progress
- **Web dashboard (localhost:8080)**: zero-dependency Node server, REST + WebSocket,
  glassmorphism SPA with live charts, theme creator, PWA support
- **Quick-setup wizard** (2 min) on first run
- **INSTALL.sh** 7-step installer with shell aliasing (`pos`)
- **scripts/**: backup.sh · update.sh (backup-then-update + rollback) · sync.sh (git-based
  cloud sync, opt-in) · uninstall.sh
- **tests.sh**: 125-check suite (8 categories, PRD timing budgets asserted)
- Docs: FEATURES · API · PLUGIN-GUIDE · TROUBLESHOOTING · CHANGELOG
