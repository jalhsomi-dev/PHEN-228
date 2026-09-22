--[[
	FirstPersonCamera (Client)

	Locks the player's camera to first person for the whole game.
	Re-applies on every respawn since CameraMode can reset.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function applyFirstPerson()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
end

applyFirstPerson()
player.CharacterAdded:Connect(applyFirstPerson)