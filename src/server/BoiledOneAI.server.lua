--[[
    PHEN-228 - The Boiled One AI
    Server controller for the custom AnimationController/Motor6D entity.

    Design:
    - RootPart is the only part used for navigation.
    - The imported rig's pivot is exactly its RootPart.
    - The visible model reaches the floor while RootPart sits ~4.67 studs above it.
    - No bounding-box grounding is performed during movement.
    - Pathfinding handles maze navigation.
    - Movement is deliberately imperfect and unsettling.
    - Motor6D animation is kept separate from navigation.
]]

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local EntityConfig = GameConfig.Entity

local model = workspace:WaitForChild(EntityConfig.ModelName)
local rootPart = model:WaitForChild("RootPart")

model.PrimaryPart = rootPart

-- ============================================================
-- RIG SETUP
-- ============================================================

-- This imported rig is manually moved, so physics must not fight us.
for _, object in ipairs(model:GetDescendants()) do
    if object:IsA("BasePart") then
        object.Anchored = true
        object.CanTouch = false
    end
end

-- Capture the rig's intended root height above its floor.
-- Measurements from the imported asset show:
-- RootPart Y ~= 4.671 when the visible bottom is at floor Y=0.
local function getRootFloorOffset(floorY)
    return rootPart.Position.Y - floorY
end

local rootFloorOffset = getRootFloorOffset(EntityConfig.FloorYLevels[1])

if rootFloorOffset < 0.5 then
    rootFloorOffset = 4.671
end

-- ============================================================
-- FLOOR HELPERS
-- ============================================================

local function nearestFloorY(y)
    local best = EntityConfig.FloorYLevels[1]
    local bestDistance = math.abs(y - best)

    for i = 2, #EntityConfig.FloorYLevels do
        local floorY = EntityConfig.FloorYLevels[i]
        local distance = math.abs(y - floorY)

        if distance < bestDistance then
            best = floorY
            bestDistance = distance
        end
    end

    return best
end

local function rootHeightForFloor(floorY)
    return floorY + rootFloorOffset
end

-- ============================================================
-- SPAWN
-- ============================================================

local function placeAt(x, z, floorY, faceDirection)
    local position = Vector3.new(x, rootHeightForFloor(floorY), z)

    local direction = faceDirection
    if not direction or direction.Magnitude < 0.001 then
        direction = Vector3.new(0, 0, -1)
    end

    direction = Vector3.new(direction.X, 0, direction.Z).Unit

    model:PivotTo(CFrame.lookAt(position, position + direction))
end

local farX = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2
local farZ = (EntityConfig.GridSize - 1) * EntityConfig.CellSize + EntityConfig.CellSize / 2

placeAt(farX, farZ, EntityConfig.FloorYLevels[1], Vector3.new(-1, 0, -1))

-- ============================================================
-- PROXIMITY AUDIO
-- ============================================================

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
    local nearest = math.huge
    local entityPosition = rootPart.Position

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")

        if playerRoot then
            local distance = (playerRoot.Position - entityPosition).Magnitude

            if distance < nearest then
                nearest = distance
            end
        end
    end

    return nearest
end

task.spawn(function()
    while model.Parent do
        local distance = nearestPlayerDistance()

        if distance <= EntityConfig.ProximityTriggerDistance then
            if not sound.IsPlaying then
                sound:Play()
            end
        elseif distance >= EntityConfig.ProximityStopDistance then
            if sound.IsPlaying then
                sound:Stop()
            end
        end

        task.wait(0.2)
    end
end)

-- ============================================================
-- PATHFINDING
-- ============================================================

local agentParams = {
    AgentHeight = EntityConfig.AgentHeight,
    AgentRadius = EntityConfig.AgentRadius,
    AgentCanJump = false,
    AgentCanClimb = true,
    WaypointSpacing = 4,
}

