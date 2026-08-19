# Praxsuite SDK para Roblox — Guía de Implementación

## Requisitos Previos

- Una cuenta de Praxsuite con un workspace activo
- Una tabla creada en Praxsuite con las columnas que vas a usar
- Una API Key generada desde el panel de Gateway de tu workspace
- Roblox Studio instalado

---

## Paso 1: Instalar el SDK

Descarga el módulo `PraxsuiteSDK` y colócalo dentro de `ServerScriptService` en tu juego de Roblox. La estructura debe quedar así:

```
ServerScriptService/
  PraxsuiteSDK/
    PraxsuiteSDK (ModuleScript)
```

> **Importante:** El SDK solo funciona desde scripts del servidor (ServerScripts). Nunca lo uses en LocalScripts por seguridad — tu API Key estaría expuesta al cliente.

---

## Paso 2: Importar Dependencias

```lua
local Praxsuite = require(game:GetService("ServerScriptService").PraxsuiteSDK.PraxsuiteSDK)
local Players = game:GetService("Players")
```

| Línea | Qué hace |
|-------|----------|
| `require(game:GetService("ServerScriptService").PraxsuiteSDK.PraxsuiteSDK)` | Importa el SDK desde ServerScriptService. Es un singleton — lo inicializas una vez y lo usas en cualquier script. |
| `game:GetService("Players")` | Servicio de Roblox para acceder a los jugadores conectados. Lo usamos para obtener el UserId. |

---

## Paso 3: Inicializar el SDK

```lua
Praxsuite.Init({
    workspaceId = "YOUR-WORKSPACE-ID-HERE",
    apiKey = "sk_live_YOUR_SERVER_KEY_HERE",
    autoFetchSchema = false,
})
```

### ¿Qué significa cada parámetro?

| Parámetro | Descripción |
|-----------|-------------|
| `workspaceId` | El UUID de tu workspace en Praxsuite. Lo encuentras en la URL de tu workspace o en **Configuración > General**. |
| `apiKey` | Tu clave secreta de API. Comienza con `sk_live_`. Se genera desde el panel de **Gateway** en Praxsuite. **Nunca la expongas en código del cliente.** |
| `autoFetchSchema` | Si es `true`, el SDK consulta automáticamente las tablas disponibles al iniciar. Si es `false`, debes registrar las tablas manualmente (más rápido y predecible para producción). |

> `Init()` se llama **una sola vez** al arrancar el servidor. Después de eso, cualquier otro script puede hacer `require` del SDK y ya estará configurado.

---

## Paso 4: Registrar tu Tabla

```lua
Praxsuite.Schema.Register("Roblox Leaderboard", "YOUR-TABLE-ID-HERE")
```

| Parámetro | Descripción |
|-----------|-------------|
| `"Roblox Leaderboard"` | El **nombre amigable** que usarás en tu código para referirte a esta tabla. Puede ser cualquier string. |
| `"YOUR-TABLE-ID-HERE"` | El **UUID de la tabla** en Praxsuite. Lo encuentras en la configuración de la tabla, sección API. |

Cuando usas `autoFetchSchema = false`, debes registrar cada tabla que vayas a usar. Esto evita una llamada HTTP extra al inicio y hace tu juego más predecible.

---

## Paso 5: Insertar Datos

```lua
local myId = tostring(Players.LocalPlayer and Players.LocalPlayer.UserId or "server_test")
local rows = {}
for i = 1, 5 do
    table.insert(rows, {
        ["Record"] = "Game Session " .. os.date("%Y-%m-%d %H:%M:%S") .. " #" .. i,
        ["Player Id"] = myId,
        ["Points"] = math.random(10, 500),
    })
end

print("[Praxsuite] Inserting 5 rows...")
local inserted = Praxsuite.Data.InsertMany("Roblox Leaderboard", rows)
print("[Praxsuite] Inserted " .. #inserted .. " rows!")
```

### ¿Qué significa cada parte?

| Elemento | Descripción |
|----------|-------------|
| `["Record"]`, `["Player Id"]`, `["Points"]` | Son los **nombres exactos de las columnas** en tu tabla de Praxsuite. Deben coincidir exactamente (mayúsculas, espacios, todo). |
| `table.insert(rows, {...})` | Construye un array de filas. Cada fila es una tabla Lua donde las keys son nombres de columna y los values son los datos. |
| `Praxsuite.Data.InsertMany("Roblox Leaderboard", rows)` | Envía **múltiples filas en una sola petición HTTP**. Mucho más eficiente que hacer un `Insert` por cada fila. |
| `#inserted` | Devuelve cuántas filas se insertaron exitosamente. |

> **Tip:** Usa `InsertMany` siempre que tengas más de una fila. Reduce las llamadas HTTP y es más rápido.

---

## Paso 6: Consultar Datos (Query)

```lua
local leaderboard = Praxsuite.Data.Query("Roblox Leaderboard", {
    select = { "Record", "Player Id", "Points" },
    orderBy = { "Points", "desc" },
    limit = 25,
})
```

### Opciones de Query

| Opción | Descripción | Ejemplo |
|--------|-------------|---------|
| `select` | Lista de columnas a devolver. Si se omite, devuelve todas. | `{ "Record", "Points" }` |
| `orderBy` | Columna y dirección de ordenamiento. | `{ "Points", "desc" }` |
| `limit` | Máximo de filas a devolver. | `25` |
| `where` | Filtros de condición (ver sección siguiente). | `{ player_id = "123" }` |
| `offset` | Saltar N filas (para paginación). | `50` |

