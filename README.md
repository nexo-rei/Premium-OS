<div align="center">

# ◢◤ Premium-OS

**The premium terminal customization & management platform for Termux**

`v1.0` · MIT License · Target: < 50 MB · Mobile-first · Touch-optimized

</div>

---

## ✨ What is Premium-OS?

Premium-OS goes beyond basic Termux theming. It is a complete, modular platform for
**customizing, monitoring, backing up, and optimizing** your terminal — with a modern
animated CLI plus an optional real-time web dashboard.

| Module | What it does |
|---|---|
| 🎨 **Theme Creator** | Visual color picker, font selection, live preview, JSON export, color-harmony suggestions |
| 🗂 **Multi-Profiles** | Save/switch complete terminal configs (theme, shell, aliases, hotkeys, banner) |
| ⚡ **Performance Monitor** | Real-time CPU/RAM/uptime/processes, benchmarks, gauges, CSV export |
| 💾 **Backup & Sync** | One-click `.poz` backups, password protection, version history, portable config |
| 🧹 **Auto-Cleanup** | History/temp/cache/package cleanup, dry-run preview, freed-space reports |
| 🚀 **Optimizer** | Startup profiling, slow-process detection, one-click boot optimization |
| ⌨ **Hotkeys** | Custom key bindings with conflict detection |
| 📚 **Snippets** | Searchable command library with one-click copy/execute |
| 🤖 **Smart Suggestions** | Time/usage-aware theme suggestions that learn your taste |
| 🧩 **Plugins** | Sandboxed plugin ecosystem with marketplace, hooks & permissions |
| 🌈 **Visual FX** | Gradients, icon themes, borders, blur, 1 500+ emoji support |
| 📱 **Responsive** | Mobile/tablet/desktop layouts, swipe-friendly, big touch targets |
| 🔐 **Cyber Lock** | SHA-256 password lock, encrypted backups (AES-256) |
| 🌐 **Web Dashboard** | Optional Node.js dashboard on `localhost:8080` with WebSocket updates |

---

## 🚀 Quick Start

```bash
# 1. Install
bash INSTALL.sh

# 2. Launch
pos            # or: bash main.sh
```

First launch runs a **2-minute quick-setup wizard** (shell → theme → banner → security).

## 🖥 CLI API (scriptable)

```bash
bash main.sh profile  list|create|switch|delete|duplicate|rename|import|export
bash main.sh theme    list|apply|preview|create|export
bash main.sh perf     stats|dashboard|benchmark|csv
bash main.sh backup   create|restore|list|preview|verify|portable
bash main.sh snippet  list|search|add|remove|run
bash main.sh hotkey   list|add|remove|test
bash main.sh cleanup  [auto]
bash main.sh optimize scan|apply|before
bash main.sh suggest
bash main.sh plugin   list|install|uninstall|enable|disable|info|market
bash main.sh dashboard     # start web dashboard (node)
bash main.sh setup         # re-run the wizard
```

## 🌐 Web Dashboard (optional)

```bash
pkg install nodejs     # in Termux
bash main.sh dashboard # → http://localhost:8080
```

REST API at `/api/*` + WebSocket events (`performance:update`, `profile:switched`, …).
Fully responsive (mobile <600 px, tablet 600–1024 px, desktop >1024 px) with a
glass-morphism neon theme — no heavy frontend frameworks, **vanilla JS only**.

## 📂 Repository Layout

```
Premium-OS/
├── main.sh               entry point (menu + CLI API)
├── INSTALL.sh            installer
├── core/                 init · utils · config · theme · profile · security
├── features/             theme-creator · performance · backup · cleanup ·
│                         hotkeys · snippets · optimization · suggestions · plugins
├── ui/                   menu · animations · responsive · colors
├── web/                  express dashboard (server.js, routes/, public/)
├── config/themes/        dark · light · neon · minimal · dracula (JSON)
├── plugins/              example plugin + plugin API
├── scripts/              backup · update · sync · uninstall
├── tests.sh              full test suite (50+ cases)
└── docs/                 FEATURES · API · PLUGIN-GUIDE · TROUBLESHOOTING · CHANGELOG
```

User data lives in **`~/.premium-os/`** (profiles, backups, snippets, settings, cache).

## 🔐 Security

- Config files are `chmod 600` (user-only)
- Cyber Lock passwords are salted **SHA-256** — never stored in plain text
- Optional **AES-256** backup encryption via `openssl`
- All user input validated & paths sanitized against command injection
- Plugins run sandboxed with explicit permissions

## 📏 Design Targets

- Install < 5 min · Menu load < 500 ms · Theme apply < 1 s · Total size < 50 MB
- Core RAM < 30 MB · Idle CPU < 5 % · works offline

## 🧪 Tests

```bash
bash tests.sh            # full suite
bash tests.sh --verbose
```

CI runs the suite on every push (`.github/workflows/ci.yml`).

## 📖 Documentation

- [docs/FEATURES.md](docs/FEATURES.md) — feature deep-dive
- [docs/API.md](docs/API.md) — bash function & REST API reference
- [docs/PLUGIN-GUIDE.md](docs/PLUGIN-GUIDE.md) — write your own plugin
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common issues
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — version history

---

<div align="center">
Built with 💜 for the Termux community · <b>Premium-OS</b>
</div>
