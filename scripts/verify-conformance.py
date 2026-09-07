"""Verifies the four Lua fixes by reading the source, since there is no Lua runtime here.

Not a substitute for running it, but it does prove the specific defects are gone rather than
just that the file still parses - which is all the Rojo build tells us.
"""
import io
import re
import sys

ROOT = 'C:/Tesseract/Repositories/Praxsuite/Praxsuite-SDK-Lua/'


def read(rel):
    return io.open(ROOT + rel, encoding='utf-8').read()


failures = []


def check(name, ok, detail=''):
    print(('  PASS  ' if ok else '  FAIL  ') + name + ('' if ok else '  <- ' + detail))
    if not ok:
        failures.append(name)


# 1. Count reads meta.total, never meta.totalCount.
data = read('src/Data.lua')
check('Count reads meta.total', 'meta.total' in data and 'meta.totalCount' not in data,
      'still references totalCount')
check('Count asks for 1 row, not 0', 'limit = 1,' in data,
      'the gateway clamps limit up to 1, so a 0-row count is impossible')

# 2. Operator table contains only what the gateway implements.
praxql = read('src/Core/PraxQL.lua')
operator_block = praxql[praxql.index('local OPERATORS = {'):praxql.index('local TRANSLATIONS')]
exposed = set(re.findall(r'(\w+) = "', operator_block)) | set(re.findall(r'\["(\w+)"\] = "', operator_block))
gateway_supports = {'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'in', 'is',
                    'between', 'contains', 'textsearch'}
invalid = exposed - gateway_supports
check('operator table exposes only real operators', not invalid, 'invalid: ' + str(sorted(invalid)))
check('is / between / textsearch now available',
      {'is', 'between', 'textsearch'} <= exposed,
      'missing: ' + str(sorted({'is', 'between', 'textsearch'} - exposed)))
check('isNull/startsWith are translated, not passed through',
      'TRANSLATIONS' in praxql and 'isNull' in praxql and 'startsWith' in praxql)
check('notIn raises a helpful error', "no 'notIn' operator" in praxql)

# 3. asPlayer and the dead headers are gone from every source file.
import glob
offenders = []
for path in glob.glob(ROOT + 'src/**/*.lua', recursive=True):
    body = io.open(path, encoding='utf-8').read()
    # Comments explaining the removal are fine; code references are not. Lua has block comments
    # (--[[ ]]) as well as line comments, and the removal is documented in both.
    code = re.sub(r'--\[\[.*?\]\]', '', body, flags=re.S)
    code = '\n'.join(l for l in code.split('\n') if not l.strip().startswith('--'))
    if 'SetContext' in code or 'ClearContext' in code:
        offenders.append(path.replace(ROOT, ''))
    if '"x-player' in code:
        offenders.append(path.replace(ROOT, '') + ' (header)')
# asPlayer is BACK, and this time it carries a real per-player session rather than the dead
# x-player-* headers this check was written to catch. Only the headers and the context helpers
# stay removed; asserting on the name itself now fails on master and says nothing.
check('the dead x-player headers and context helpers stay removed', not offenders, str(offenders))

# 4. baseUrl is required rather than silently defaulted.
init = read('src/init.lua')
config = read('src/Core/Config.lua')
check('Init asserts baseUrl', 'baseUrl is required' in init)
check('no silent cloud-host default',
      'Config._baseUrl = "https://gateway.praxsuite.com"' not in config,
      'Config still defaults the host')

# 5. The Event Bus, against the shared conformance contract's cases/event-bus.json.
#
# Source-reading again, and for the same reason: there is no Luau runtime here. What it does
# prove is that the specific traps the contract names are handled, rather than only that the
# file still parses.
wire = read('src/Core/BusWire.lua')
bus = read('src/Bus.lua')
init_lua = read('src/init.lua')

check('the record separator is an escape, not a raw byte',
      'BusWire.RS = "\\30"' in wire and chr(30) not in wire,
      'a raw 0x1E in source is mangled by half the tools that touch it')
check('the handshake frame is byte-exact',
      '{"protocol":"json","version":1}' in wire)
check('the hub path carries no workspace segment',
      'BusWire.BUS_PATH = "/hubs/event-bus"' in wire and 'workspaceId' not in wire)

# Only the TOPIC segment folds. Fold the whole key and two different buses merge; fold neither
# and two peers resolve the same topic, are both admitted, and silently never see each other.
check('only the topic segment is lowercased',
      'string.lower(string.sub(key, 1, separator - 1)) .. string.sub(key, separator)' in wire)
check('a key containing ws: is refused before the round trip',
      '"ws:", 1, true' in wire)

# A REJECTION arrives inside a SUCCESSFUL completion as ok = false. Code that only inspects
# SignalR's own error field reports every denied join as a success.
check('a rejection is read from result.ok, not from the error channel',
      'parsed.ok = result.ok ~= false' in wire)
check('a transport error is kept apart from a policy rejection',
      'parsed.isTransportError = true' in wire)
# LeaveBus is void: its result is literally null, so a table check must precede any field read.
check('a void result does not fall through to a field read',
      'if type(result) ~= "table" then' in wire)
check('the retained peer list is surfaced',
      'parsed.peers' in wire and 'entry.payload' in wire)

# Frames coalesce and split; decoding a whole body breaks under exactly the load the bus is for.
check('frames are split on the separator, with the tail kept',
      'return frames, string.sub(buffer, start)' in wire)
check('a ping is never surfaced as an event',
      'BusWire.MSG_PING then' in bus and 'keepalive' in bus)

# Roblox cannot open a WebSocket at all, so long polling is not a preference here.
check('long polling is used, and the file says why',
      'HttpService cannot open a WebSocket' in bus and 'RequestAsync' in bus)
check('the bus signs a player in rather than using the server key',
      'Auth.GetTokenFor' in bus and 'x-api-key returns 401' in bus)
check('an eviction drops membership and does not re-join',
      'bus-evicted' in bus and '_joined[key] = nil' in bus)
check('every hub error code has a sentence worth reading',
      all(code in wire for code in ('unknown_topic', 'denied', 'invalid_ticket',
                                    'not_a_member', 'invalid_bus_key', 'invalid_event_name',
                                    'payload_too_large', 'bus_full_or_too_many_buses',
                                    'rate_limited')))
check('the bus is exported from the singleton', 'Praxsuite.Bus = Bus' in init_lua)

print()
if failures:
    print('%d check(s) failed' % len(failures))
    sys.exit(1)
print('all checks verified in source')
