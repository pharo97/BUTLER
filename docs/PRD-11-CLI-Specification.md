# PRD-11: BUTLER — Command Line Interface Specification

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

---

## 1. Overview

The `butler` CLI is a first-class interface to BUTLER. It provides installation, configuration, interaction, and diagnostic capability from any terminal without launching the GUI. Advanced users can script `butler` commands, integrate them into workflows, and operate BUTLER entirely from the shell.

The CLI communicates with the running BUTLER.app via a Unix domain socket. If BUTLER.app is not running, the CLI starts it in background mode before executing the command.

**Binary name:** `butler`
**Install locations:**
- Homebrew: `/opt/homebrew/bin/butler` (Apple Silicon) or `/usr/local/bin/butler` (Intel)
- Direct install: `/usr/local/bin/butler` (symlinked to `/Applications/Butler.app/Contents/MacOS/butler-cli`)
- Manual: anywhere on `$PATH`

---

## 2. Global Options

```
butler [--version] [--help] [--json] [--quiet] [--socket PATH] <command> [args]
```

| Flag | Short | Description |
|------|-------|-------------|
| `--version` | `-v` | Print version string and exit. Format: `butler 1.0.0 (build 42)` |
| `--help` | `-h` | Print help for the current command and exit |
| `--json` | | Output all responses as newline-delimited JSON (machine-readable) |
| `--quiet` | `-q` | Suppress all output except errors and explicit return values |
| `--socket PATH` | | Override default socket path (default: `~/.butler/run/butler.sock`) |
| `--no-launch` | | Do not auto-launch BUTLER.app if not running; exit with code 2 instead |

---

## 3. Command Groups

```
butler
├── install         Installation and update
├── uninstall       Removal
├── config          Configuration management
├── status          Runtime status
├── speak           Send a natural language command
├── trigger         Fire specific actions
├── history         Conversation and action history
├── permissions     Permission status and management
├── logs            Log access and filtering
├── reset           Reset subsystems
└── diagnostics     System health checks
```

---

## 4. Command Reference

### 4.1 `butler install`

```
butler install [--no-cli] [--no-launch-agent] [--dir PATH]
```

Registers BUTLER with the system. Does NOT download the binary — this assumes the .app is already present (via DMG or direct download). Installation means:
- Creates `~/.butler/` directory structure
- Installs CLI symlink to `/usr/local/bin/butler`
- Registers launchd user agent (optional) for auto-start on login
- Creates default configuration file at `~/.butler/config.json`
- Requests initial macOS permissions (microphone, speech recognition)

**Flags:**
| Flag | Description |
|------|-------------|
| `--no-cli` | Skip CLI symlink creation (GUI-only install) |
| `--no-launch-agent` | Do not register launchd agent (manual launch only) |
| `--dir PATH` | Specify alternate config directory (default: `~/.butler/`) |

**Exit codes:**
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 3 | Already installed |
| 4 | Insufficient permissions (sudo required for /usr/local/bin) |

**Output (default):**
```
Butler v1.0.0 installed.
  Config:     ~/.butler/config.json
  CLI:        /usr/local/bin/butler
  Socket:     ~/.butler/run/butler.sock
  LaunchAgent: com.butler.app (registered)

Run 'butler status' to verify.
```

---

### 4.2 `butler update`

```
butler update [--check-only] [--channel stable|beta]
```

Checks for and applies updates.

**Behavior:**
- Queries Sparkle appcast URL for latest version
- If update available: downloads, verifies signature, prompts to apply
- Applies update and relaunches BUTLER.app

**Flags:**
| Flag | Description |
|------|-------------|
| `--check-only` | Print available version without downloading |
| `--channel` | Select update channel (default: `stable`) |

**Output:**
```
Current version:   1.0.0
Available version: 1.1.0
Release notes:     https://butlerapp.com/releases/1.1.0

Apply update? [y/N] y
Downloading... ████████████████ 100%
Verifying signature... OK
Applying update...
Butler restarted at v1.1.0.
```

