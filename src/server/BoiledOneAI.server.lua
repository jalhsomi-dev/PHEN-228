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

-- Move along one path with deliberately unnatural, organic movement.
-- The Boiled One should NOT look like a normal Roblox NPC.
local function moveAlongPath(waypoints)
	for _, waypoint in ipairs(waypoints) do
		local targetPos = waypoint.Position
		local floorY = getFloorYForPosition(targetPos)
		local lastCheckPosition = rootPart.Position
		local checkTimer = 0
		local waypointStart = os.clock()

		-- Each waypoint gets a slightly different pace so the entity doesn't
		-- have the constant "AI motor" look.
		local pace = EntityConfig.MoveSpeed * math.random(85, 115) / 100

		while true do
			local dt = RunService.Heartbeat:Wait()
			local currentPos = rootPart.Position
			local flatToTarget = Vector3.new(
				targetPos.X - currentPos.X,
				0,
				targetPos.Z - currentPos.Z
			)
			local distance = flatToTarget.Magnitude

			if distance <= 1.35 then
				break
			end

			-- Slow slightly near corners, then accelerate again. This avoids
			-- perfectly constant velocity.
			local cornerFactor = math.clamp(distance / 5, 0.45, 1)
			local speed = pace * cornerFactor

			-- Subtle irregular lateral drift makes the body feel like it is
			-- being dragged rather than controlled by a humanoid.
			local side = Vector3.new(-flatToTarget.Z, 0, flatToTarget.X)
			if side.Magnitude > 0.01 then
				side = side.Unit
			end
			local drift = math.sin(os.clock() * 3.2) * 0.28
			local direction = (flatToTarget.Unit + side * drift * 0.18).Unit
			local step = math.min(speed * dt, distance)
			local newPos = currentPos + direction * step

			-- Occasional tiny freezes are intentional: the entity pauses for
			-- fractions of a second, then resumes suddenly.
			local t = os.clock() - waypointStart
			local freezeWave = math.sin(t * 0.43 + 1.7)
			if freezeWave > 0.997 then
				newPos = currentPos
			end

			local flatDir = flatToTarget.Magnitude > 0.05 and flatToTarget.Unit or rootPart.CFrame.LookVector
			local look = CFrame.lookAt(newPos, newPos + flatDir)

			-- Procedural tilt: tiny pitch/roll changes give the model a
			-- disturbing "wrong" posture without requiring an animation.
			local pitch = math.sin(t * 2.1) * math.rad(2.2)
			local roll = math.sin(t * 2.8 + 0.8) * math.rad(3.0)
			local yawJitter = math.sin(t * 4.7) * math.rad(1.2)
			look = look * CFrame.Angles(pitch, yawJitter, roll)
			model:PivotTo(look)

			-- Re-ground after the tilt. This is the important part: the
			-- lowest actual point of the model, not RootPart, determines the
			-- floor contact.
			local boxCFrame, boxSize = model:GetBoundingBox()
			local lowestY = boxCFrame.Position.Y - boxSize.Y / 2
			local correction = floorY - lowestY
			if math.abs(correction) > 0.001 then
				model:PivotTo(model:GetPivot() + Vector3.new(0, correction, 0))
			end

			-- Stuck detection. If the model barely changes position for a
			-- second, abandon the current path and let the main loop recalc.
			checkTimer += dt
			if checkTimer >= 1 then
				local moved = (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
					- Vector3.new(lastCheckPosition.X, 0, lastCheckPosition.Z)).Magnitude

				if moved < 0.2 then
					return false
				end

				lastCheckPosition = rootPart.Position
				checkTimer = 0
			end
		end

		-- A brief, irregular pause at some corners makes the wandering
		-- pattern less predictable.
		if math.random() < 0.28 then
			task.wait(math.random(8, 22) / 100)
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
