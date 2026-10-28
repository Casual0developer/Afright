local REQUIRED_PLACE_ID = 118827270815584

if game.PlaceId ~= REQUIRED_PLACE_ID then

    print(string.format("[Afright Scripts] Wrong game! Expected PlaceId %s; current PlaceId %s.", tostring(REQUIRED_PLACE_ID), tostring(game.PlaceId)))

    return

end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local destination = Vector3.new(5413.06, 8.54, -20686.59)
local autoWin = false
local autoWinSession = 0
local walkSpeed = 16
local jumpPower = 50
local flySpeed = 70
local noclip = false
local flying = false
local originalCollision = setmetatable({}, { __mode = "k" })
local noclipConnection
local flightConnection
local flightVelocity
local flightGyro
local flightHumanoid

local Window = Fluent:CreateWindow({
    Title = "Afright Scripts",
    SubTitle = "1.0.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 420),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift
})

local Main = Window:AddTab({ Title = "Main", Icon = "home" })
local Movement = Window:AddTab({ Title = "Movement", Icon = "person-standing" })

local function getCharacterParts()
    local character = player.Character
    if not character then
        return nil, nil, nil
    end
    return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

local function teleport()
    local _, _, root = getCharacterParts()
    if not root then
        return false
    end
    root.CFrame = CFrame.new(destination)
    return true
end

local function applyMovement()
    local _, humanoid = getCharacterParts()
    if humanoid then
        humanoid.WalkSpeed = walkSpeed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = jumpPower
    end
end

local function stopFlight()
    if flightConnection then
        flightConnection:Disconnect()
        flightConnection = nil
    end
    if flightVelocity then
        flightVelocity:Destroy()
        flightVelocity = nil
    end
    if flightGyro then
        flightGyro:Destroy()
        flightGyro = nil
    end
    if flightHumanoid and flightHumanoid.Parent then
        flightHumanoid.PlatformStand = false
    end
    flightHumanoid = nil
end

local function startFlight()
    stopFlight()
    if not flying then
        return
    end

    local _, humanoid, root = getCharacterParts()
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    flightHumanoid = humanoid
    humanoid.PlatformStand = true

    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "FluentFlightVelocity"
    velocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    velocity.P = 1e5
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    flightVelocity = velocity

    local gyro = Instance.new("BodyGyro")
    gyro.Name = "FluentFlightGyro"
    gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    gyro.P = 1e5
    gyro.D = 1000
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    flightGyro = gyro

    flightConnection = RunService.RenderStepped:Connect(function()
        if not flying or not root.Parent or humanoid.Health <= 0 then
            stopFlight()
            return
        end

        humanoid.PlatformStand = true
        local camera = workspace.CurrentCamera
        if not camera then
            velocity.Velocity = Vector3.zero
            return
        end

        local direction = Vector3.zero
        if not UserInputService:GetFocusedTextBox() then
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                direction = direction + camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                direction = direction - camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                direction = direction + camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                direction = direction - camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                direction = direction + Vector3.yAxis
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                direction = direction - Vector3.yAxis
            end
        end

        velocity.Velocity = direction.Magnitude > 0 and direction.Unit * flySpeed or Vector3.zero
        gyro.CFrame = camera.CFrame
    end)
end

local function setNoclip(enabled)
    noclip = enabled
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    if enabled then
        noclipConnection = RunService.Stepped:Connect(function()
            local character = player.Character
            if not character then
                return
            end
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    if originalCollision[part] == nil then
                        originalCollision[part] = true
                    end
                    part.CanCollide = false
                end
            end
        end)
    else
        for part, wasCollidable in pairs(originalCollision) do
            if part.Parent then
                part.CanCollide = wasCollidable
            end
            originalCollision[part] = nil
        end
    end
end

Main:AddButton({
    Title = "Win",
    Description = "Teleport to the win location",
    Callback = function()
        if not teleport() then
            Fluent:Notify({ Title = "Win", Content = "Character is not ready.", Duration = 3 })
        end
    end
})

Main:AddToggle("AutoWin", {
    Title = "Auto Win",
    Description = "Teleport to the win location every 0.5 seconds",
    Default = false,
    Callback = function(enabled)
        autoWin = enabled
        autoWinSession = autoWinSession + 1
        local session = autoWinSession
        if not enabled then
            return
        end
        task.spawn(function()
            while autoWin and autoWinSession == session and not Fluent.Unloaded do
                teleport()
                task.wait(0.5)
            end
        end)
    end
})

Movement:AddSlider("WalkSpeed", {
    Title = "Speed",
    Description = "Change your walking speed",
    Default = 16,
    Min = 0,
    Max = 250,
    Rounding = 0,
    Callback = function(value)
        walkSpeed = value
        applyMovement()
    end
})

Movement:AddToggle("Noclip", {
    Title = "Noclip",
    Description = "Walk through collidable parts",
    Default = false,
    Callback = setNoclip
})

Movement:AddToggle("Fly", {
    Title = "Fly",
    Description = "WASD to move, Space up, Left Ctrl down",
    Default = false,
    Callback = function(enabled)
        flying = enabled
        if enabled then
            startFlight()
        else
            stopFlight()
        end
    end
})

Movement:AddSlider("FlySpeed", {
    Title = "Fly Speed",
    Description = "Adjust flying movement speed",
    Default = 70,
    Min = 10,
    Max = 250,
    Rounding = 0,
    Callback = function(value)
        flySpeed = value
    end
})

Movement:AddSlider("JumpPower", {
    Title = "Jump Power",
    Description = "Change your jump strength",
    Default = 50,
    Min = 0,
    Max = 300,
    Rounding = 0,
    Callback = function(value)
        jumpPower = value
        applyMovement()
    end
})

player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if humanoid then
        applyMovement()
    end
    if root and flying then
        startFlight()
    end
end)

applyMovement()
Window:SelectTab(1)

task.spawn(function()
    while not Fluent.Unloaded do
        task.wait(0.25)
    end
    autoWin = false
    autoWinSession = autoWinSession + 1
    flying = false
    stopFlight()
    setNoclip(false)
end)