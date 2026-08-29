# Premium-OS — Troubleshooting

---

## Installation issues

**`bash INSTALL.sh` says "Missing required tools"**
Install them in Termux: `pkg install tar gzip`. jq is optional but recommended:
`pkg install jq`.

**Menu shows raw `\033[...]` codes**
Your terminal is not reporting ANSI support. In Termux default sessions this
automatically works; if you piped/routed output through something, run Premium-OS
in a real TTY.

**`pos` alias not found after install**
The alias is added to `~/.bashrc` / `~/.zshrc`. Run `source ~/.bashrc` or open a
new session. Until then: `bash /path/to/Premium-OS/main.sh`.

## Themes & profiles

**Theme apply says "not found"**
List what Premium-OS sees: `bash main.sh theme list`. Custom themes live in
`~/.premium-os/themes/<name>.json` — check JSON validity with `jq . file`.

**Profile won't switch / "corrupted"**
Premium-OS validates profile JSON before switching. Inspect:
`jq . ~/.premium-os/profiles/<name>.json` — fix or delete the file and recreate.

**Settings messed up → factory reset (keep profiles)**
```bash
cp ~/.premium-os/settings.json /tmp/pos-settings-backup.json
rm ~/.premium-os/settings.json
bash main.sh theme current   # defaults are recreated
```

## Performance dashboard

**CPU stays 0 % in the CLI one-shot**
CPU % needs two samples. The live dashboard samples continuously — one-shot
`bash main.sh perf stats` self-samples with a short pause; values then update.

**Web dashboard shows "offline"**
Check the server is running (`bash main.sh dashboard`) and that you browse the
same host/port. The UI auto-reconnects every 3 s.

## Backups

**Restore failed: "corrupt or wrong password"**
The backup was created with `--encrypt` — you must supply the same password.

**Encrypted restore & non-openssl device**
`.poz.enc` needs `openssl`. Install it (`pkg install openssl-tool`) or re-create
backups without `--encrypt`.

## Plugins

**Install rejected: "dangerous code pattern"**
The static scanner found `rm -rf /`-like code. This is by design. If it's a
false positive, wrap the dangerous call behind a clearly-named helper or contact
the plugin author.

**Plugin doesn't react to hooks**
1. Its dir must contain `manifest.json` **and** `plugin.sh`.
2. The hook must be listed in `hooks` in the manifest.
3. Check it's enabled: `bash main.sh plugin list`.

## Cyber Lock

**Forgot the password**
```bash
jq '.security.cyber_lock_enabled=false | .security.lock_hash=""' \
  ~/.premium-os/settings.json > /tmp/s.json && \
  cat /tmp/s.json > ~/.premium-os/settings.json
chmod 600 ~/.premium-os/settings.json
```
(This is intentionally possible for the local device owner — Cyber Lock gates
casual access, it is not full-disk encryption.)

## Getting diagnostics

```bash
bash tests.sh                 # full self-test (125 checks)
bash tests.sh --verbose ui    # focused, with failure logs
POS_DEBUG=1 bash main.sh      # verbose internal logging
```
