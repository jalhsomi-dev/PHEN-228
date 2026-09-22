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

-- Keep the model grounded using its real bounding box. The correction is
-- calculated from the current pivot after rotation as well, so tilted
-- movement never pushes the feet below the floor.
local function groundModelAt(x, z, floorY)
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(x, pivot.Position.Y, z) * (pivot - pivot.Position))

	local boxCFrame, boxSize = model:GetBoundingBox()
	local lowestY = boxCFrame.Position.Y - boxSize.Y / 2
	local correction = floorY - lowestY

	model:PivotTo(model:GetPivot() + Vector3.new(0, correction, 0))
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

-- Move along one path.
-- IMPORTANT: this rig is not a humanoid. Its RootPart sits ~4.67 studs
-- above the floor while the visual body reaches the floor. We therefore
-- move the model horizontally without repeatedly re-grounding/tilting it.
-- Creepy motion should come from the Motor6Ds/animation layer, not from
-- physically pitching the entire model into the floor.
local function moveAlongPath(waypoints)
	for _, waypoint in ipairs(waypoints) do
		local targetPos = waypoint.Position
		local floorY = getFloorYForPosition(targetPos)
		local lastCheckPosition = rootPart.Position
		local checkTimer = 0
		local elapsed = 0

		-- Preserve the rig's real root-to-floor relationship. For this
		-- imported Boiled One rig, the root is above the visible bottom.
		local rootFloorOffset = rootPart.Position.Y - floorY
		if rootFloorOffset < 0.5 then
			rootFloorOffset = 4.67
		end

		local pace = EntityConfig.MoveSpeed * math.random(82, 112) / 100

		while true do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt

			local currentRoot = rootPart.Position
			local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
			local flatCurrent = Vector3.new(currentRoot.X, 0, currentRoot.Z)
			local toTarget = flatTarget - flatCurrent
			local distance = toTarget.Magnitude

			if distance <= 1.1 then
				break
			end

			local direction = toTarget.Unit

			-- Uneven acceleration/deceleration instead of a constant NPC speed.
			local speedWave = 0.88 + math.sin(elapsed * 1.7 + waypoint.Position.X) * 0.10
			local cornerFactor = math.clamp(distance / 4, 0.55, 1)
			local speed = pace * speedWave * cornerFactor

			-- Very subtle sideways wandering. This changes the path slightly
			-- without rotating/tilting the actual body into the floor.
			local side = Vector3.new(-direction.Z, 0, direction.X)
			local drift = math.sin(elapsed * 2.4 + waypoint.Position.Z) * 0.10
			local movementDirection = (direction + side * drift).Unit
			local step = math.min(speed * dt, distance)

			-- Rare micro-pauses make the entity feel less machine-perfect.
			local freeze = math.sin(elapsed * 0.37 + 2.1) > 0.999
			if not freeze then
				local newXZ = flatCurrent + movementDirection * step

				-- Keep the root at the correct height above whichever floor
				-- this waypoint belongs to.
				local newRootPosition = Vector3.new(
					newXZ.X,
					floorY + rootFloorOffset,
					newXZ.Z
				)

				-- Rotate only around the vertical axis. NO pitch/roll and NO
				-- bounding-box correction every frame, so the monster cannot
				-- be shoved through the floor by its tilted bounding box.
				local lookDirection = movementDirection
				local targetCFrame = CFrame.lookAt(newRootPosition, newRootPosition + lookDirection)
				model:PivotTo(targetCFrame)
			end

			checkTimer += dt
			if checkTimer >= 1 then
				local moved = (
					Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
					- Vector3.new(lastCheckPosition.X, 0, lastCheckPosition.Z)
				).Magnitude

				if moved < 0.2 then
					return false
				end

				lastCheckPosition = rootPart.Position
				checkTimer = 0
			end
		end

		-- Occasional longer pauses at waypoints.
		if math.random() < 0.24 then
			task.wait(math.random(10, 30) / 100)
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
