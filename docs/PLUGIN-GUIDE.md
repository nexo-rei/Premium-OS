# Premium-OS — Plugin Developer Guide

Write, package, and distribute a Premium-OS plugin in 5 minutes.

---

## 1. Plugin layout

```
my-plugin/
├── manifest.json    # required metadata
├── plugin.sh        # required entry point (bash)
├── config.json      # optional default config
└── README.md        # recommended docs
```

## 2. manifest.json

```json
{
  "name": "My Plugin",
  "version": "1.0.0",
  "author": "you",
  "description": "What it does, one line.",
  "hooks": ["theme:applied", "profile:switched"],
  "permissions": ["filesystem"],
  "dependencies": []
}
```

Rules:
- `name`, `version`, `author`, `description` are **required** (install fails otherwise)
- `hooks` lists events your plugin cares about (see §4)
- `permissions` are declarations users review before enabling you:
  `filesystem` · `network` · `shell` · `config` · `ui`

## 3. plugin.sh — write handlers

Two supported styles:

```bash
# Style A: single dispatcher
plugin_on_event() {
    local hook="$1"; shift
    case "$hook" in
        theme:applied)     mylog "theme → $1" ;;
        profile:switched)  mylog "profile → $1" ;;
    esac
}

# Style B: named functions (':' becomes '_')
on_theme_applied() { mylog "theme → $1"; }
```

Environment available inside the sandbox:

| Variable | Meaning |
|---|---|
| `POS_PLUGIN_DIR` | your install directory |
| `POS_PLUGIN_NAME` | your directory name |
| `POS_HOOK` | the hook that fired |

Shortly `source`ing `plugins/plugin-api.sh` (optional) gives you
`plugin_log`, `plugin_data_set/get` (per-plugin kv storage) and hook catalog helpers.

## 4. Hook reference

| Hook | Args | When |
|---|---|---|
| `startup:init` | — | Premium-OS finished booting |
| `theme:applied` | `$1=theme` | a theme got applied |
| `profile:switched` | `$1=profile` | profile switched |
| `backup:created` | `$1=file.poz` | backup finished |
| `restore:complete` | `$1=file.poz` | restore finished |
| `cleanup:complete` | — | cleanup done |
| `system:optimized` | — | optimizer applied |
| `plugin:installed` | `$1=dir-name` | new plugin installed |
| `update:available` | `$1=version` | updater noticed a new version |
| `ui:render` | — | dashboard render tick |

## 5. Sandbox & safety model

For each hook, your plugin runs in a **subshell** with:

- stdin closed (`</dev/null`), output redirected to the void — use `plugin_log`
- a **10-second watchdog** (long-running handlers get killed)
- no inherited functions (only what `plugin.sh` defines / sources)

At install time, Premium-OS **statically scans** your source and refuses plugins
containing destructive patterns (`rm -rf /`, fork bombs, `mkfs`, `dd if=`, …).

Good citizenship:

- Write only inside `$POS_PLUGIN_DIR/data` (create it when needed)
- Never block; schedule work or exit fast
- Treat `$1..$n` as untrusted text (quote expansions!)

## 6. Local install & test

```bash
bash main.sh plugin install ./my-plugin
bash main.sh plugin list
bash main.sh plugin info my-plugin
bash main.sh plugin disable my-plugin
bash main.sh plugin enable my-plugin
bash main.sh plugin uninstall my-plugin
```

Test manually: `bash main.sh theme apply neon` should fire your `theme:applied`
handler — check `$POS_PLUGIN_DIR/data/plugin.log` (if you used `plugin_log`).

## 7. Example

The complete working example ships at
[`plugins/example-plugin.sh`](../plugins/example-plugin.sh) — copy it, add a
manifest, edit handlers, done.

## 8. Publishing

Tar your plugin directory and host it anywhere (GitHub release, gist, static):

```bash
tar -czf my-plugin.tar.gz my-plugin/
```

Users install with `bash main.sh plugin install https://example.com/my-plugin.tar.gz`.

To be listed in the built-in marketplace view, open a PR against the Premium-OS
repo adding your entry to `features/plugin-manager.sh → plugin_marketplace()`.
