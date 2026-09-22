--[[
	PickupSystem (Server)

	Handles all key + crowbar pickups. Progress is SHARED across all
	players (co-op objective) rather than per-player, since this is a
	4-player survival game.

	Setup required in Studio:
	  - Tag each of your 5 key parts with "KeyPickup" (CollectionService)
	  - Tag your crowbar part with "CrowbarPickup"
	  - Each tagged part needs a ProximityPrompt child (ActionText = "Pick up")
	  - Parts can be anywhere in the maze; this script finds them by tag
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

-- Ensure Remotes folder + events exist (created at runtime so you don't
-- have to manually add them in Studio)
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemote(name)
	local remote = remotesFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end
	return remote
end

local itemCollectedRemote = getOrCreateRemote("ItemCollected") -- (itemType, keysCollected, requiredKeys, hasCrowbar)
local doorUnlockedRemote = getOrCreateRemote("DoorUnlocked")

-- Shared progress state
local state = {
	keysCollected = 0,
	hasCrowbar = false,
}

local doorUnlockEvent = Instance.new("BindableEvent")
doorUnlockEvent.Name = "DoorUnlockRequested"
doorUnlockEvent.Parent = script

local function checkWinCondition()
	if state.keysCollected >= GameConfig.RequiredKeys and state.hasCrowbar then
		doorUnlockEvent:Fire()
		doorUnlockedRemote:FireAllClients()
	end
end

local function collectKey(promptPart)
	state.keysCollected += 1
	promptPart:Destroy()
	itemCollectedRemote:FireAllClients("Key", state.keysCollected, GameConfig.RequiredKeys, state.hasCrowbar)
	checkWinCondition()
end

local function collectCrowbar(promptPart)
	if state.hasCrowbar then
		return
	end
	state.hasCrowbar = true
	promptPart:Destroy()
	itemCollectedRemote:FireAllClients("Crowbar", state.keysCollected, GameConfig.RequiredKeys, state.hasCrowbar)
	checkWinCondition()
end

local function setupPrompt(instance, onCollect)
	local prompt = instance:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		warn(("[PickupSystem] %s is tagged but has no ProximityPrompt child"):format(instance:GetFullName()))
		return
	end

	-- Studio defaults new ProximityPrompts to ClickablePrompt = true, which
	-- lets mouse hover/click trigger it too - that conflicts with a locked
	-- first-person camera (cursor unlocks and movement freezes while
	-- hovering). Force it off so only the keybind (E by default) works.
	prompt.ClickablePrompt = false

	local debounce = false
	prompt.Triggered:Connect(function(_player)
		if debounce then
			return
		end
		debounce = true
		onCollect(instance)
	end)
end

-- Wire up existing tagged instances
for _, instance in ipairs(CollectionService:GetTagged(GameConfig.Tags.KeyPickup)) do
	setupPrompt(instance, collectKey)
end
for _, instance in ipairs(CollectionService:GetTagged(GameConfig.Tags.CrowbarPickup)) do
	setupPrompt(instance, collectCrowbar)
end

-- Wire up any tagged instances added later (e.g. if you spawn pickups dynamically)
CollectionService:GetInstanceAddedSignal(GameConfig.Tags.KeyPickup):Connect(function(instance)
	setupPrompt(instance, collectKey)
end)
CollectionService:GetInstanceAddedSignal(GameConfig.Tags.CrowbarPickup):Connect(function(instance)
	setupPrompt(instance, collectCrowbar)
end)

print("[PickupSystem] Ready. Waiting for keys + crowbar...")