---

### 4.3 `butler uninstall`

```
butler uninstall [--keep-data] [--force]
```

Removes BUTLER from the system.

**Actions (in order):**
1. Stop BUTLER.app if running
2. Remove launchd agent registration
3. Remove CLI symlink at `/usr/local/bin/butler`
4. Remove `~/.butler/` directory (unless `--keep-data`)
5. Print confirmation

**Flags:**
| Flag | Description |
|------|-------------|
| `--keep-data` | Preserve `~/.butler/data/` (conversations, behavioral profile) |
| `--force` | Skip confirmation prompt |

**Output:**
```
The following will be removed:
  LaunchAgent:  com.butler.app
  CLI binary:   /usr/local/bin/butler
  Config & data: ~/.butler/ (147 MB)

Confirm? [y/N]
```

---

### 4.4 `butler config`

```
butler config <subcommand> [key] [value]
```

Read and write configuration values.

#### 4.4.1 `butler config list`
Print all current configuration as key-value pairs.

```
$ butler config list
voice.preset          = formal_british
voice.speed           = 1.0
personality.name      = Alfred
personality.formality = 4
personality.proactivity = 3
personality.humor     = 2
personality.directness = 4
permissions.tier      = 2
permissions.quiet_hours.start = 22:00
permissions.quiet_hours.end   = 08:00
api.key               = [SET]
api.model             = claude-opus-4-6
```

#### 4.4.2 `butler config get <key>`
```
$ butler config get personality.name
Alfred
```

#### 4.4.3 `butler config set <key> <value>`
```
$ butler config set voice.preset formal_british
$ butler config set personality.name "Sage"
$ butler config set personality.proactivity 4
$ butler config set permissions.quiet_hours.start 23:00
$ butler config set api.key sk-ant-xxxxx
```

**Validated key-value pairs:**

| Key | Type | Valid Values |
|-----|------|-------------|
| `voice.preset` | string | `formal_british`, `calm_american`, `direct_tactical`, `warm_mentor` |
| `voice.speed` | float | `0.75` – `1.5` |
| `personality.name` | string | Any non-empty string, max 32 chars |
| `personality.formality` | int | `1` – `5` |
| `personality.proactivity` | int | `1` – `5` |
| `personality.humor` | int | `1` – `5` |
| `personality.directness` | int | `1` – `5` |
| `permissions.tier` | int | `0` – `3` (raises system dialogs if increasing) |
| `permissions.quiet_hours.start` | time | `HH:MM` (24h) |
| `permissions.quiet_hours.end` | time | `HH:MM` (24h) |
| `api.key` | string | Stored in Keychain; value echoed as `[SET]` after |
| `api.model` | string | Valid Claude model ID |

**Exit codes:**
| Code | Meaning |
|------|---------|
| 0 | Success |
| 5 | Invalid key |
| 6 | Invalid value for key |
| 7 | Permission denied (tier elevation requires confirmation) |

#### 4.4.4 `butler config reset [key]`
Reset a specific key to default, or all keys if no argument.

```
$ butler config reset personality.humor
personality.humor reset to default (2).

$ butler config reset
Reset ALL configuration to defaults? [y/N]
```

---

### 4.5 `butler status`

```
butler status [--watch]
```

Print current runtime status of all BUTLER subsystems.

