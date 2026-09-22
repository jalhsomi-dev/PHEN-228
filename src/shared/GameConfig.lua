--[[
	GameConfig
	Central place for tunable constants. Tag-based design means the map
	can be rebuilt/rearranged freely without touching scripts.
]]

local GameConfig = {}

GameConfig.RequiredKeys = 4 -- one per padlock
GameConfig.CodeLength = 4

-- CollectionService tags you'll apply to instances in Studio (the door
-- assembly itself gets built for you by ExitDoorBuilder, already tagged):
GameConfig.Tags = {
	KeyPickup = "KeyPickup",         -- apply to each of the 4 key parts you place in the maze
	CrowbarPickup = "CrowbarPickup", -- apply to the single crowbar part
	ExitDoor = "ExitDoor",           -- the actual door leaf that finally unlocks
	Padlock = "Padlock",             -- each of the 4 padlocks on the door
	DoorPlanks = "DoorPlanks",       -- the prompt for prying the nailed planks off
	Keypad = "Keypad",               -- the numeric keypad prompt
	CodeClue = "CodeClue",           -- part whose text gets set to the random code
	SafeZone = "SafeZone",           -- apply to a part covering the spawn room
}

GameConfig.Flashlight = {
	ToggleKey = Enum.KeyCode.F,
	Brightness = 0.6,
	Range = 30,
	Angle = 90,
	Color = Color3.fromRGB(255, 221, 130),
}

GameConfig.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	StaminaMax = 100,
	StaminaDrainRate = 25, -- per second while sprinting
	StaminaRegenRate = 15, -- per second while not sprinting
	StaminaRegenDelay = 1, -- seconds after releasing sprint before regen starts
}

GameConfig.Entity = {
	ModelName = "TheBoiledOne",
	MoveSpeed = 10, -- studs/sec while wandering
	AgentHeight = 9, -- matches its current scaled height
	AgentRadius = 2,
	GridSize = 13, -- matches the maze's GRID_WIDTH/GRID_HEIGHT
	CellSize = 12,
	FloorYLevels = { 0, 13 }, -- Y height of Floor0 and Floor1
	ProximitySoundId = "rbxassetid://137177653817621",
	ProximitySoundMinDistance = 12, -- full volume within this range
	ProximitySoundMaxDistance = 50, -- as quiet as it gets while still playing
	ProximityTriggerDistance = 50, -- sound starts playing once a player gets this close
	ProximityStopDistance = 60, -- sound stops once a player is this far (bigger than trigger, avoids rapid on/off flicker at the edge)
}

return GameConfig