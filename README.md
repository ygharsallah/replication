# Replication

Simple server-authored state replication with path-based updates and client listeners.

## Installation

Add the package to your `wally.toml`:

```toml
[dependencies]
Replication = "ygharsallah/replication@VERSION"
```

Then require it from your project:

```lua
local Replication = require(game.ReplicatedStorage.Packages.Replication)
```

## API

## `Replication.ID(name: string) -> ID`

Creates a unique identifier used to reference a replication object. The same name on server and client resolves to the same object.

---

## `Replication.New(config: { ID: ID, Mutable: boolean, Data: table, Targets: Player | { Player }? }) -> { Mutable: boolean, Data: table }`

*(Server-only)* Creates a new replication object and replicates it to all clients, or only to `Targets` when provided.

| Field | Type | Description |
|---|---|---|
| `ID` | `ID` | The identifier returned by `Replication.ID()` |
| `Mutable` | `boolean` | Whether `Replication:Set()` can be called on this object |
| `Data` | `table` | Initial data to replicate. The passed table reference is stored directly |
| `Targets` | `Player \| { Player }?` | Optional audience. If omitted, replicates to all clients |

---

## `Replication.NewForPlayer(player: Player, config: { ID: ID, Mutable: boolean, Data: table }) -> { Mutable: boolean, Data: table }`

*(Server-only)* Convenience wrapper for single-player replication. Equivalent to calling `Replication.New()` with `Targets = player`.

---

## `Replication:Set(ID: string, path: string, value: any) -> void`

*(Server-only)* Updates a value at dot-notation `path` (e.g. `"Money"`, `"Stats.XP"`, `"Items.1"`) and replicates the change to the object's audience (`Targets` if configured, otherwise all clients). Requires `Mutable = true`.

---

## `Replication.GetData(ID: string) -> table`

Returns a deep-copied snapshot of the current replicated data for the given ID.

`Replication:getData(...)` is still supported as a backwards-compatible alias.

---

## `Replication.OnChanged(ID: string, path: string, callback: (new_value: any, old_value: any?) -> void) -> Connection`

Registers a listener that fires whenever that exact `path` is updated via `Replication:Set()`. Supports dot-notation for nested tables (e.g. `"Stats.XP"`).

`Replication:onChanged(...)` is still supported as a backwards-compatible alias.

**Callback parameters:**

| Parameter | Type | Description |
|---|---|---|
| `new_value` | `any` | The new value after the change |
| `old_value` | `any?` | The previous value, nil if this is the first update |

Both callback values are deep-copied snapshots.

Returns a `Connection` object.

---

## `Connection:disconnect() -> void`

Unregisters the listener returned by `Replication.OnChanged()`.

## Behavior Notes

- `Replication.New()` and `Replication:Set()` are server-only.
- `Replication.NewForPlayer()` is a convenience wrapper around `Replication.New(..., Targets = player)`.
- When `Targets` is passed to `Replication.New()`, only those players receive `init` and future `set` updates for that object.
- Mutating the original table passed to `Replication.New()` does not replicate by itself; call `Replication:Set()` to replicate and trigger listeners.
- `Replication.OnChanged()` listeners are keyed by exact path. Updating `"Stats.XP"` does not fire a listener registered on `"Stats"`.

## Basic example

### Server-side

``` lua
local Players = game:GetService("Players")
local Replication = require(game.ReplicatedStorage.Packages.Replication)

Players.PlayerAdded:Connect(function(player)
    local ID = Replication.ID(("PlayerData:%d"):format(player.UserId))

    local Data = {
        Money = 0,
        Invincible = true,
        Stats = {
            Level = 1,
            XP = 0,
        },
        Items = {
            "Sword",
            "Shield",
            "Potion",
        },
    }

    -- Only this player receives this object.
    Replication.NewForPlayer(player, {
        ID = ID,
        Mutable = true,
        Data = Data,
    })

    task.spawn(function()
        while player.Parent == Players do
            Replication:Set(ID, "Money", Data.Money + 100)
            Replication:Set(ID, "Stats.XP", Data.Stats.XP + 10)
            task.wait(1)
        end
    end)

    Replication:Set(ID, "Invincible", true)
end)
```

### Client-side

``` lua
local Players = game:GetService("Players")
local Replication = require(game.ReplicatedStorage.Packages.Replication)

local player = Players.LocalPlayer
local ID = Replication.ID(("PlayerData:%d"):format(player.UserId))

-- Fetch the current snapshot of the replicated data
local remoteData = Replication.GetData(ID)
local Money = remoteData.Money
local Stats = remoteData.Stats
local Items = remoteData.Items

-- Fires whenever Money changes, prints old and new value
local function printMoney(new_value, old_value)
    if old_value then
        print(`Money has changed from {old_value} to {new_value}!`)
        return
    end

    print(`Money has changed to {new_value}!`)
end

-- Fires whenever Stats.XP changes, prints old and new value
local function printXP(new_value, old_value)
    if old_value then
        print(`XP has changed from {old_value} to {new_value}!`)
        return
    end

    print(`XP has changed to {new_value}!`)
end

-- Fires whenever the Items array changes, prints the new item count
local function printItems(new_value, old_value)
    print(`Items updated! Now has {#new_value} items.`)
end

-- Register listeners and store the connections so they can be disconnected later
local moneyConnection = Replication.OnChanged(ID, "Money", printMoney)
local xpConnection    = Replication.OnChanged(ID, "Stats.XP", printXP)
local itemsConnection = Replication.OnChanged(ID, "Items", printItems)

-- Disconnect all listeners after 10 seconds
task.delay(10, function()
    moneyConnection:disconnect()
    xpConnection:disconnect()
    itemsConnection:disconnect()
end)
```
