local REQUIRED_PLACE_ID = 105527962898452

if game.PlaceId ~= REQUIRED_PLACE_ID then

    print(string.format("[Afright Scripts] Wrong game! Expected PlaceId %s; current PlaceId %s.", tostring(REQUIRED_PLACE_ID), tostring(game.PlaceId)))

    return

end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Global = (getgenv and getgenv()) or _G

if Global.FluentCombatVisuals and Global.FluentCombatVisuals.Stop then
    pcall(function()
        Global.FluentCombatVisuals:Stop()
    end)
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Settings = {
    HitboxEnabled = false,
    HitboxSize = 10,
    HitboxVisual = "3D",
    AimbotEnabled = false,
    AimRadius = 250,
    ESPEnabled = false,
    ESPMode = "2D",
    ESPInfo = true
}

local Controller = {Alive = true, Connections = {}, Library = Fluent}
local Hitboxes = {}
local Visuals = {}
local CurrentTarget = nil
local AimElapsed = 0
local RenderName = "FluentCombatVisualsRender_" .. tostring(LocalPlayer.UserId)
local EnemyColor = Color3.fromRGB(255, 65, 65)
local OutlineColor = Color3.fromRGB(255, 80, 80)

local Overlay = Instance.new("ScreenGui")
Overlay.Name = "FluentCombatVisualsOverlay"
Overlay.IgnoreGuiInset = true
Overlay.ResetOnSpawn = false
Overlay.DisplayOrder = 9999
Overlay.ZIndexBehavior = Enum.ZIndexBehavior.Global
Overlay.Parent = PlayerGui

local function destroy(instance)
    if instance then
        pcall(function()
            instance:Destroy()
        end)
    end
end

local function isEnemy(player)
    return player ~= LocalPlayer
        and player.Team ~= nil
        and player.Team.Name ~= "Lobby"
        and player.Team ~= LocalPlayer.Team
end

local function getLivingCharacter(player)
    local character = player.Character
    if not character then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not humanoid or humanoid.Health <= 0 then
        return nil
    end
    if not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
        return nil
    end
    return character, humanoid, root, head
end

local function restoreHitbox(player)
    local record = Hitboxes[player]
    if not record then
        return
    end
    Hitboxes[player] = nil
    if record.Head and record.Head.Parent then
        pcall(function()
            record.Head.Size = record.Size
            record.Head.CanCollide = record.CanCollide
            record.Head.Massless = record.Massless
        end)
    end
    if record.Neck and record.Neck.Parent and record.C1 then
        pcall(function()
            record.Neck.C1 = record.C1
        end)
    end
end

