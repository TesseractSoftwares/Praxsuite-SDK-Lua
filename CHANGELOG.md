# Changelog

All notable changes to the Praxsuite SDK for Lua.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-20

Four bugs fixed. Each one failed silently or at runtime rather than at build time, and each has
been live since the SDK was first published, so this release is worth taking.

### Fixed

- **`Data.Count` always returned 0.** It read `meta.totalCount`; the gateway sends `meta.total`
  (`PraxQLResultMeta`). Nothing errored - the field was simply absent, so every count came back
  as zero. It now reads the right field, and raises a clear error if the gateway returns no total
  at all (which means aggregations are disabled on that table's scope). The count query also asks
  for one row instead of zero, because the gateway clamps `limit` up to a minimum of 1.

- **Five operators the gateway does not implement have been removed.** `notIn`, `isNull`,
  `isNotNull`, `startsWith` and `endsWith` were offered by the operator table; the PraxQL parser
  accepts none of them, so every query using one failed at runtime in a live game. The four that
  have a sensible equivalent are now **translated** rather than passed through:
  `isNull` to `is null`, `isNotNull` to `neq null`, `startsWith`/`endsWith` to `like` with the
  wildcard applied. `notIn` has no equivalent and now raises an error explaining what to do
  instead. `is`, `between` and `textsearch` - which the gateway does implement and this SDK never
  exposed - have been added.

- **`asPlayer` has been removed, because it scoped nothing.** It set `x-player-platform` and
  `x-player-id` request headers, and no code path in the Praxsuite gateway reads either. It read
  like a security boundary while being decorative, which is worse than not existing.

  **This is not a loss of capability on Roblox.** The SDK runs in `ServerScriptService` with a
  server key, so your game server is the trusted party - enforce per-player rules in your own
  server code, exactly as you would for a DataStore write. The gateway's row-filter isolation
  exists for *untrusted* clients that authenticate as an end user (a browser, a Unity build); a
  trusted game server is a different model.

- **`baseUrl` is now required.** It defaulted to the Praxsuite Cloud host, which returns 404 for
  every call from a workspace on a dedicated tier - the single most confusing failure this SDK
  produced, because nothing in the error said "wrong host". `Init` now asserts it and the message
  explains where to find the right value.

### Changed

- `SetContext` / `ClearContext` removed from `Players`. They existed only to set the dead headers
  above. Identify and resolve are unchanged and still useful for analytics and account linking.
- Azure DevOps is now the source of truth, mirrored to GitHub on every master push.
- Licence is the Praxsuite Open SDK Licence v1.0, matching the other Praxsuite SDKs.

### Migration

```lua
-- Before
Praxsuite.Init({ workspaceId = "...", apiKeySecret = "PraxKey" })
Praxsuite.Data.Query("saves", { where = { level = { isNull = true } } , asPlayer = player })
local n = Praxsuite.Data.Count("saves")   -- always 0

-- After
Praxsuite.Init({
    workspaceId = "...",
    apiKeySecret = "PraxKey",
    baseUrl = "https://gateway.praxsuite.com",   -- now required
})
-- isNull still works; it is translated to the operator the gateway has.
-- asPlayer is gone: scope by a column you control instead.
Praxsuite.Data.Query("saves", { where = { level = { isNull = true }, owner = player.UserId } })
local n = Praxsuite.Data.Count("saves")   -- now correct
```
