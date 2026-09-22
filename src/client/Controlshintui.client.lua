--[[
	ControlsHintUI (Client)

	Small persistent reminder of key controls, tucked in a corner.
	Add more lines here as you add more controls (interact key, etc.)
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONTROLS = {
	"SHIFT — Sprint",
	"F — Flashlight",
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ControlsHintGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "ControlsContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, 16, 1, -16)
container.Size = UDim2.new(0, 160, 0, #CONTROLS * 20 + 12)
container.BackgroundColor3 = Color3.fromRGB(15, 14, 14)
container.BackgroundTransparency = 0.4
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = container

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 2)
layout.Parent = container

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = container

for _, text in ipairs(CONTROLS) do
	local line = Instance.new("TextLabel")
	line.Size = UDim2.new(1, 0, 0, 18)
	line.BackgroundTransparency = 1
	line.Text = text
	line.Font = Enum.Font.Gotham
	line.TextSize = 13
	line.TextColor3 = Color3.fromRGB(225, 225, 225)
	line.TextTransparency = 0.15
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Parent = container
end