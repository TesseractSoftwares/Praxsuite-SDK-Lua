# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This project is licensed under the [Apache License 2.0](LICENSE).

## [0.1.0] - 2026-05-30

### Added

- **Core**: SDK initialization with `Praxsuite.Init()`
- **Core**: HTTP transport with automatic retry and exponential backoff
- **Core**: PraxQL query builder (converts Lua tables → gateway format)
- **Data**: `Query()` — read rows with where, orderBy, limit, offset, select
- **Data**: `Insert()` / `InsertMany()` — create one or multiple rows
- **Data**: `Update()` — modify rows matching conditions
- **Data**: `Delete()` — remove rows matching conditions
- **Data**: `Count()` — count rows matching conditions
- **Data**: `Batch()` — execute multiple operations in sequence
- **Endpoints**: `Call()` — invoke sync endpoint, wait for automation result
- **Endpoints**: `Fire()` — fire-and-forget async endpoint
- **Endpoints**: `Webhook()` — legacy webhook route support
- **Players**: `Identify()` — register player with Praxsuite backend
- **Players**: `Forget()` — cleanup on player leave
- **Players**: `SetContext()` / `ClearContext()` — manual player context
- **Schema**: `Fetch()` — auto-discover table names from gateway
- **Schema**: `Register()` / `RegisterMany()` — manual table registration
- **Where clause operators**: eq, neq, gt, gte, lt, lte, like, ilike, in, notIn, isNull, isNotNull, contains, startsWith, endsWith
- **Luau type annotations** for Roblox Studio autocomplete
- Wally package manifest
- Rojo project configuration
- GitHub Actions CI + Release workflows