local function restoreAllHitboxes()
    local players = {}
    for player in pairs(Hitboxes) do
        players[#players + 1] = player
    end
    for _, player in ipairs(players) do
        restoreHitbox(player)
    end
end

local function updateHitbox(player)
    if not Settings.HitboxEnabled or not isEnemy(player) then
        restoreHitbox(player)
        return
    end

    local character, _, _, head = getLivingCharacter(player)
    if not head then
        restoreHitbox(player)
        return
    end

    local record = Hitboxes[player]
    if record and record.Head ~= head then
        restoreHitbox(player)
        record = nil
    end

    if not record then
        local neck = character:FindFirstChild("Neck", true)
        if neck and not neck:IsA("Motor6D") then
            neck = nil
        end
        record = {
            Head = head,
            Size = head.Size,
            CanCollide = head.CanCollide,
            Massless = head.Massless,
            Neck = neck,
            C1 = neck and neck.C1 or nil
        }
        Hitboxes[player] = record
    end

    local size = Settings.HitboxSize
    local newSize = Vector3.new(size, size, size)
    if head.Size ~= newSize then
        head.Size = newSize
    end
    if head.CanCollide then
        head.CanCollide = false
    end
    if not head.Massless then
        head.Massless = true
    end
    if record.Neck and record.Neck.Parent and record.C1 then
        local yOffset = (size - record.Size.Y) / 2
        local newC1 = record.C1 * CFrame.new(0, -yOffset, 0)
        if record.Neck.C1 ~= newC1 then
            record.Neck.C1 = newC1
        end
    end
end

local function new2DBox(name, thickness)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.ZIndex = 4
    frame.Parent = Overlay

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = thickness
    stroke.Color = EnemyColor
    stroke.Parent = frame

    return frame, stroke
end

local function newVisualRecord(player)
    local record = Visuals[player]
    if record then
        return record
    end

    local esp2D, espStroke = new2DBox("ESP2D_" .. player.UserId, 1.6)
    local hit2D, hitStroke = new2DBox("Hitbox2D_" .. player.UserId, 2)
    hitStroke.Color = OutlineColor

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.BorderSizePixel = 0
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 0, -3)
    nameLabel.Size = UDim2.fromOffset(200, 19)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0.35
    nameLabel.ZIndex = 5
    nameLabel.Parent = esp2D

    local infoLabel = Instance.new("TextLabel")
    infoLabel.BackgroundTransparency = 1
    infoLabel.BorderSizePixel = 0
    infoLabel.AnchorPoint = Vector2.new(0.5, 0)
    infoLabel.Position = UDim2.new(0.5, 0, 1, 3)
    infoLabel.Size = UDim2.fromOffset(200, 17)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 12
    infoLabel.TextColor3 = Color3.new(1, 1, 1)
    infoLabel.TextStrokeTransparency = 0.35
    infoLabel.ZIndex = 5
    infoLabel.Parent = esp2D

    local esp3D = Instance.new("BoxHandleAdornment")
    esp3D.Name = "ESP3D_" .. player.UserId
    esp3D.AlwaysOnTop = true
    esp3D.Size = Vector3.new(4, 6, 3)
    esp3D.Transparency = 0.8
    esp3D.ZIndex = 2
    esp3D.Color3 = EnemyColor
    esp3D.Visible = false
    esp3D.Parent = PlayerGui

    local hit3D = Instance.new("SelectionBox")
    hit3D.Name = "Hitbox3D_" .. player.UserId
    hit3D.LineThickness = 0.055
    hit3D.SurfaceTransparency = 0.94
    hit3D.Color3 = OutlineColor
    hit3D.SurfaceColor3 = OutlineColor
    hit3D.Visible = false
    hit3D.Parent = PlayerGui

    record = {
        ESP2D = esp2D,
        ESP3D = esp3D,
        Hit2D = hit2D,
        Hit3D = hit3D,
        NameLabel = nameLabel,
        InfoLabel = infoLabel,
        Character = nil
    }
    Visuals[player] = record
    return record
end

local function removeVisualRecord(player)
    local record = Visuals[player]
    if not record then
        return
    end
    Visuals[player] = nil
    destroy(record.ESP2D)
    destroy(record.ESP3D)
    destroy(record.Hit2D)
    destroy(record.Hit3D)
end

local function hideVisualRecord(record)
    record.ESP2D.Visible = false
    record.ESP3D.Visible = false
    record.Hit2D.Visible = false
    record.Hit3D.Visible = false
end

local function projectBox(camera, boxCFrame, boxSize)
    local half = boxSize * 0.5
    local left, right = math.huge, -math.huge
    local top, bottom = math.huge, -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local point = camera:WorldToViewportPoint(boxCFrame:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z)))
                if point.Z <= 0.1 then
                    return nil
                end
                left = math.min(left, point.X)
                right = math.max(right, point.X)
                top = math.min(top, point.Y)
                bottom = math.max(bottom, point.Y)
            end
        end
    end

    local viewport = camera.ViewportSize
    if right < 0 or left > viewport.X or bottom < 0 or top > viewport.Y then
        return nil
    end

    left = math.max(left, 0)
    top = math.max(top, 0)
    right = math.min(right, viewport.X)
    bottom = math.min(bottom, viewport.Y)
    if right - left < 2 or bottom - top < 2 then
        return nil
    end

    return UDim2.fromOffset(left, top), UDim2.fromOffset(right - left, bottom - top)
end

local function draw2D(frame, camera, boxCFrame, boxSize)
    local position, size = projectBox(camera, boxCFrame, boxSize)
    if not position then
        frame.Visible = false
        return
    end
    frame.Position = position
    frame.Size = size
    frame.Visible = true
end

