--[[
	FlashlightController (Client)

	Press F to toggle a flashlight attached to the camera. Uses a
	SpotLight parented to a small invisible part welded to the head so
	the beam follows head movement in first person.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local player = Players.LocalPlayer

local flashlightOn = false
local currentRig = nil -- the invisible part + spotlight for the current character

local function destroyRig()
	if currentRig then
		currentRig:Destroy()
		currentRig = nil
	end
end

local function buildRig(character)
	local head = character:WaitForChild("Head")

	local mount = Instance.new("Part")
	mount.Name = "FlashlightMount"
	mount.Size = Vector3.new(0.1, 0.1, 0.1)
	mount.Transparency = 1
	mount.CanCollide = false
	mount.CanQuery = false
	mount.Massless = true
	mount.CFrame = head.CFrame
	mount.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = mount
	weld.Part1 = head
	weld.Parent = mount

	local spotLight = Instance.new("SpotLight")
	spotLight.Enabled = false
	spotLight.Brightness = GameConfig.Flashlight.Brightness
	spotLight.Range = GameConfig.Flashlight.Range
	spotLight.Angle = GameConfig.Flashlight.Angle
	spotLight.Color = GameConfig.Flashlight.Color
	spotLight.Face = Enum.NormalId.Front
	spotLight.Parent = mount

	currentRig = mount
	return spotLight
end

local function getSpotLight()
	if currentRig then
		return currentRig:FindFirstChildOfClass("SpotLight")
	end
	return nil
end

local function onCharacterAdded(character)
	destroyRig()
	flashlightOn = false
	buildRig(character)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == GameConfig.Flashlight.ToggleKey then
		flashlightOn = not flashlightOn
		local light = getSpotLight()
		if light then
			light.Enabled = flashlightOn
		end
	end
end)