**Output:**
```
Butler v1.0.0 — Running

Core
  App status:       running (PID 8421)
  Uptime:           4h 32m
  Socket:           ~/.butler/run/butler.sock [connected]

Modules
  Activity Monitor:   active (tier 2)
  Context Analyzer:   active
  Intervention Engine: active (last trigger: 14m ago)
  Voice System:       ready (STT: Apple | TTS: native)
  Claude Integration: connected (claude-opus-4-6)
  Behavioral Memory:  healthy (db: 2.1 MB)
  Visualization Engine: rendering (state: idle)
  Automation Execution: standby
  Permission Manager: tier 2 active
  CLI Controller:     listening (socket active)

Permissions
  Microphone:       granted
  Speech Recognition: granted
  Accessibility:    granted
  Downloads folder: granted
  Calendar:         not granted
  Full Disk Access: not granted

Active Suppression
  Mode:             none
  Quiet Hours:      22:00 – 08:00 (inactive)
  Focus Mode:       off

Resources (last 60s avg)
  CPU:              1.2%
  Memory:           142 MB
  Battery impact:   low
```

**`--watch` flag:** Refreshes output every 2 seconds (like `top`).

**Exit codes:**
| Code | Meaning |
|------|---------|
| 0 | Running and healthy |
| 2 | Not running |
| 8 | Running but degraded (at least one module in error state) |

---

### 4.6 `butler speak`

```
butler speak "<natural language input>" [--no-voice] [--no-display]
```

Send a natural language command or question to BUTLER. Response is spoken via TTS and displayed in the Glass Chamber. Response text is also printed to stdout.

```
$ butler speak "Organize my Downloads folder by file type"
Alfred: I'll create subfolders by type and move your 147 files accordingly.
        Shall I proceed?

$ butler speak "What meetings do I have this afternoon?"
Alfred: You have a calendar event at 3 PM — I can see it's present but
        I don't have permission to read the title. Enable calendar access
        to get more detail.
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--no-voice` | Suppress TTS; text-only response to stdout |
| `--no-display` | Do not animate Glass Chamber; silent socket call |
| `--raw` | Print raw Claude response without personality formatting |

**Stdin support:**
```
echo "Summarize the last 10 actions I took" | butler speak
```

---

### 4.7 `butler trigger`

```
butler trigger <trigger-type> [--force]
```

Manually fire a specific suggestion trigger regardless of intervention score. Used for testing the suggestion engine or forcing a specific suggestion.

**Available triggers:**
| Trigger | Description |
|---------|-------------|
| `downloads-clutter` | Fire Downloads folder suggestion |
| `idle-detection` | Fire idle time suggestion |
| `focus-suggestion` | Fire focus mode suggestion |
| `late-night` | Fire late-night context suggestion |
| `app-switch` | Fire app-switching frequency suggestion |

```
$ butler trigger downloads-clutter
Intervention triggered: downloads_clutter
Score (forced): 1.0 (threshold bypassed)
BUTLER: "Your Downloads has 160 unsorted files. Shall I categorize them?"
```

**`--force`:** Bypasses all suppression rules (quiet hours, cooldowns, active video call). Used exclusively in development and testing. Requires explicit flag.

---

### 4.8 `butler history`

```
butler history <subcommand> [options]
```

#### 4.8.1 `butler history list`
```
$ butler history list [--limit N] [--since DATE] [--type conversation|action|suggestion]
```

```
$ butler history list --limit 5
  #   Time          Type          Summary
  ─────────────────────────────────────────────────────────
  42  Today 14:32   conversation  "Organize project files..."
  41  Today 11:05   suggestion    downloads_clutter (engaged)
  40  Today 10:18   action        Moved 34 files to Downloads/Organized/
  39  Today 09:44   conversation  "What's on my calendar?"
  38  Yesterday     suggestion    idle_detection (dismissed)
```

#### 4.8.2 `butler history show <id>`
Print full detail for a specific history entry.

#### 4.8.3 `butler history clear [--type TYPE] [--before DATE]`
Delete history entries. Requires confirmation.

---

### 4.9 `butler permissions`

```
butler permissions <subcommand>
```