local function renderPlayer(player, camera)
    local record = Visuals[player]
    local needsESP = Settings.ESPEnabled
    local needsHitboxVisual = Settings.HitboxEnabled and Settings.HitboxVisual ~= "Off"
    if not isEnemy(player) or (not needsESP and not needsHitboxVisual) then
        if record then
            hideVisualRecord(record)
        end
        return
    end

    local character, humanoid, root, head = getLivingCharacter(player)
    if not character or (camera.CFrame.Position - root.Position).Magnitude > 1500 then
        if record then
            hideVisualRecord(record)
        end
        return
    end

    record = record or newVisualRecord(player)
    if record.Character ~= character then
        record.Character = character
        record.ESP3D.Adornee = root
        record.Hit3D.Adornee = head
    end

    if needsESP then
        if Settings.ESPMode == "2D" then
            draw2D(record.ESP2D, camera, root.CFrame, Vector3.new(4, 6, 3))
            record.ESP3D.Visible = false
            record.NameLabel.Visible = Settings.ESPInfo
            record.InfoLabel.Visible = Settings.ESPInfo
            if Settings.ESPInfo and record.ESP2D.Visible then
                local health = math.ceil(humanoid.Health)
                local distance = math.floor((camera.CFrame.Position - root.Position).Magnitude)
                record.NameLabel.Text = player.DisplayName
                record.InfoLabel.Text = health .. " HP  |  " .. distance .. " studs"
            end
        else
            record.ESP2D.Visible = false
            record.ESP3D.Adornee = root
            record.ESP3D.Visible = true
        end
    else
        record.ESP2D.Visible = false
        record.ESP3D.Visible = false
    end

    if needsHitboxVisual and Hitboxes[player] and Hitboxes[player].Head == head then
        if Settings.HitboxVisual == "2D" then
            draw2D(record.Hit2D, camera, head.CFrame, head.Size)
            record.Hit3D.Visible = false
        else
            record.Hit2D.Visible = false
            record.Hit3D.Adornee = head
            record.Hit3D.Visible = true
        end
    else
        record.Hit2D.Visible = false
        record.Hit3D.Visible = false
    end
end

local function hasLineOfSight(camera, character, point)
    local origin = camera.CFrame.Position
    local direction = point - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LocalPlayer.Character and {LocalPlayer.Character} or {}
    params.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, params)
    return not result or result.Instance:IsDescendantOf(character)
end

local function canAimAt(player, camera)
    if not player or not isEnemy(player) then
        return nil
    end
    local character, _, _, head = getLivingCharacter(player)
    if not character then
        return nil
    end
    local point, onScreen = camera:WorldToViewportPoint(head.Position)
    if not onScreen or point.Z <= 0 then
        return nil
    end
    local viewport = camera.ViewportSize
    local offset = Vector2.new(point.X - viewport.X / 2, point.Y - viewport.Y / 2)
    local radius = offset.Magnitude
    if radius > Settings.AimRadius then
        return nil
    end
    if not hasLineOfSight(camera, character, head.Position) then
        return nil
    end
    return head, radius
end

local function selectAimTarget(camera)
    local oldHead, oldDistance = canAimAt(CurrentTarget, camera)
    local bestPlayer = oldHead and CurrentTarget or nil
    local bestDistance = oldHead and oldDistance * 0.7 or Settings.AimRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= CurrentTarget then
            local head, distance = canAimAt(player, camera)
            if head and distance < bestDistance then
                bestPlayer = player
                bestDistance = distance
            end
        end
    end

    CurrentTarget = bestPlayer
end

local function updateAim(camera, dt)
    if not Settings.AimbotEnabled then
        CurrentTarget = nil
        AimElapsed = 0
        return
    end

    AimElapsed += dt
    if AimElapsed >= 0.12 then
        AimElapsed = 0
        selectAimTarget(camera)
    end

    local head = CurrentTarget and select(4, getLivingCharacter(CurrentTarget))
    if not head or not isEnemy(CurrentTarget) then
        CurrentTarget = nil
        return
    end

    local position = camera.CFrame.Position
    local direction = head.Position - position
    if direction.Magnitude > 0.01 then
        local desired = CFrame.lookAt(position, head.Position)
        local blend = math.clamp(1 - math.exp(-18 * math.min(dt, 0.1)), 0, 1)
        camera.CFrame = camera.CFrame:Lerp(desired, blend)
    end
end

function Controller:Stop()
    if not self.Alive then
        return
    end
    self.Alive = false
    RunService:UnbindFromRenderStep(RenderName)
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    restoreAllHitboxes()
    for player in pairs(Visuals) do
        removeVisualRecord(player)
    end
    destroy(Overlay)
    CurrentTarget = nil
    if Global.FluentCombatVisuals == self then
        Global.FluentCombatVisuals = nil
    end
    if self.Library and not self.Library.Unloaded then
        pcall(function()
            if self.Library.Unload then
                self.Library:Unload()
            elseif self.Library.Destroy then
                self.Library:Destroy()
            end
        end)
    end
end

Global.FluentCombatVisuals = Controller

