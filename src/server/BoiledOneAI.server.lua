--[[
	BoiledOneAI (Server)

	Gives TheBoiledOne free-roam wandering across both floors of the
	maze. The model has no Humanoid, so movement is driven manually
	with PathfindingService + Model:PivotTo().

	Movement is grounded from the model's actual bounding box so the
	entity's feet stay on the floor instead of sinking through it.
	The controller also detects when the entity gets stuck and lets
	the main loop recalculate a fresh path.
]]

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local EntityConfig = GameConfig.Entity

local model = workspace:WaitForChild(EntityConfig.ModelName)
local rootPart = model.PrimaryPart or model:WaitForChild("RootPart")

-- Anchor everything so scripted movement is stable and isn't fought by
-- physics (gravity, players bumping into it, etc.).
for _, part in ipairs(model:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Anchored = true
	end
end

-- Return the lowest point of the model's current bounding box.
local function getLowestY()
	local cf, size = model:GetBoundingBox()
	return cf.Position.Y - size.Y / 2
end

-- Move the model to X/Z and then correct its Y position so the actual
-- bottom of the model sits exactly on the requested floor.
local function groundModelAt(x, z, floorY)
	local pivot = model:GetPivot()
	local horizontalOffset = Vector3.new(
		x - pivot.Position.X,
		0,
		z - pivot.Position.Z
	)

	model:PivotTo(pivot + horizontalOffset)

	local verticalAdjust = floorY - getLowestY()
	if math.abs(verticalAdjust) > 0.001 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, verticalAdjust, 0))
	end
end

-- Pick the maze floor represented by a path waypoint.
local function getFloorYForPosition(position)
	local closestFloor = EntityConfig.FloorYLevels[1]
	local closestDifference = math.abs(position.Y - closestFloor)

	for i = 2, #EntityConfig.FloorYLevels do
		local floorY = EntityConfig.FloorYLevels[i]
		local difference = math.abs(position.Y - floorY)

		if difference < closestDifference then
			closestFloor = floorY
			closestDifference = difference
		end
	end

	return closestFloor
end

-- ===== Spawn at the corner farthest from the player safe room =====
local farX = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
local farZ = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2

groundModelAt(farX, farZ, EntityConfig.FloorYLevels[1])

-- ===== Proximity sound =====
local sound = rootPart:FindFirstChild("ProximitySound")

if not sound then
	sound = Instance.new("Sound")
	sound.Name = "ProximitySound"
	sound.Parent = rootPart
end

sound.SoundId = EntityConfig.ProximitySoundId
sound.Looped = true
sound.RollOffMode = Enum.RollOffMode.InverseTapered
sound.RollOffMinDistance = EntityConfig.ProximitySoundMinDistance
sound.RollOffMaxDistance = EntityConfig.ProximitySoundMaxDistance
sound.Volume = 1
sound.Playing = false

local function nearestPlayerDistance()
	local closest = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		if hrp then
			local dist = (hrp.Position - rootPart.Position).Magnitude

			if dist < closest then
				closest = dist
			end
		end
	end

	return closest
end

task.spawn(function()
	while true do
		local dist = nearestPlayerDistance()

		if not sound.IsPlaying and dist <= EntityConfig.ProximityTriggerDistance then
			sound:Play()
		elseif sound.IsPlaying and dist >= EntityConfig.ProximityStopDistance then
			sound:Stop()
		end

		task.wait(0.3)
	end
end)

-- ===== Free-roam wandering =====
local agentParams = {
	AgentHeight = EntityConfig.AgentHeight,
	AgentRadius = EntityConfig.AgentRadius,
	AgentCanJump = false,
	AgentCanClimb = true,
	WaypointSpacing = 4,
}

local function randomDestination()
	local x = math.random(0, EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
	local z = math.random(0, EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
	local floorY = EntityConfig.FloorYLevels[math.random(1, #EntityConfig.FloorYLevels)]

	return Vector3.new(x, floorY + 2, z)
end

-- Move along one path. Returns false if the entity appears stuck.
local function moveAlongPath(waypoints)
	for _, waypoint in ipairs(waypoints) do
		local targetPos = waypoint.Position
		local floorY = getFloorYForPosition(targetPos)
		local waypointReached = false
		local lastCheckPosition = rootPart.Position
		local timeSinceMovementCheck = 0

		while not waypointReached do
			local dt = RunService.Heartbeat:Wait()

			local currentPos = rootPart.Position
			local toTarget = targetPos - currentPos
			local distance = toTarget.Magnitude

			if distance <= 1.5 then
				waypointReached = true
				break
			end

			local moveDir = toTarget.Unit
			local stepDistance = math.min(EntityConfig.MoveSpeed * dt, distance)
			local newPos = currentPos + moveDir * stepDistance

			-- Only use the waypoint for direction. The entity itself is
			-- always grounded from its real bounding box.
			local flatDir = Vector3.new(
				targetPos.X - currentPos.X,
				0,
				targetPos.Z - currentPos.Z
			)

			local lookCFrame

			if flatDir.Magnitude > 0.05 then
				lookCFrame = CFrame.new(newPos, newPos + flatDir)
			else
				lookCFrame = CFrame.new(newPos) * (rootPart.CFrame - rootPart.CFrame.Position)
			end

			model:PivotTo(lookCFrame)

			-- Correct the vertical position after every movement step.
			-- This prevents the model from gradually ending up inside
			-- the floor because of its pivot/bounding-box offset.
			local verticalAdjust = floorY - getLowestY()

			if math.abs(verticalAdjust) > 0.001 then
				model:PivotTo(model:GetPivot() + Vector3.new(0, verticalAdjust, 0))
			end

			-- Stuck detection: if almost no horizontal movement happened
			-- for a full second, abandon this path and recalculate.
			timeSinceMovementCheck += dt

			if timeSinceMovementCheck >= 1 then
				local movementSinceCheck = (
					Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
					- Vector3.new(lastCheckPosition.X, 0, lastCheckPosition.Z)
				).Magnitude

				if movementSinceCheck < 0.25 then
					return false
				end

				lastCheckPosition = rootPart.Position
				timeSinceMovementCheck = 0
			end
		end
	end

	return true
end

-- ===== Main AI loop =====
while true do
	local destination = randomDestination()
	local path = PathfindingService:CreatePath(agentParams)

	local ok = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()

		if #waypoints > 0 then
			moveAlongPath(waypoints)
		end
	else
		task.wait(0.5)
	end

	-- Short pause makes the wandering feel less robotic.
	task.wait(math.random(1, 3))
end