local function randomDestination()
    local x = math.random(0, EntityConfig.GridSize - 1) * EntityConfig.CellSize
        + EntityConfig.CellSize / 2

    local z = math.random(0, EntityConfig.GridSize - 1) * EntityConfig.CellSize
        + EntityConfig.CellSize / 2

    local floorY = EntityConfig.FloorYLevels[
        math.random(1, #EntityConfig.FloorYLevels)
    ]

    return Vector3.new(x, floorY + 1, z)
end

local function computePath(destination)
    local path = PathfindingService:CreatePath(agentParams)

    local success = pcall(function()
        path:ComputeAsync(rootPart.Position, destination)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        return nil
    end

    local waypoints = path:GetWaypoints()

    if #waypoints < 2 then
        return nil
    end

    return path, waypoints
end

-- ============================================================
-- UNSETTLING MOVEMENT
-- ============================================================

local function moveToWaypoint(targetPosition, floorY)
    local startPosition = rootPart.Position

    local targetXZ = Vector3.new(targetPosition.X, 0, targetPosition.Z)
    local currentXZ = Vector3.new(startPosition.X, 0, startPosition.Z)

    local initialDistance = (targetXZ - currentXZ).Magnitude

    if initialDistance < 0.75 then
        return true
    end

    local travelTime = 0
    local stuckTime = 0
    local lastPosition = rootPart.Position

    -- Every waypoint gets its own personality.
    local baseSpeed = EntityConfig.MoveSpeed * math.random(88, 108) / 100
    local swayStrength = math.random(2, 7) / 100
    local swayFrequency = math.random(14, 25) / 10
    local phase = math.random() * math.pi * 2

    -- The entity occasionally has a moment where it seems to hesitate.
    local hesitation = math.random() < 0.18
    local hesitationTime = math.random(8, 20) / 100
    local hesitationAt = math.random(25, 70) / 100

    while model.Parent do
        local dt = RunService.Heartbeat:Wait()
        travelTime += dt

        local currentRoot = rootPart.Position
        currentXZ = Vector3.new(currentRoot.X, 0, currentRoot.Z)

        local offset = targetXZ - currentXZ
        local distance = offset.Magnitude

        if distance <= 0.85 then
            return true
        end

        local direction = offset.Unit
        local side = Vector3.new(-direction.Z, 0, direction.X)

        -- Organic-looking lateral drift.
        local sway = math.sin(travelTime * swayFrequency + phase) * swayStrength

        -- Speed breathes instead of remaining perfectly constant.
        local speedPulse = 0.94 + math.sin(travelTime * 1.9 + phase) * 0.08

        -- Slow down naturally as the entity reaches a corner.
        local cornerSlowdown = math.clamp(distance / 3.5, 0.55, 1)

        local speed = baseSpeed * speedPulse * cornerSlowdown

        -- Brief hesitation. It stops without snapping into a robotic idle.
        local hesitating = hesitation
            and travelTime >= hesitationAt
            and travelTime <= hesitationAt + hesitationTime

        if not hesitating then
            local movement = (direction + side * sway).Unit
            local step = math.min(speed * dt, distance)

            local nextXZ = currentXZ + movement * step

            -- Keep RootPart at the correct height for the floor.
            local nextPosition = Vector3.new(
                nextXZ.X,
                rootHeightForFloor(floorY),
                nextXZ.Z
            )

            -- Rotate only around Y. The body itself will later be animated
            -- through its Motor6Ds rather than pitching the whole rig.
            local facing = movement

            -- A tiny, slow directional imperfection prevents perfect NPC turns.
            local yawOffset = math.sin(travelTime * 2.1 + phase) * 0.035
            local facingCF = CFrame.lookAt(
                nextPosition,
                nextPosition + facing
            ) * CFrame.Angles(0, yawOffset, 0)

            model:PivotTo(facingCF)
        end

        -- Stuck detection.
        stuckTime += dt

        if stuckTime >= 0.75 then
            local moved = (
                Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
                - Vector3.new(lastPosition.X, 0, lastPosition.Z)
            ).Magnitude

            if moved < 0.12 and not hesitating then
                return false
            end

            lastPosition = rootPart.Position
            stuckTime = 0
        end
    end

    return false
end

local function followPath(waypoints)
    for index = 2, #waypoints do
        local waypoint = waypoints[index]
        local floorY = nearestFloorY(waypoint.Position.Y)

        local reached = moveToWaypoint(waypoint.Position, floorY)

        if not reached then
            return false
        end

        -- Unpredictable micro-pauses at some corners.
        if index < #waypoints and math.random() < 0.12 then
            task.wait(math.random(5, 18) / 100)
        end
    end

    return true
end

-- ============================================================
-- MAIN WANDER LOOP
-- ============================================================

while model.Parent do
    local destination = randomDestination()
    local path, waypoints = computePath(destination)

    if path and waypoints then
        local blocked = false
        local connection

        connection = path.Blocked:Connect(function(blockedWaypoint)
            if blockedWaypoint >= 2 then
                blocked = true
            end
        end)

        if not blocked then
            followPath(waypoints)
        end

        if connection then
            connection:Disconnect()
        end
    end

    -- Not every decision happens immediately. The small delay makes
    -- wandering feel intentional rather than like a pathfinding loop.
    task.wait(math.random(20, 60) / 100)
end
