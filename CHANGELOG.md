# Changelog

All notable changes to this project are documented here.

## [1.1.0] — 2026-11-07

### Added
- CSV export (`-f csv`), alongside the existing table and JSON formats
- `-g, --filter PATTERN` — only show/export networks whose SSID contains `PATTERN` (case-insensitive)
- Exported files are now automatically `chmod 600`'d — they hold plaintext credentials and should never be left group/world-readable
- New banner and refreshed README

## [1.0.0] — 2026-11-06

Initial public release.

### Added
- Linux extraction via `nmcli`, raw NetworkManager connection files, `wpa_supplicant` configs, `iwd` profiles, and `connman` settings — results merged and de-duplicated by SSID
- macOS extraction via `networksetup` (preferred network list) + Keychain (`security find-generic-password`)
- Interactive selector mode (`-s`, default) and full-dump mode (`-a`)
- Export to a plain-text table (`-o file.txt`) or structured JSON (`-o file.json -f json`)
- `--debug` diagnostic scan that reports which backends exist on the system and what they contain, without extracting any credentials
- Automatic color detection (disables ANSI colors on non-interactive output or when `NO_COLOR` is set), plus an explicit `--no-color` flag
- `--version` / `-v`
