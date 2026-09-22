--[[
	DoorController (Server)

	Listens for PickupSystem's win-condition event and unlocks the
	exit door(s). Tag your door part/model with "ExitDoor" in Studio.

	Unlock behavior here is intentionally simple (CanCollide off +
	sound). Swap in your own animation/sliding logic later if you want
	something fancier.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local pickupSystemScript = ServerScriptService:WaitForChild("PickupSystem")
local doorUnlockEvent = pickupSystemScript:WaitForChild("DoorUnlockRequested")

local function unlockDoor(doorInstance)
	-- Handle both a single Part and a Model containing parts
	local parts = {}
	if doorInstance:IsA("BasePart") then
		table.insert(parts, doorInstance)
	else
		for _, descendant in ipairs(doorInstance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	for _, part in ipairs(parts) do
		part.CanCollide = false
		part.Transparency = math.min(part.Transparency + 0.5, 1)
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://9125826338" -- placeholder unlock sound, swap for your own
	sound.Parent = doorInstance
	sound:Play()
	game.Debris:AddItem(sound, 5)
end

doorUnlockEvent.Event:Connect(function()
	for _, door in ipairs(CollectionService:GetTagged(GameConfig.Tags.ExitDoor)) do
		unlockDoor(door)
	end
	print("[DoorController] Exit door(s) unlocked!")
end)