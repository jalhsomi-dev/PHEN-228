--[[
	SprintController (Client)

	Hold Left/Right Shift + move to sprint, draining stamina. Stamina
	regenerates after a short delay once you stop sprinting. Can't
	sprint again after hitting 0 until it's regenerated back up to
	GameConfig.Movement.MinStaminaToSprint (stops rapid tap-spamming).

	Includes a self-contained UI bar that:
	  - Auto-hides when stamina is full and you're not sprinting
	  - Fades in smoothly when it's needed
	  - Shifts color green -> yellow -> red as stamina drops
	  - Pulses red when critically low
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Movement = GameConfig.Movement

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}

local currentHumanoid = nil
local stamina = Movement.StaminaMax
local wantsToSprint = false
local isSprinting = false
local isExhausted = false
local regenCooldown = 0

-- ===== UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StaminaGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "StaminaContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -40)
container.Size = UDim2.new(0, 240, 0, 28)
container.BackgroundTransparency = 1
container.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "SprintLabel"
label.Size = UDim2.new(1, 0, 0, 14)
label.Position = UDim2.new(0, 0, 0, -2)
label.BackgroundTransparency = 1
label.Text = "STAMINA"
label.Font = Enum.Font.GothamBold
label.TextSize = 11
label.TextColor3 = Color3.fromRGB(220, 220, 220)
label.TextTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = container

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(1, 0, 0, 14)
barBackground.Position = UDim2.new(0, 0, 1, -14)
barBackground.BackgroundColor3 = Color3.fromRGB(20, 18, 18)
barBackground.BackgroundTransparency = 1
barBackground.BorderSizePixel = 0
barBackground.Parent = container

local bgCorner = Instance.new("UICorner")
bgCorner.CornerRadius = UDim.new(1, 0)
bgCorner.Parent = barBackground

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 0, 0)
stroke.Thickness = 1.5
stroke.Transparency = 1
stroke.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(120, 220, 120)
barFill.BackgroundTransparency = 1
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

local fillGradient = Instance.new("UIGradient")
fillGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(1, 0.6),
})
fillGradient.Rotation = 90
fillGradient.Parent = barFill

local lowStaminaTween = nil
local function setLowStaminaPulse(active)
	if active and not lowStaminaTween then
		lowStaminaTween = TweenService:Create(
			stroke,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0, Color = Color3.fromRGB(180, 30, 30) }
		)
		lowStaminaTween:Play()
	elseif not active and lowStaminaTween then
		lowStaminaTween:Cancel()
		lowStaminaTween = nil
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Transparency = 0.3
	end
end

local containerVisible = false
local function setContainerVisible(visible)
	if visible == containerVisible then
		return
	end
	containerVisible = visible
	local t = TweenInfo.new(0.25)
	TweenService:Create(barBackground, t, { BackgroundTransparency = visible and 0.25 or 1 }):Play()
	TweenService:Create(barFill, t, { BackgroundTransparency = visible and 0 or 1 }):Play()
	TweenService:Create(label, t, { TextTransparency = visible and 0.3 or 1 }):Play()
	if not visible then
		setLowStaminaPulse(false)
		stroke.Transparency = 1
	else
		stroke.Transparency = 0.3
	end
end

local function updateUI(fraction)
	barFill.Size = UDim2.new(fraction, 0, 1, 0)

	local color
	if fraction > 0.5 then
		color = Color3.fromRGB(120, 220, 120)
	elseif fraction > 0.2 then
		color = Color3.fromRGB(230, 200, 80)
	else
		color = Color3.fromRGB(210, 60, 60)
	end
	barFill.BackgroundColor3 = color

	local shouldShow = fraction < 0.999 or isSprinting
	setContainerVisible(shouldShow)
	if shouldShow then
		setLowStaminaPulse(fraction <= 0.2 and fraction > 0)
	end
end

-- ===== Sprint/stamina logic =====
local function onCharacterAdded(character)
	currentHumanoid = character:WaitForChild("Humanoid")
	currentHumanoid.WalkSpeed = Movement.WalkSpeed
	stamina = Movement.StaminaMax
	isSprinting = false
	isExhausted = false
	wantsToSprint = false
	regenCooldown = 0
	updateUI(1)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if SPRINT_KEYS[input.KeyCode] then
		wantsToSprint = true
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if SPRINT_KEYS[input.KeyCode] then
		wantsToSprint = false
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not currentHumanoid then
		return
	end

	local isMoving = currentHumanoid.MoveDirection.Magnitude > 0.05

	if stamina <= 0 then
		isExhausted = true
	elseif stamina >= Movement.StaminaMax then
		isExhausted = false
	end

	local canSprint = wantsToSprint and isMoving and stamina > 0 and not isExhausted

	if canSprint then
		isSprinting = true
		stamina = math.max(0, stamina - Movement.StaminaDrainRate * dt)
		regenCooldown = Movement.StaminaRegenDelay
	else
		isSprinting = false
		if regenCooldown > 0 then
			regenCooldown -= dt
		else
			stamina = math.min(Movement.StaminaMax, stamina + Movement.StaminaRegenRate * dt)
		end
	end

	currentHumanoid.WalkSpeed = isSprinting and Movement.SprintSpeed or Movement.WalkSpeed
	updateUI(stamina / Movement.StaminaMax)
end)