#### 4.9.1 `butler permissions status`
```
$ butler permissions status

Permission Tiers
  Current tier: 2 (Context Awareness)

  Tier 0 — Passive:      active (always)
  Tier 1 — App Aware:    granted (2025-12-01)
  Tier 2 — Context:      partially granted
    Downloads folder:    granted
    Idle detection:      granted
    Calendar presence:   NOT GRANTED
    File metadata:       NOT GRANTED
  Tier 3 — Automation:   LOCKED (requires Tier 2 for 7+ days)

System Permissions
  Microphone:            granted
  Speech Recognition:    granted
  Accessibility API:     granted
  Full Disk Access:      NOT GRANTED
  Calendar:              NOT GRANTED

Suppressed Triggers
  downloads_clutter:     suppressed until 2026-03-05 (3x dismiss)
  idle_detection:        (no suppression)

Site Exclusions:         amazon.com, youtube.com
App Exclusions:          zoom.us, obs, keynote
```

#### 4.9.2 `butler permissions grant <permission>`
Request a specific system permission, opening the appropriate System Settings pane.

```
$ butler permissions grant calendar
Opening System Settings → Privacy & Security → Calendars...
Waiting for user action... granted.
```

#### 4.9.3 `butler permissions revoke <permission>`
Revoke a previously granted permission.

```
$ butler permissions revoke downloads-folder
Downloads folder monitoring disabled.
Tier 2 context awareness will continue with remaining permissions.
```

---

### 4.10 `butler logs`

```
butler logs [--module MODULE] [--level debug|info|warn|error] [--follow] [--since TIME] [--lines N]
```

Access BUTLER's structured log output.

```
$ butler logs --level warn --lines 20
2026-03-03 14:32:01 WARN  [InterventionEngine] Score 0.48 below threshold 0.65 — suppressed
2026-03-03 14:28:44 WARN  [VoiceSystem]        STT confidence 0.61 below threshold 0.70
2026-03-03 13:15:02 WARN  [ClaudeAPI]          Request latency 1.8s exceeded target 1.5s
```

**`--follow` flag:** Stream new log lines in real time (like `tail -f`).

**Available modules:**
`ActivityMonitor`, `ContextAnalyzer`, `LearningSystem`, `ReinforcementScorer`,
`InterventionEngine`, `ClaudeAPI`, `VoiceSystem`, `VisualizationEngine`,
`AutomationExecution`, `PermissionManager`, `CLIController`

---

### 4.11 `butler reset`

```
butler reset <subcommand>
```

| Subcommand | Effect |
|-----------|--------|
| `butler reset learning` | Wipes behavioral profile and reinforcement scores. Resets tolerance to 50. Keeps conversations. |
| `butler reset suppression` | Clears all suppressed trigger rules. |
| `butler reset personality` | Resets all personality config to defaults. Keeps API key. |
| `butler reset conversations` | Deletes all conversation history. Irreversible. |
| `butler reset all` | Full factory reset. Requires double confirmation. |

All reset commands require interactive confirmation unless `--force` is passed.

---

### 4.12 `butler diagnostics`

```
butler diagnostics [--verbose] [--export PATH]
```

Runs a full system health check. Used for debugging and support.

**Output:**
```
Butler Diagnostics Report — 2026-03-03 14:45:00

System
  macOS version:        15.2
  Architecture:         arm64 (Apple Silicon)
  BUTLER version:       1.0.0 (build 42)
  App path:             /Applications/Butler.app

Connectivity
  Claude API:           reachable (latency: 210ms)
  Socket:               connected (~/.butler/run/butler.sock)

Permissions
  Microphone:           OK
  Accessibility:        OK
  Speech Recognition:   OK
  Downloads:            OK
  Calendar:             MISSING
  Full Disk Access:     MISSING

Resource Usage (current)
  CPU:                  1.4%
  Memory (RSS):         138 MB
  Open file descriptors: 48

Database
  Path:                 ~/.butler/data/butler.db
  Size:                 2.1 MB
  Integrity:            OK (PRAGMA integrity_check)
  Last backup:          2026-03-03 08:00 OK

Voice System
  STT engine:           SFSpeechRecognizer (on-device)
  TTS engine:           AVSpeechSynthesizer
  Microphone test:      [not run — pass --verbose to test]

Recent Errors (last 24h)
  3 WARN  [InterventionEngine] score below threshold
  1 WARN  [VoiceSystem]        STT confidence below 0.70
  0 ERROR

Status: HEALTHY (2 non-critical warnings)
```

