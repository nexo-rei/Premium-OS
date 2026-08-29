# Premium-OS — API Reference

Two surfaces: the **bash CLI API** (scriptable functions / subcommands) and the
**REST + WebSocket API** of the web dashboard.

---

## 1. Bash API

`source` the modules, or use `bash main.sh <group> <action>`. Every function
returns `0` on success, non-zero on failure, and prints human-readable status.

### Profiles — `core/profile.sh`

| Function | Description |
|---|---|
| `create_profile <name>` | Create from template |
| `switch_profile <name>` | Make active (validates JSON) |
| `delete_profile <name>` | Remove (`default` protected) |
| `duplicate_profile <src> <dest>` | Clone |
| `rename_profile <old> <new>` | Rename |
| `list_profiles` | Print profile names |
| `get_active_profile` | Echo active profile |
| `profile_exists <name>` | → 0/1 |
| `export_profile <name> [dir]` | → `<name>.profile.json` |
| `import_profile <file.json>` | Install exported profile |
| `merge_profile <name>` | Merge theme/aliases into active |
| `profile_preview <name>` | Pretty summary |

CLI: `bash main.sh profile list|active|create|switch|delete|duplicate|rename|import|export|preview`

### Themes — `core/theme.sh`

| Function | Description |
|---|---|
| `list_themes` | Built-in + custom (`(custom)` suffix) |
| `apply_theme <name>` | Apply (self-heals missing settings) |
| `theme_preview <name>` | ANSI swatch preview |
| `create_custom_theme [name]` | Interactive creator |
| `theme_file_for <name>` | Echo backing JSON path |
| `get_current_theme` | Active theme name |
| `export_theme <name> [out]` | Copy JSON out |

Theme-creator extras (`features/theme-creator.sh`): `display_color_picker`,
`get_color_input`, `suggest_color_harmony`, `save_custom_theme`,
`export_theme_code`, `theme_creator_ui`.

### Performance — `features/performance-monitor.sh`

| Function | Description |
|---|---|
| `get_cpu_usage` | Integer %, two-sample /proc/stat |
| `get_memory_usage` / `get_ram_usage` | `usedMB totalMB pct` |
| `calculate_uptime` | `session Xh Ym Zs · system …` |
| `get_process_count` | /proc enumeration |
| `benchmark_terminal [n]` | Loop-dispatch cmds/s |
| `get_performance_stats` | `cpu=.. ram=.. procs=.. …` one-liner |
| `display_dashboard [secs]` | Live full-screen view |
| `get_performance_history 1h|24h` | CSV rows |
| `export_report [out.csv]` | Write CSV |

### Backup — `features/backup-restore.sh`

`create_backup [--encrypt]` (echoes archive path) · `restore_backup <file> [--replace|--merge]`
· `list_backups` · `delete_backup <file>` · `backup_verification <file>`
· `preview_backup` / `backup_explorer <file>` · `rollback_restore`
· `export_portable [dir]` / `import_portable <file>` · `schedule_backup <freq>`

### Cleanup — `features/cleanup.sh`

`dry_run_cleanup` · `cleanup_history` · `cleanup_temp_files` · `cleanup_cache`
· `cleanup_packages` · `get_cleanup_report h t c p` · `post_cleanup_verification`
· `schedule_cleanup` · `cleanup_all_auto` · `display_cleanup_menu`

### Optimizer — `features/optimization.sh`

`benchmark_startup` · `optimize_startup_scan` · `optimize_recommend`
· `optimize_apply` · `optimize_compare` · `optimization_menu`

### Snippets — `features/snippets.sh`

`add_snippet <cat> <name> <cmd>` · `remove_snippet <id>` · `list_snippets [cat]`
· `search_snippet <term>` · `get_snippet_command <id>` · `execute_snippet <id>`

### Hotkeys — `features/hotkeys.sh`

`register_hotkey <key> <cmd>` · `remove_hotkey <key>` · `list_hotkeys`
· `test_hotkey <key>` · `export_hotkeys [out]`

### Smart — `features/smart-suggestions.sh`

`analyze_usage_pattern` · `detect_active_task` · `suggest_theme`
· `learn_preference <theme> accept|reject` · `weekly_rotation` · `fetch_weather` (opt-in)

### Plugins — `features/plugin-manager.sh`

`install_plugin <dir|url>` · `uninstall_plugin <name>` · `enable_plugin <name>`
· `disable_plugin <name>` · `list_plugins` · `get_plugin_info <name>`
· `validate_plugin <dir>` · `execute_plugin <name> [action]`
· `plugin_marketplace` · `plugin_settings <name>` · `pos_emit_hook <hook> [args…]`

### Config & security — `core/config.sh`, `core/security.sh`

`pos_config_get <dot.path> [default]` · `pos_config_set <dot.path> <val> [number|bool]`
· `pos_config_validate` · `pos_config_merge_defaults`
· `cyber_lock_setup` · `cyber_lock_verify` · `cyber_lock_disable` · `cyber_lock_is_enabled`
· `pos_hash_password <pw>` · `pos_encrypt_file/pos_decrypt_file <in> <out> <pw>`
· `pos_sanitize_path <p>` · `pos_secure_store <k> <v>` · `pos_secure_read <k>`

---

## 2. REST API (dashboard, port 8080)

All bodies JSON. `POS_HOME` is the shared data dir, so CLI ⇄ web stay in sync.

| Method | Path | Notes |
|---|---|---|
| GET | `/api/health` | `{ok,version}` |
| GET | `/api/profiles` | list |
| POST | `/api/profiles` | `{name, ...}` create |
| GET/PUT/DELETE | `/api/profiles/:id` | read/update/delete (default protected) |
| POST | `/api/profiles/:id/switch` | activate |
| GET | `/api/themes` | built-ins + custom |
| POST | `/api/themes` | create custom |
| GET/DELETE | `/api/themes/:id` | read; delete only custom |
| GET | `/api/performance` | `{cpu,ram,processes,uptime,timestamp}` |
| GET | `/api/performance/history` | `[{epoch,cpu,ram}]` |
| POST | `/api/backup` | create `.poz` |
| GET | `/api/backups` | list with sizes |
| POST | `/api/restore` | `{file}` |
| GET/POST | `/api/snippets` | list/create |
| PUT/DELETE | `/api/snippets/:id` | update/remove |
| GET/POST | `/api/hotkeys` | list/register (conflict → 400) |
| DELETE | `/api/hotkeys/:id` | (`:id` = url-encoded combo) |
| GET/PUT | `/api/settings` | full doc or `{set:"dot.path",value}` |
| GET | `/api/plugins` | list |
| POST | `/api/plugins` | inline install, dangerous-code scan |
| DELETE | `/api/plugins/:id` | uninstall |

Error envelope: `{ "error": "message" }` with proper 4xx/5xx codes.

## 3. WebSocket `/ws`

Client → server: `{type:"ping"}`, `{type:"subscribe",channel:"performance"}`

Server → client events (JSON `{event,data}`):

| Event | Payload | Cadence |
|---|---|---|
| `connected` | `{ok,clients}` | on join |
| `performance:update` | same as GET `/api/performance` | every 2 s |
| `profile:switched` | `{id}` | on switch |
| `backup:created` | `{file}` | after backup |
| `restore:complete` | `{file}` | after restore |
| `plugin:installed` | `{id}` | after install |
