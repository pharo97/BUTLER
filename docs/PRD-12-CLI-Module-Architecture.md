# PRD-12: BUTLER — CLI Module Architecture & IPC Design

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering

---

## 1. Architecture Overview

BUTLER uses a two-binary model:

```
┌─────────────────────────────────────────────────────────────┐
│                      User's Terminal                        │
│                                                             │
│  $ butler speak "Organize my files"                         │
│            │                                                │
│            ▼                                                │
│  ┌──────────────────┐                                       │
│  │  butler binary   │  (CLI client, thin binary)            │
│  │  /usr/local/bin/ │                                       │
│  └────────┬─────────┘                                       │
│           │ Unix domain socket                              │
│           │ ~/.butler/run/butler.sock                       │
└───────────┼─────────────────────────────────────────────────┘
            │
┌───────────┼─────────────────────────────────────────────────┐
│           ▼                              BUTLER.app          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              CLI Controller Module                  │    │
│  │  (Unix socket server, command dispatcher)           │    │
│  └───────────────┬─────────────────────────────────────┘    │
│                  │ internal Swift calls                      │
│  ┌───────────────┴──────────────────────────────────────┐   │
│  │            11-Module BUTLER Core                     │   │
│  │  ActivityMonitor, ContextAnalyzer, VoiceSystem, ...  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Key architectural decision:** BUTLER.app serves as both the GUI application and the "daemon." There is no separate `butlerd` process. The CLI Controller Module within BUTLER.app runs a Unix domain socket server that accepts connections from the `butler` CLI binary.

If BUTLER.app is not running, the `butler` CLI launches it in background mode (`NSApp.setActivationPolicy(.accessory)` — no window, no dock icon) before connecting to the socket.

---

## 2. Binary Structure

### 2.1 BUTLER.app Bundle Layout

```
Butler.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   ├── Butler              ← Main GUI executable
│   │   └── butler-cli          ← CLI executable (symlink target)
│   ├── Resources/
│   │   ├── pulse.html
│   │   └── Assets.xcassets
│   └── Frameworks/
│       └── [Swift runtime if needed]
```

The `butler` binary in `/usr/local/bin/` is a symlink to `Butler.app/Contents/MacOS/butler-cli`.

Alternatively, for simpler distribution: `butler-cli` is a standalone binary bundled inside the .app but capable of being extracted and placed on `$PATH`. Both binaries share no dynamic library dependencies beyond system frameworks.

### 2.2 Swift Package Targets

```
// Package.swift (simplified)
let package = Package(
    name: "Butler",
    targets: [
        // Main GUI app
        .executableTarget(name: "Butler", dependencies: ["ButlerCore"]),

        // CLI binary — lightweight, connects to socket only
        .executableTarget(name: "butler-cli", dependencies: ["ButlerCLI"]),

        // Shared core library (not used by CLI directly)
        .target(name: "ButlerCore", ...),

        // CLI client library (socket protocol, command encoding)
        .target(name: "ButlerCLI", dependencies: ["ButlerIPCProtocol"]),

        // Shared IPC protocol types (used by both app and CLI)
        .target(name: "ButlerIPCProtocol", ...),
    ]
)
```

---

## 3. IPC Protocol

### 3.1 Transport

- **Socket type:** Unix domain socket (`AF_UNIX`, `SOCK_STREAM`)
- **Socket path:** `~/.butler/run/butler.sock`
- **Permissions:** `0600` (owner read/write only) — prevents other users from connecting
- **Connection model:** One connection per CLI invocation; CLI connects, sends request, reads response, disconnects

**Socket directory creation:**
```swift
// At app launch, before socket is created:
let socketDir = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".butler/run")
try FileManager.default.createDirectory(at: socketDir,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
```

### 3.2 Wire Format

Newline-delimited JSON (`\n` terminated). Each message is a single JSON object on one line. No framing header. Rationale: simple to implement in both Swift and shell scripts; debuggable with `nc`.

**Request envelope:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "version": "1",
  "command": "config.set",
  "args": {
    "key": "personality.name",
    "value": "Sage"
  },
  "auth_token": "sha256_of_session_token"
}
```

**Response envelope:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": true,
  "command": "config.set",
  "data": {
    "key": "personality.name",
    "previous": "Alfred",
    "current": "Sage"
  }
}
```

**Error response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": false,
  "command": "config.set",
  "error": {
    "code": "invalid_value",
    "message": "Value must be 1–5 characters.",
    "exit_code": 6
  }
}
```

**Streaming response (for `butler speak`, `butler logs --follow`):**
```json
{"id": "abc123", "type": "stream_start", "command": "speak"}
{"id": "abc123", "type": "stream_chunk", "data": {"text": "I'll organize"}}
{"id": "abc123", "type": "stream_chunk", "data": {"text": " your files by type."}}
{"id": "abc123", "type": "stream_end", "data": {"exit_code": 0}}
```

