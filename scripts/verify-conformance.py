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
    if 'asPlayer' in code or 'SetContext' in code or 'ClearContext' in code:
        offenders.append(path.replace(ROOT, ''))
    if '"x-player' in code:
        offenders.append(path.replace(ROOT, '') + ' (header)')
check('asPlayer / context / dead headers removed from code', not offenders, str(offenders))

# 4. baseUrl is required rather than silently defaulted.
init = read('src/init.lua')
config = read('src/Core/Config.lua')
check('Init asserts baseUrl', 'baseUrl is required' in init)
check('no silent cloud-host default',
      'Config._baseUrl = "https://gateway.praxsuite.com"' not in config,
      'Config still defaults the host')

print()
if failures:
    print('%d check(s) failed' % len(failures))
    sys.exit(1)
print('all four fixes verified in source')
