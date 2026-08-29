#!/usr/bin/env bash
#==============================================================================
# Premium-OS :: plugins/example-plugin.sh
# Reference plugin demonstrating the Premium-OS plugin API.
# This file doubles as the template — copy it into a folder with a
# manifest.json to build your own plugin.
#
# Layout expected by the plugin manager:
#   my-plugin/
#   ├── manifest.json   (required metadata)
#   ├── plugin.sh       (this file)
#   ├── config.json     (optional runtime config)
#   └── README.md       (docs for your users)
#==============================================================================

#----------------------------------------
# manifest.json (place beside this file):
#----------------------------------------
# {
#   "name": "Example Plugin",
#   "version": "1.0.0",
#   "author": "Premium-OS",
#   "description": "Demonstrates hooks, permissions and sandboxed execution.",
#   "hooks": ["theme:applied", "profile:switched", "startup:init"],
#   "permissions": ["filesystem"],
#   "dependencies": []
# }
#==============================================================================

# Environment provided inside the sandbox:
#   POS_PLUGIN_DIR   — install directory of this plugin
#   POS_PLUGIN_NAME  — directory name
#   POS_HOOK         — the hook that fired (e.g. theme:applied)

plugin_on_event() { # $1=hook $2..=args
    local hook="$1"; shift
    case "$hook" in
        startup:init)
            # Runs once when Premium-OS starts
            ;;
        theme:applied)     # $1=theme_name
            echo "[example-plugin] theme applied: $1" \
                >> "$POS_PLUGIN_DIR/data/events.log" 2>/dev/null
            ;;
        profile:switched)  # $1=profile_name
            echo "[example-plugin] profile switched: $1" \
                >> "$POS_PLUGIN_DIR/data/events.log" 2>/dev/null
            ;;
        backup:created)
            ;;
    esac
}

# Optional named handlers also work (bash-friendly names, ':' → '_'):
# on_theme_applied() { local theme="$1"; ... }
# on_profile_switched() { local profile="$1"; ... }