---

## Paso 7: Mostrar Resultados

```lua
print("\n=== LEADERBOARD (Top 25) ===")
for rank, row in ipairs(leaderboard) do
    print(rank .. ". " .. tostring(row["Player Id"]) .. " - " .. tostring(row["Points"]) .. " pts (" .. tostring(row["Record"]) .. ")")
end
```

El resultado de `Query` es un **array de tablas Lua**. Cada elemento es una fila donde accedes a los valores por nombre de columna: `row["NombreColumna"]`.

---

## Script Completo

```lua
local Praxsuite = require(game:GetService("ServerScriptService").PraxsuiteSDK.PraxsuiteSDK)
local Players = game:GetService("Players")

-- 1. Inicializar (una sola vez)
Praxsuite.Init({
    workspaceId = "YOUR-WORKSPACE-ID-HERE",
    apiKey = "sk_live_YOUR_SERVER_KEY_HERE",
    autoFetchSchema = false,
})

-- 2. Registrar tabla
Praxsuite.Schema.Register("Roblox Leaderboard", "YOUR-TABLE-ID-HERE")

-- 3. Insertar datos
local myId = tostring(Players.LocalPlayer and Players.LocalPlayer.UserId or "server_test")
local rows = {}
for i = 1, 5 do
    table.insert(rows, {
        ["Record"] = "Game Session " .. os.date("%Y-%m-%d %H:%M:%S") .. " #" .. i,
        ["Player Id"] = myId,
        ["Points"] = math.random(10, 500),
    })
end

local inserted = Praxsuite.Data.InsertMany("Roblox Leaderboard", rows)
print("[Praxsuite] Inserted " .. #inserted .. " rows!")

-- 4. Consultar leaderboard
local leaderboard = Praxsuite.Data.Query("Roblox Leaderboard", {
    select = { "Record", "Player Id", "Points" },
    orderBy = { "Points", "desc" },
    limit = 25,
})

-- 5. Mostrar resultados
for rank, row in ipairs(leaderboard) do
    print(rank .. ". " .. tostring(row["Player Id"]) .. " - " .. tostring(row["Points"]) .. " pts")
end
```

---

## Más Operaciones: Expandiendo tu Integración

### Filtrar con Where

```lua
-- Igualdad simple
local mis_filas = Praxsuite.Data.Query("Roblox Leaderboard", {
    where = { ["Player Id"] = "12345" }
})

-- Mayor que
local top_players = Praxsuite.Data.Query("Roblox Leaderboard", {
    where = { Points = { gt = 100 } }
})

-- Contiene texto
local busqueda = Praxsuite.Data.Query("Roblox Leaderboard", {
    where = { Record = { like = "%Session%" } }
})
```

### Operadores Disponibles

| Operador | Significado | Ejemplo |
|----------|-------------|---------|
| `eq` | Igual a (por defecto) | `{ campo = valor }` |
| `neq` | No igual a | `{ campo = { neq = valor } }` |
| `gt` / `gte` | Mayor que / Mayor o igual | `{ Points = { gt = 100 } }` |
| `lt` / `lte` | Menor que / Menor o igual | `{ Points = { lt = 50 } }` |
| `like` | Contiene (usa % como comodín) | `{ name = { like = "%john%" } }` |
| `in` | Está en una lista | `{ status = { ["in"] = {"active","pending"} } }` |
| `isNull` | Es nulo | `{ campo = { isNull = true } }` |

### Actualizar Datos (Update)

```lua
Praxsuite.Data.Update("Roblox Leaderboard", {
    set = { Points = 999 },
    where = { ["Player Id"] = "12345" }
})
```

- `set` → qué columnas cambiar y a qué valor
- `where` → qué filas afectar (**siempre incluye un where** para no modificar toda la tabla)

### Eliminar Datos (Delete)

```lua
Praxsuite.Data.Delete("Roblox Leaderboard", {
    where = { ["Player Id"] = "12345" }
})
```

### Contar Filas (Count)

```lua
local total = Praxsuite.Data.Count("Roblox Leaderboard")
local activos = Praxsuite.Data.Count("Roblox Leaderboard", { Points = { gt = 0 } })
```

### Insertar Una Sola Fila

```lua
Praxsuite.Data.Insert("Roblox Leaderboard", {
    ["Record"] = "Boss Kill",
    ["Player Id"] = tostring(player.UserId),
    ["Points"] = 50,
})
```

---

## Consejos de Producción

- Usa `autoFetchSchema = false` y registra tablas manualmente — es más rápido y no depende de una llamada extra al inicio.
- Siempre usa el SDK desde **ServerScripts**, nunca desde LocalScripts.
- Usa `InsertMany` cuando tengas múltiples filas — reduce las llamadas HTTP.
- Agrega `limit` a tus queries para no sobrecargar la respuesta.
- Los nombres de columna deben coincidir **exactamente** con los de tu tabla en Praxsuite (respeta mayúsculas y espacios).
- Para producción, usa `apiKeySecret` en vez de `apiKey` para guardar la clave en el Roblox Secrets Store.
