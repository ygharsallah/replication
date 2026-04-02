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

## `Replication.New(config: { ID: ID, Mutable: boolean, Data: table }) -> { Mutable: boolean, Data: table }`

*(Server-only)* Creates a new replication object and replicates it to all clients.

| Field | Type | Description |
|---|---|---|
| `ID` | `ID` | The identifier returned by `Replication.ID()` |
| `Mutable` | `boolean` | Whether `Replication:Set()` can be called on this object |
| `Data` | `table` | Initial data to replicate. The passed table reference is stored directly |

---

## `Replication:Set(ID: string, path: string, value: any) -> void`

*(Server-only)* Updates a value at dot-notation `path` (e.g. `"Money"`, `"Stats.XP"`, `"Items.1"`) and replicates the change to all clients. Requires `Mutable = true`.

---

## `Replication:getData(ID: string) -> table`

Returns a deep-copied snapshot of the current replicated data for the given ID.

---

## `Replication:onChanged(ID: string, path: string, callback: (new_value: any, old_value: any?) -> void) -> Connection`

Registers a listener that fires whenever that exact `path` is updated via `Replication:Set()`. Supports dot-notation for nested tables (e.g. `"Stats.XP"`).

**Callback parameters:**

| Parameter | Type | Description |
|---|---|---|
| `new_value` | `any` | The new value after the change |
| `old_value` | `any?` | The previous value, nil if this is the first update |

Both callback values are deep-copied snapshots.

Returns a `Connection` object.

---

## `Connection:disconnect() -> void`

Unregisters the listener returned by `Replication:onChanged()`.

## Behavior Notes

- `Replication.New()` and `Replication:Set()` are server-only.
- Mutating the original table passed to `Replication.New()` does not replicate by itself; call `Replication:Set()` to replicate and trigger listeners.
- `Replication:onChanged()` listeners are keyed by exact path. Updating `"Stats.XP"` does not fire a listener registered on `"Stats"`.

## Basic example

### Server-side

``` lua
local Replication = require(game.ReplicatedStorage.Packages.Replication)

local ID = Replication.ID("GlobalData")

-- Define the initial data for this replication object
local Data = {
    Money = 0,
    Invincible = true,
    Stats = {         -- Nested table for player progression
        Level = 1,
        XP = 0,
    },
    Items = {         -- Array of items the player owns
        "Sword",
        "Shield",
        "Potion",
    },
}

-- Create the replication object, Mutable allows :Set() to be called on it
Replication.New({
    ID = ID,
    Mutable = true,
    Data = Data,
})

-- Every second, increment Money by 100 and XP by 10
task.spawn(function()
    while true do
        Replication:Set(ID, "Money", Data.Money + 100)
        Replication:Set(ID, "Stats.XP", Data.Stats.XP + 10)
        task.wait(1)
    end
end)

-- Immediately set Invincible to true on startup
Replication:Set(ID, "Invincible", true)
```

### Client-side

``` lua
local Replication = require(game.ReplicatedStorage.Packages.Replication)

local ID = Replication.ID("GlobalData")

-- Fetch the current snapshot of the replicated data
local remoteData = Replication:getData(ID)
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
local moneyConnection = Replication:onChanged(ID, "Money", printMoney)
local xpConnection    = Replication:onChanged(ID, "Stats.XP", printXP)
local itemsConnection = Replication:onChanged(ID, "Items", printItems)

-- Disconnect all listeners after 10 seconds
task.delay(10, function()
    moneyConnection:disconnect()
    xpConnection:disconnect()
    itemsConnection:disconnect()
end)
```
