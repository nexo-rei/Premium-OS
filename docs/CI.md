# Continuous Integration

Premium-OS ships its GitHub Actions pipeline as an example asset:

**Enable it (repo admin):**
```bash
mkdir -p .github/workflows
cp docs/ci.yml.example .github/workflows/ci.yml
git add .github/workflows/ci.yml && git commit -m "Enable CI"
```

The workflow runs two jobs on every push/PR:
- **bash-suite** — syntax check of every `.sh`, optional shellcheck, the full
  `tests.sh` suite (125 checks), JSON asset validation, and an isolated-HOME
  installer dry run.
- **web-dashboard** — `node --check` on all dashboard JS + the zero-dep
  REST/WebSocket smoke test (`web/test/smoke.js`, 25 assertions).

> Note: pushing workflow files requires a token/app with the `workflows`
> permission — which is why this file ships in `docs/`.