### 3.3 Command Registry

| Command String | Handler | Description |
|---------------|---------|-------------|
| `install` | `InstallCommandHandler` | System registration |
| `config.list` | `ConfigCommandHandler` | List all config |
| `config.get` | `ConfigCommandHandler` | Get single value |
| `config.set` | `ConfigCommandHandler` | Set single value |
| `config.reset` | `ConfigCommandHandler` | Reset to default |
| `status` | `StatusCommandHandler` | Full system status |
| `speak` | `SpeakCommandHandler` | NL command dispatch |
| `trigger` | `TriggerCommandHandler` | Manual trigger |
| `history.list` | `HistoryCommandHandler` | List history |
| `history.show` | `HistoryCommandHandler` | Show entry |
| `history.clear` | `HistoryCommandHandler` | Clear entries |
| `permissions.status` | `PermissionsCommandHandler` | Permission status |
| `permissions.grant` | `PermissionsCommandHandler` | Request permission |
| `permissions.revoke` | `PermissionsCommandHandler` | Revoke permission |
| `logs` | `LogsCommandHandler` | Filtered log access |
| `reset.learning` | `ResetCommandHandler` | Reset learning |
| `reset.suppression` | `ResetCommandHandler` | Clear suppressions |
| `reset.personality` | `ResetCommandHandler` | Reset personality |
| `reset.all` | `ResetCommandHandler` | Factory reset |
| `diagnostics` | `DiagnosticsCommandHandler` | Health check |

---

## 4. CLI Controller Module

### 4.1 Responsibilities
- Create and manage the Unix domain socket server
- Accept incoming CLI connections (concurrent, each on its own thread/task)
- Parse and validate JSON request envelopes
- Authenticate requests via session token
- Dispatch to appropriate command handler
- Return JSON responses
- Manage socket cleanup on app exit

### 4.2 Prohibited Behaviors
- Must not block the main thread
- Must not grant capabilities beyond what the user's current permission tier allows
- Must not accept connections from sockets with permissions other than current user's UID

### 4.3 Swift Implementation Sketch

```swift
// CLIControllerModule.swift
actor CLIController {
    private var server: UnixSocketServer?
    private let commandRouter: CommandRouter
    private let authToken: String  // Generated at app launch, written to ~/.butler/run/.auth

    func start() async throws {
        let socketPath = socketURL().path
        server = UnixSocketServer(path: socketPath, permissions: 0o600)
        try await server!.start()

        // Accept connections indefinitely
        for await connection in server!.connections {
            Task {
                await handleConnection(connection)
            }
        }
    }

    private func handleConnection(_ connection: UnixSocketConnection) async {
        defer { connection.close() }

        do {
            let requestData = try await connection.readLine()
            let request = try JSONDecoder().decode(CLIRequest.self, from: requestData)

            guard authenticate(request) else {
                try await connection.writeLine(authErrorResponse(for: request))
                return
            }

            let response = await commandRouter.route(request)
            try await connection.writeLine(JSONEncoder().encode(response))
        } catch {
            // Log error; connection already closed
        }
    }

    private func authenticate(_ request: CLIRequest) -> Bool {
        // Compare request.authToken to session token using constant-time comparison
        return request.authToken.constantTimeEquals(authToken)
    }

    private func socketURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".butler/run/butler.sock")
    }
}
```

### 4.4 Session Authentication

The CLI and app share a session token stored at `~/.butler/run/.auth` with permissions `0600`.

**Token lifecycle:**
1. On BUTLER.app launch: generate 32-byte random token, write to `~/.butler/run/.auth`
2. `butler` CLI binary: reads token from `~/.butler/run/.auth` at invocation
3. Token included in every request envelope
4. On app quit: delete `~/.butler/run/.auth` and `butler.sock`
5. On abnormal termination: socket file is stale; CLI detects this and relaunches app

**Why this approach:** Prevents unauthorized processes running as different users from sending commands to BUTLER. The token file is only readable by the owning user (0600). This is the same pattern used by Docker, Tailscale, and other daemon+CLI tools on macOS.

---

## 5. CLI Binary (`butler-cli`)

The `butler-cli` binary is intentionally thin. It does not contain business logic. Its sole responsibilities:

1. Parse command-line arguments and flags
2. Locate socket path (default or `--socket` override)
3. Read auth token from `~/.butler/run/.auth`
4. If BUTLER.app is not running:
   a. Launch `Butler.app` via `NSWorkspace.shared.open()`
   b. Poll for socket file to appear (max 5 seconds, 100ms intervals)
   c. If timeout: exit with code 2 + error message
5. Connect to socket
6. Encode and send JSON request
7. Read response(s) until stream_end or connection close
8. Format and print to stdout/stderr per `--json` / default mode
9. Exit with appropriate exit code

