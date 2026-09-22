--[[
	BoiledOneAI (Server)

	Gives TheBoiledOne free-roam wandering across both floors of the
	maze. Spawns at the corner of the grid farthest from the player
	safe room. Plays a 3D positional sound only once a player gets
	close (quiet at the trigger range, getting louder as they approach,
	via Roblox's built-in distance falloff) rather than always playing.

	The model has no Humanoid (custom AnimationController rig), so
	movement is driven manually: PathfindingService computes waypoints,
	and we move the whole model along them via Model:PivotTo() each
	frame. This works regardless of the model's internal rigging, since
	PivotTo moves every part by the same rigid transform.
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
-- physics (gravity, players bumping into it, etc.)
for _, part in ipairs(model:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Anchored = true
	end
end

-- Moves the model so its feet land exactly on the given floor height,
-- at the given X/Z, preserving its current facing. Using the actual
-- lowest point of the mesh (not just half its height) since RootPart
-- usually isn't at the model's true vertical center - assuming it was
-- is what caused it to sink partway into the floor last time.
local function groundModelAt(x, z, floorY)
	local cf, size = model:GetBoundingBox()
	local currentLowestY = cf.Position.Y - size.Y / 2
	local currentPos = model:GetPivot().Position
	local horizontalOffset = Vector3.new(x - currentPos.X, 0, z - currentPos.Z)
	local verticalAdjust = floorY - currentLowestY
	model:PivotTo(model:GetPivot() + horizontalOffset + Vector3.new(0, verticalAdjust, 0))
end

-- ===== Spawn at the corner farthest from the player safe room =====
-- The safe room sits just outside maze cell (0,0), so the opposite
-- corner of the grid is the farthest starting point.
local farX = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
local farZ = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
groundModelAt(farX, farZ, EntityConfig.FloorYLevels[1])

-- ===== Proximity sound (trigger-based, not always playing) =====
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

local function moveAlongPath(waypoints)
	for _, waypoint in ipairs(waypoints) do
		local targetPos = waypoint.Position
		while (rootPart.Position - targetPos).Magnitude > 1.5 do
			local dt = RunService.Heartbeat:Wait()
			local currentPos = rootPart.Position
			local toTarget = targetPos - currentPos
			local moveDir = toTarget.Unit
			local step = moveDir * EntityConfig.MoveSpeed * dt

			local newPos
			if step.Magnitude >= toTarget.Magnitude then
				newPos = targetPos
			else
				newPos = currentPos + step
			end

			local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
			local lookCFrame
			if flatDir.Magnitude > 0.05 then
				lookCFrame = CFrame.new(newPos, newPos + flatDir)
			else
				lookCFrame = CFrame.new(newPos) * (rootPart.CFrame - rootPart.CFrame.Position)
			end

			model:PivotTo(lookCFrame)
		end
	end
end

while true do
	local destination = randomDestination()
	local path = PathfindingService:CreatePath(agentParams)

	local ok = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		moveAlongPath(waypoints)
	else
		task.wait(1) -- couldn't reach that spot, try another destination soon
	end

	task.wait(math.random(1, 3)) -- brief pause between destinations, feels less robotic
end

local function moveAlongPath(waypoints)
	for _, waypoint in ipairs(waypoints) do
		local targetPos = waypoint.Position
		while (rootPart.Position - targetPos).Magnitude > 1.5 do
			local dt = RunService.Heartbeat:Wait()
			local currentPos = rootPart.Position
			local toTarget = targetPos - currentPos
			local moveDir = toTarget.Unit
			local step = moveDir * EntityConfig.MoveSpeed * dt

			local newPos
			if step.Magnitude >= toTarget.Magnitude then
				newPos = targetPos
			else
				newPos = currentPos + step
			end

			local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
			local lookCFrame
			if flatDir.Magnitude > 0.05 then
				lookCFrame = CFrame.new(newPos, newPos + flatDir)
			else
				lookCFrame = CFrame.new(newPos) * (rootPart.CFrame - rootPart.CFrame.Position)
			end

			model:PivotTo(lookCFrame)
		end
	end
end

while true do
	local destination = randomDestination()
	local path = PathfindingService:CreatePath(agentParams)

	local ok = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		moveAlongPath(waypoints)
	else
		task.wait(1) -- couldn't reach that spot, try another destination soon
	end

	task.wait(math.random(1, 3)) -- brief pause between destinations, feels less robotic
end