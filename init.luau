--!strict

local Replication = {}

-- // Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HTTPService = game:GetService("HttpService")

-- // Types
export type Config = {
	ID: ID,
	Mutable: boolean,
	Data: {},
	Targets: TargetPlayers?,
}

export type PlayerConfig = {
	ID: ID,
	Mutable: boolean,
	Data: {},
}

export type TargetPlayers = Player | { Player }

type PlayerSet = { [Player]: true }

type ReplicationObject = {
	Mutable: boolean,
	Data: {},
	Targets: PlayerSet?,
}

export type Connection = {
	disconnect: (Connection) -> (),
}

export type ID = string

-- // Constants
local REMOTE_NAME = "ReplicationEvent"

-- // Data
local ids: { [ID]: ID } = {}
local objects: { [ID]: ReplicationObject } = {}
local listeners: { [ID]: { [string]: { Connection } } } = {}
local remoteEvent: RemoteEvent? = nil

-- // Helpers
local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, inner in pairs(value) do
		result[key] = deepCopy(inner)
	end

	return result
end

local function splitPath(path: string): { string }
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end

	return parts
end

local function normalizeKey(part: string): string | number
	local numeric = tonumber(part)
	if numeric then
		return numeric
	end

	return part
end

local function setValueAtPath(root: {}, path: string, newValue: any): (any, any)
	local parts = splitPath(path)
	local current: any = root

	for index = 1, #parts - 1 do
		local key = normalizeKey(parts[index])
		local nextValue = current[key]

		if nextValue == nil or typeof(nextValue) ~= "table" then
			nextValue = {}
			current[key] = nextValue
		end

		current = nextValue
	end

	local leafKey = normalizeKey(parts[#parts])
	local oldValue = current[leafKey]
	current[leafKey] = newValue

	return newValue, oldValue
end

local function ensureRemote()
	if remoteEvent then
		return remoteEvent
	end

	if RunService:IsServer() then
		local found = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if found and found:IsA("RemoteEvent") then
			remoteEvent = found
		else
			local created = Instance.new("RemoteEvent")
			created.Name = REMOTE_NAME
			created.Parent = ReplicatedStorage
			remoteEvent = created
		end
	else
		remoteEvent = ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent
	end

	local event = remoteEvent
	assert(event ~= nil, "Replication: failed to initialize remote event.")
	return event
end

local function toPlayerSet(targets: TargetPlayers?): PlayerSet?
	if targets == nil then
		return nil
	end

	local result: PlayerSet = {}

	if typeof(targets) == "Instance" then
		assert(targets:IsA("Player"), "Replication: Targets must be a Player or an array of Players.")
		result[targets] = true
		return result
	end

	assert(type(targets) == "table", "Replication: Targets must be a Player or an array of Players.")
	for _, player in ipairs(targets :: { Player }) do
		assert(
			typeof(player) == "Instance" and player:IsA("Player"),
			"Replication: Every Targets entry must be a Player."
		)
		result[player] = true
	end

	return result
end

local function shouldReplicateToPlayer(object: ReplicationObject, player: Player): boolean
	local targets = object.Targets
	if not targets then
		return true
	end

	return targets[player] == true
end

local function fireInitToTargets(id: string, object: ReplicationObject)
	local event = ensureRemote()
	local targets = object.Targets

	if not targets then
		event:FireAllClients("init", id, object.Data, object.Mutable)
		return
	end

	for player in pairs(targets) do
		if player.Parent == Players then
			event:FireClient(player, "init", id, object.Data, object.Mutable)
		end
	end
end

local function fireSetToTargets(id: string, object: ReplicationObject, path: string, value: any)
	local event = ensureRemote()
	local targets = object.Targets

	if not targets then
		event:FireAllClients("set", id, path, value)
		return
	end

	for player in pairs(targets) do
		if player.Parent == Players then
			event:FireClient(player, "set", id, path, value)
		end
	end
end

local function fireListeners(id: string, path: string, newValue: any, oldValue: any)
	local byId = listeners[id]
	if not byId then
		return
	end

	local forPath = byId[path]
	if not forPath then
		return
	end

	local newSnapshot = deepCopy(newValue)
	local oldSnapshot = deepCopy(oldValue)

	for _, connection in ipairs(forPath) do
		if (connection :: any).connected then
			task.spawn((connection :: any).callback, newSnapshot, oldSnapshot)
		end
	end
end

-- // Connection wrapper
local Connection = {}
Connection.__index = Connection

function Connection.new(id: string, path: string, callback: (any, any?) -> ())
	local self = setmetatable({}, Connection)
	self.id = id
	self.path = path
	self.callback = callback
	self.connected = true

	return self :: any
end

function Connection:disconnect()
	if not (self :: any).connected then
		return
	end

	(self :: any).connected = false
	local byId = listeners[(self :: any).id]
	local forPath = byId and byId[(self :: any).path]

	if not forPath then
		return
	end

	for index = #forPath, 1, -1 do
		if forPath[index] == self then
			table.remove(forPath, index)
			break
		end
	end
end

-- // Client-side replication handler
if not RunService:IsServer() then
	local event = ensureRemote()
	local function handleInit(id: string, data: {}, mutable: boolean)
		objects[id] = {
			Mutable = mutable,
			Data = data,
		}
	end

	local function handleSet(id: string, path: string, value: any)
		local object = objects[id]
		if not object then
			object = {
				Mutable = false,
				Data = {},
			}
			objects[id] = object
		end

		local _, oldValue = setValueAtPath(object.Data, path, value)
		fireListeners(id, path, value, oldValue)
	end

	event.OnClientEvent:Connect(function(action: string, ...)
		if action == "init" then
			handleInit(...)
			return
		end

		if action == "set" then
			handleSet(...)
		end
	end)
else
	-- Ensure new players receive all existing replication objects.
	local event = ensureRemote()
	Players.PlayerAdded:Connect(function(player: Player)
		for id, object in pairs(objects) do
			if shouldReplicateToPlayer(object, player) then
				event:FireClient(player, "init", id, object.Data, object.Mutable)
			end
		end
	end)
end

-- // Public API
function Replication.ID(name: string): string
	assert(type(name) == "string" and name ~= "", "Replication: name must be a non-empty string.")
	if ids[name] then
		return ids[name]
	end

	local generated = string.format("Replication:%s", HTTPService:UrlEncode(name))
	ids[name] = generated

	return generated
end

function Replication.New(config: Config)
	assert(RunService:IsServer(), "Replication.New can only be called on the server.")
	assert(config, "Replication: config is required.")
	assert(type(config.ID) == "string" and config.ID ~= "", "Replication: ID must be a non-empty string.")
	assert(type(config.Data) == "table", "Replication: Data must be a table.")

	local object: ReplicationObject = {
		Mutable = config.Mutable == true,
		Data = config.Data,
		Targets = toPlayerSet(config.Targets),
	}

	objects[config.ID] = object
	fireInitToTargets(config.ID, object)

	return object
end

function Replication.NewForPlayer(player: Player, config: PlayerConfig)
	assert(RunService:IsServer(), "Replication.NewForPlayer can only be called on the server.")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Replication.NewForPlayer requires a Player.")
	assert(config, "Replication.NewForPlayer: config is required.")

	return Replication.New({
		ID = config.ID,
		Mutable = config.Mutable,
		Data = config.Data,
		Targets = player,
	})
end

function Replication:Set(id: string, path: string, value: any)
	assert(RunService:IsServer(), "Replication:Set can only be called on the server.")
	assert(type(id) == "string" and id ~= "", "Replication:Set requires a non-empty ID.")
	assert(type(path) == "string" and path ~= "", "Replication:Set requires a non-empty path string (e.g. 'Stats.XP').")

	local object = objects[id]
	assert(object, string.format("Replication:Set: No replication object found for ID '%s'.", id))
	assert(object.Mutable, string.format("Replication:Set: Object '%s' is not mutable.", id))

	local newValue, oldValue = setValueAtPath(object.Data, path, value)
	fireListeners(id, path, newValue, oldValue)
	fireSetToTargets(id, object, path, newValue)
end

function Replication:getData(id: string)
	assert(type(id) == "string" and id ~= "", "Replication:getData requires a non-empty ID.")
	local object = objects[id]
	assert(object, string.format("Replication:getData: No replication object found for ID '%s'.", id))

	return deepCopy(object.Data)
end

function Replication:onChanged(id: string, path: string, callback: (any, any?) -> ())
	assert(type(id) == "string" and id ~= "", "Replication:onChanged requires a non-empty ID.")
	assert(type(path) == "string" and path ~= "", "Replication:onChanged requires a non-empty path string.")
	assert(type(callback) == "function", "Replication:onChanged requires a callback function.")

	listeners[id] = listeners[id] or {}
	listeners[id][path] = listeners[id][path] or {}

	local connection = Connection.new(id, path, callback)
	table.insert(listeners[id][path], connection)

	return connection
end

function Replication.GetData(id: string)
	return Replication:getData(id)
end

function Replication.OnChanged(id: string, path: string, callback: (any, any?) -> ())
	return Replication:onChanged(id, path, callback)
end

return Replication