```swift
// main.swift (butler-cli)
@main
struct ButlerCLI {
    static func main() async {
        let cli = CommandLineParser().parse(CommandLine.arguments)
        let client = IPCClient(socketPath: cli.socketPath, authToken: readAuthToken())

        do {
            try await client.ensureAppRunning(noLaunch: cli.noLaunch)
            let response = try await client.execute(cli.request)
            Formatter(jsonMode: cli.json, quiet: cli.quiet).print(response)
            exit(Int32(response.exitCode))
        } catch IPCError.notRunning {
            fputs("Error: Butler is not running. Start it from /Applications/Butler.app\n", stderr)
            exit(2)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
```

---

## 6. App Launch Behavior

BUTLER.app supports two launch modes:

### 6.1 GUI Mode (normal launch)
- User opens app from Finder, Spotlight, or Dock
- Full Glass Chamber UI appears
- Socket server starts

### 6.2 Headless Mode (CLI-triggered launch)
```
butler <any command>  ← BUTLER.app not running
```
- `butler-cli` detects app not running
- Launches: `open -a Butler.app --args --headless`
- App starts with `--headless` flag:
  - `NSApp.setActivationPolicy(.prohibited)` — no menu bar, no dock icon, no windows
  - Socket server starts
  - All modules initialize normally
  - No Glass Chamber UI rendered
- CLI connects to socket, executes command
- App remains running in background for subsequent CLI calls

Headless mode is exited when:
- User explicitly opens the GUI (`butler status` → user clicks "Open Butler" link)
- User launches BUTLER.app directly (app detects existing headless instance and promotes it to GUI mode)
- `butler uninstall` is called

---

## 7. Socket Lifecycle

```
App launch
│
├── Generate session token → write ~/.butler/run/.auth (0600)
├── Bind socket at ~/.butler/run/butler.sock (0600)
├── Start accepting connections
│
│   [CLI invocations — each a separate connection lifecycle]
│   ├── connect()
│   ├── send request JSON
│   ├── receive response JSON
│   └── close()
│
App quit (normal)
├── Close socket server
├── unlink("~/.butler/run/butler.sock")
└── unlink("~/.butler/run/.auth")

App crash (abnormal)
├── Socket file remains (stale)
├── Auth file remains
│
Next CLI invocation
├── Attempts connect() → ECONNREFUSED
├── Detects stale socket
├── Relaunches app
└── Retries connection
```

---

## 8. Command Handlers

Each command handler is a Swift actor (concurrency-safe). Handlers call directly into the module they own — no secondary IPC. All operations within BUTLER.app are in-process.

```swift
// Example: SpeakCommandHandler
actor SpeakCommandHandler: CommandHandler {
    let claudeLayer: ClaudeIntegrationLayer
    let voiceSystem: VoiceSystem

    func handle(_ request: CLIRequest) async -> CLIResponse {
        guard let text = request.args["text"] as? String, !text.isEmpty else {
            return .error(code: "missing_argument", message: "speak requires non-empty text", exitCode: 1)
        }

        // Route to Claude integration layer
        do {
            let stream = try await claudeLayer.sendMessage(text, context: .cliInitiated)
            // Stream response back to CLI
            return .stream(stream.map { .chunk(text: $0) })
        } catch {
            return .error(code: "claude_error", message: error.localizedDescription, exitCode: 1)
        }
    }
}
```

---

## 9. Directory Structure

```
~/.butler/
├── config.json              ← Personality and behavior settings (not API key)
├── run/
│   ├── butler.sock          ← Unix domain socket (exists only while app is running)
│   └── .auth                ← Session token (exists only while app is running)
├── data/
│   └── butler.db            ← SQLite behavioral database (encrypted)
├── logs/
│   ├── butler.log           ← Current log file
│   └── butler.log.1         ← Previous log (rotated)
└── completions/
    ├── _butler              ← zsh completion script
    ├── butler.bash          ← bash completion script
    └── butler.fish          ← fish completion script
```

---

## 10. Homebrew Integration

Homebrew installs the `butler` CLI binary only — not the full .app. The Homebrew formula:

```ruby
class Butler < Formula
  desc "BUTLER AI companion — CLI interface"
  homepage "https://butlerapp.com"
  url "https://github.com/butler-app/butler-cli/releases/download/v1.0.0/butler-cli-1.0.0.tar.gz"
  sha256 "..."
  license "Commercial"
  version "1.0.0"

  def install
    bin.install "butler"
    bash_completion.install "completions/butler.bash"
    zsh_completion.install "completions/_butler"
    fish_completion.install "completions/butler.fish"
  end

  def caveats
    <<~EOS
      The butler CLI requires BUTLER.app to be installed separately.
      Download from: https://butlerapp.com/download

      After installing BUTLER.app, run:
        butler install
    EOS
  end

  test do
    assert_match "butler", shell_output("#{bin}/butler --version")
  end
end
```

The GUI .app is distributed separately (direct download / DMG). The Homebrew formula is `butler-cli` (or `butler` in a custom tap: `brew install butler-app/tap/butler`).
