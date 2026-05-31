# Contributing to Praxsuite SDK for Lua

Thank you for your interest in contributing! Here's how to get started.

## Development Setup

### Prerequisites

- [Aftman](https://github.com/LPGhatguy/aftman) — Toolchain manager
- [Rojo](https://rojo.space/) — Roblox project sync
- [Roblox Studio](https://create.roblox.com/) — For testing

### Setup

```bash
# Clone the repository
git clone https://github.com/TesseractSoftwares/Praxsuite-SDK-Lua.git
cd Praxsuite-SDK-Lua

# Install toolchain
aftman install

# Build the .rbxm
rojo build -o PraxsuiteSDK.rbxm

# Or sync live to Studio
rojo serve
```

## Code Style

- Use **tabs** for indentation (Roblox community standard)
- Max line width: **120 characters**
- Run `stylua src/` before committing
- Run `selene src/` to check for lint issues

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Write your code following the existing patterns
4. Ensure `rojo build` succeeds without errors
5. Submit a PR against `master`

## Architecture

```
src/
├── init.lua          -- Entry point (Praxsuite module table)
├── Core/
│   ├── Config.lua    -- Internal configuration state
│   ├── Http.lua      -- Transport layer (platform-adaptive)
│   └── PraxQL.lua    -- Query language builder
├── Data.lua          -- CRUD operations (Query, Insert, Update, Delete, Batch)
├── Endpoints.lua     -- Sync/Async endpoint calls
├── Players.lua       -- Player identity management
└── Schema.lua        -- Table name ↔ UUID registry
```

### Key Principles

- **Game developers never see PraxQL** — the SDK abstracts it completely
- **No global state leakage** — player context is explicit (via `asPlayer` option)
- **Errors are Lua tables** — `{ code, message, status, details }` for clean `pcall` handling
- **Platform-agnostic core** — only `Http.lua` has Roblox-specific code (future: adapters)

## Adding a New Platform Adapter

1. Create `src/adapters/{platform}/HttpAdapter.lua`
2. Implement: `Request(method, url, headers, body) → { status, body, headers }`
3. Implement: `GetSecret(name) → string`
4. Implement: `Wait(seconds)`
5. Update `init.lua` auto-detection

## Reporting Issues

Use [GitHub Issues](https://github.com/TesseractSoftwares/Praxsuite-SDK-Lua/issues) with:
- SDK version
- Platform (Roblox Studio / live server / FiveM)
- Minimal reproduction code
- Error message (full `pcall` output)

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