local Window = Fluent:CreateWindow({
    Title = "Afright Scripts",
    SubTitle = "1.0.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 420),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift
})

local titleBar = Window.TitleBar and Window.TitleBar.Frame
if titleBar then
    local titleLabel
    local versionLabel

    for _, descendant in ipairs(titleBar:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            if descendant.Text == "Afright Scripts" then
                titleLabel = descendant
            elseif descendant.Text == "1.0.0" then
                versionLabel = descendant
            end
        end
    end

    if titleLabel and versionLabel then
        local layout = titleLabel.Parent:FindFirstChildOfClass("UIListLayout")
        if layout then
            layout.Padding = UDim.new(0, 4)
        end

        titleLabel.AutomaticSize = Enum.AutomaticSize.None
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextTruncate = Enum.TextTruncate.None

        local function alignVersion()
            local textWidth = titleLabel.TextBounds.X
            titleLabel.Size = UDim2.new(0, textWidth > 0 and math.ceil(textWidth) + 1 or 95, 1, 0)
        end

        alignVersion()
        titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(alignVersion)

        versionLabel.AutomaticSize = Enum.AutomaticSize.None
        versionLabel.Size = UDim2.new(0, 48, 1, 0)
        versionLabel.TextXAlignment = Enum.TextXAlignment.Left
    end
end

local Combat = Window:AddTab({Title = "Combat", Icon = "swords"})
local VisualTab = Window:AddTab({Title = "Visuals", Icon = "eye"})

Combat:AddToggle("CV_HitboxEnabled", {
    Title = "Enemy Head Hitboxes",
    Default = false,
    Callback = function(value)
        Settings.HitboxEnabled = value
        if not value then
            restoreAllHitboxes()
        end
    end
})

Combat:AddSlider("CV_HitboxSize", {
    Title = "Head Hitbox Size",
    Default = 10,
    Min = 2,
    Max = 40,
    Rounding = 0,
    Callback = function(value)
        Settings.HitboxSize = value
    end
})

Combat:AddToggle("CV_AimbotEnabled", {
    Title = "Head Aimbot",
    Description = "Smoothly aims at visible enemy heads near the crosshair",
    Default = false,
    Callback = function(value)
        Settings.AimbotEnabled = value
        CurrentTarget = nil
        AimElapsed = 0.12
    end
})

Combat:AddSlider("CV_AimRadius", {
    Title = "Aimbot FOV (Pixels)",
    Default = 250,
    Min = 50,
    Max = 600,
    Rounding = 0,
    Callback = function(value)
        Settings.AimRadius = value
    end
})

VisualTab:AddToggle("CV_ESPEnabled", {
    Title = "Enemy ESP",
    Default = false,
    Callback = function(value)
        Settings.ESPEnabled = value
    end
})

VisualTab:AddDropdown("CV_ESPMode", {
    Title = "ESP Style",
    Values = {"2D", "3D"},
    Multi = false,
    Default = "2D",
    Callback = function(value)
        Settings.ESPMode = value
    end
})

VisualTab:AddDropdown("CV_HitboxVisual", {
    Title = "Head Hitbox Outline",
    Values = {"Off", "2D", "3D"},
    Multi = false,
    Default = "3D",
    Callback = function(value)
        Settings.HitboxVisual = value
    end
})

VisualTab:AddToggle("CV_ESPInfo", {
    Title = "Names, Health & Distance (2D)",
    Default = true,
    Callback = function(value)
        Settings.ESPInfo = value
    end
})

VisualTab:AddButton({
    Title = "Unload",
    Callback = function()
        Controller:Stop()
    end
})

local hitboxElapsed = 0
Controller.Connections[#Controller.Connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not Controller.Alive then
        return
    end
    if Fluent.Unloaded then
        Controller:Stop()
        return
    end
    hitboxElapsed += dt
    if hitboxElapsed < 0.12 then
        return
    end
    hitboxElapsed = 0
    if not Settings.HitboxEnabled and next(Hitboxes) then
        restoreAllHitboxes()
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            updateHitbox(player)
        end
    end
end)

RunService:BindToRenderStep(RenderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not Controller.Alive then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    updateAim(camera, dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            renderPlayer(player, camera)
        end
    end
end)

Controller.Connections[#Controller.Connections + 1] = Players.PlayerRemoving:Connect(function(player)
    restoreHitbox(player)
    removeVisualRecord(player)
    if CurrentTarget == player then
        CurrentTarget = nil
    end
end)

Window:SelectTab(1)