**`--export PATH`:** Write full diagnostic report as JSON to specified path.

---

## 5. Tab Completion

Shell completion scripts are installed for:
- **zsh:** `~/.butler/completions/_butler` (added to `$FPATH` by installer)
- **bash:** `~/.butler/completions/butler.bash` (sourced in `.bashrc` by installer)
- **fish:** `~/.config/fish/completions/butler.fish`

Completion covers:
- Command names
- Subcommand names
- `butler config set <key>` — completes known config keys
- `butler config set voice.preset` — completes valid values
- `butler logs --module` — completes module names
- `butler trigger` — completes trigger types
- `butler permissions grant/revoke` — completes permission names

---

## 6. Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General / unhandled error |
| 2 | BUTLER.app not running (and `--no-launch` set) |
| 3 | Already in requested state (install when installed, etc.) |
| 4 | Insufficient system privileges |
| 5 | Invalid configuration key |
| 6 | Invalid value for configuration key |
| 7 | Permission elevation required |
| 8 | Degraded state (partial success) |
| 9 | Timeout waiting for BUTLER.app to respond |
| 10 | IPC protocol error |

---

## 7. Output Format

### Default (human-readable)
Structured plain text. Aligned columns where applicable. Color-coded via ANSI codes when stdout is a TTY. Color suppressed when piped.

### JSON mode (`--json`)
Every response is a JSON object on a single line followed by `\n`.

```json
{"ok": true, "command": "config.get", "key": "personality.name", "value": "Alfred"}
{"ok": false, "command": "config.set", "error": "invalid_value", "key": "personality.formality", "detail": "Value must be integer 1–5, got 'high'"}
{"ok": true, "command": "status", "data": {...}}
```

### Error output
Errors go to stderr. Exit code is always non-zero on error.

```
$ butler speak ""
Error: speak requires a non-empty input string.
Usage: butler speak "<text>" [--no-voice] [--no-display]
```

---

## 8. `butler help` System

Every command and subcommand supports `--help`. The `butler help <command>` form is also supported.

```
$ butler help config set

NAME
    butler config set — Set a configuration value

SYNOPSIS
    butler config set <key> <value>

DESCRIPTION
    Sets the value for a configuration key. Changes take effect immediately
    in the running BUTLER process. Validated keys and their allowed values
    are listed below.

    The API key (api.key) is stored in macOS Keychain, not in the config
    file. It is never echoed in output.

KEYS
    voice.preset          formal_british | calm_american | direct_tactical
                          | warm_mentor
    voice.speed           Float: 0.75 – 1.5
    personality.name      String: max 32 characters
    personality.formality Int: 1 – 5
    ...

EXAMPLES
    butler config set personality.name "Sage"
    butler config set voice.preset formal_british
    butler config set permissions.quiet_hours.start 22:00

EXIT CODES
    0   Success
    5   Invalid key
    6   Invalid value
```

---

## 9. Scripting Support

`butler` is designed to be scriptable. All operations are:
- Deterministic (same input → same output)
- Non-interactive when `--force` is passed
- Machine-readable with `--json`

**Example script — reset learning if tolerance falls below 20:**
```bash
#!/bin/bash
TOLERANCE=$(butler config get learning.tolerance_score --json | jq -r '.value')
if [ "$TOLERANCE" -lt 20 ]; then
    echo "Tolerance critically low ($TOLERANCE). Resetting learning."
    butler reset learning --force
fi
```

**Example — status check in CI for integration tests:**
```bash
butler status --json | jq -e '.modules | to_entries | all(.value.status == "active")'
```
