local REQUIRED_PLACE_ID = 2768379856

if game.PlaceId ~= REQUIRED_PLACE_ID then

    print(string.format("[Afright Scripts] Wrong game! Expected PlaceId %s; current PlaceId %s.", tostring(REQUIRED_PLACE_ID), tostring(game.PlaceId)))

    return

end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local env = getgenv and getgenv() or _G

if type(env.__3008FluentCleanup) == "function" then
    pcall(env.__3008FluentCleanup)
end

local oldGui = playerGui:FindFirstChild("Mod Menu")
if oldGui then
    oldGui:Destroy()
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "3008 Mod Menu",
    SubTitle = "Movement Update | Fluent UI",
    TabWidth = 150,
    Size = UDim2.fromOffset(575, 450),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift
})

local Tabs = {
    Main = Window:AddTab({Title = "Main", Icon = "home"}),
    Visuals = Window:AddTab({Title = "Visuals", Icon = "eye"}),
    Movement = Window:AddTab({Title = "Movement", Icon = "footprints"})
}

local state = {
    watch = false,
    nickname = false,
    nicknameText = "New Nickname",
    esp = false,
    fullbright = false,
    antiFall = false,
    speed = 16,
    jumpPower = 40
}

local connections = {}
local espConnection
local watchConnection
local nicknameConnection
local headlightConnection
local antiFallConnection
local timeConnection
local highlighted = {}
local originalHumanoidStats = {}
local originalNickname
local originalWatchVisibility
local originalWatchText
local heldFreefallHumanoid
local cleaned = false
local miscShutdown = function() end

local function bind(connection)
    table.insert(connections, connection)
    return connection
end

local function disconnect(connection)
    if connection then
        connection:Disconnect()
    end
end

local function notify(message, duration)
    if cleaned or Fluent.Unloaded then
        return
    end
    Fluent:Notify({
        Title = "3008 Mod Menu",
        Content = message,
        Duration = duration or 4
    })
end

local function findTimeTextBox()
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj.Name == "TimeLeft" then
            local input = obj:FindFirstChild("Input")
            local textBox = input and input:FindFirstChild("TextBox")
            if textBox and textBox:IsA("TextBox") then
                return textBox
            end
        end
    end
    return nil
end

local function getGamepassClock()
    local mainGui = playerGui:FindFirstChild("MainGui")
    local topBar = mainGui and mainGui:FindFirstChild("TopBar")
    local calendar = topBar and topBar:FindFirstChild("Calendar")
    return calendar and calendar:FindFirstChild("Gamepass_Clock") or nil
end

local function getUsernameLabel()
    local topBar = playerGui:FindFirstChild("TopBar")
    local fakeTopBar = topBar and topBar:FindFirstChild("Fake_TopBar")
    local username = fakeTopBar and fakeTopBar:FindFirstChild("username")
    if username and (username:IsA("TextLabel") or username:IsA("TextButton") or username:IsA("TextBox")) then
        return username
    end
    return nil
end

local function formatSecondsToTime(seconds)
    local value = tonumber(seconds)
    if not value then
        return tostring(seconds)
    end
    value = math.max(0, math.floor(value))
    return string.format("%d:%02d", math.floor(value / 60), value % 60)
end

local function refreshWatch()
    if not state.watch then
        return
    end
    local clock = getGamepassClock()
    local timeBox = findTimeTextBox()
    if clock then
        if originalWatchVisibility == nil then
            originalWatchVisibility = clock.Visible
            if clock:IsA("TextLabel") or clock:IsA("TextButton") then
                originalWatchText = clock.Text
            end
        end
        clock.Visible = true
        if timeBox and (clock:IsA("TextLabel") or clock:IsA("TextButton")) then
            clock.Text = formatSecondsToTime(timeBox.Text)
        end
    end
end

local function setWatch(enabled)
    state.watch = enabled
    disconnect(watchConnection)
    watchConnection = nil
    if enabled then
        refreshWatch()
        local timeBox = findTimeTextBox()
        if timeBox then
            watchConnection = timeBox:GetPropertyChangedSignal("Text"):Connect(refreshWatch)
        else
            notify("Game clock input has not been found yet.")
        end
    else
        local clock = getGamepassClock()
        if clock then
            clock.Visible = false
            if originalWatchText and (clock:IsA("TextLabel") or clock:IsA("TextButton")) then
                clock.Text = originalWatchText
            end
        end
    end
end

local function restoreNickname()
    disconnect(nicknameConnection)
    nicknameConnection = nil
    local label = getUsernameLabel()
    if label and originalNickname ~= nil then
        label.Text = originalNickname
    end
end

local function setNickname(enabled)
    state.nickname = enabled
    disconnect(nicknameConnection)
    nicknameConnection = nil
    if not enabled then
        restoreNickname()
        return
    end
    local label = getUsernameLabel()
    if not label then
        notify("The game's username label was not found.")
        return
    end
    if originalNickname == nil then
        originalNickname = label.Text
    end
    label.Text = state.nicknameText
    nicknameConnection = RunService.Heartbeat:Connect(function()
        if not state.nickname then
            return
        end
        local current = getUsernameLabel()
        if current and current.Text ~= state.nicknameText then
            current.Text = state.nicknameText
        end
    end)
end

local function removeHeadlight()
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    local light = head and head:FindFirstChild("HeadlightFB")
    if light then
        light:Destroy()
    end
end

local function addHeadlight()
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    if not head then
        return
    end
    removeHeadlight()
    local light = Instance.new("PointLight")
    light.Name = "HeadlightFB"
    light.Brightness = 10
    light.Range = 250
    light.Shadows = false
    light.Parent = head
end

local function setFullbright(enabled)
    state.fullbright = enabled
    disconnect(headlightConnection)
    headlightConnection = nil
    if enabled then
        addHeadlight()
        headlightConnection = player.CharacterAdded:Connect(function(character)
            local head = character:WaitForChild("Head", 10)
            if head and state.fullbright and not cleaned then
                addHeadlight()
            end
        end)
    else
        removeHeadlight()
    end
end

local function destroyHighlights()
    for model, highlight in pairs(highlighted) do
        if highlight then
            pcall(function()
                highlight:Destroy()
            end)
        end
        highlighted[model] = nil
    end
end

local function applyHighlight(model)
    if not state.esp or not model or not model:IsA("Model") or model == player.Character then
        return
    end
    if not model:FindFirstChildOfClass("Humanoid") then
        return
    end
    local existing = highlighted[model]
    if existing and existing.Parent ~= model then
        highlighted[model] = nil
        existing = nil
    end
    local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
    if existing then
        existing.FillColor = isPlayer and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(255, 0, 50)
        return
    end
    local old = model:FindFirstChild("MenuESP")
    if old and old:IsA("Highlight") then
        old:Destroy()
    end
    local highlight = Instance.new("Highlight")
    highlight.Name = "MenuESP"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.OutlineColor = Color3.new(1, 1, 1)
    highlight.FillColor = isPlayer and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(255, 0, 50)
    highlight.Parent = model
    highlighted[model] = highlight
end

local function setESP(enabled)
    state.esp = enabled
    disconnect(espConnection)
    espConnection = nil
    if not enabled then
        destroyHighlights()
        return
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Humanoid") then
            applyHighlight(obj.Parent)
        end
    end
    espConnection = Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Humanoid") then
            applyHighlight(obj.Parent)
        elseif obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
            applyHighlight(obj)
        end
    end)
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            applyHighlight(otherPlayer.Character)
        end
    end
end

local function restoreFreefall()
    local humanoid = heldFreefallHumanoid
    heldFreefallHumanoid = nil
    if humanoid and humanoid.Parent then
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
        end)
    end
    local character = player.Character
    local currentHumanoid = character and character:FindFirstChildOfClass("Humanoid")
    if currentHumanoid and currentHumanoid ~= humanoid then
        pcall(function()
            currentHumanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
        end)
    end
end

local function setAntiFall(enabled)
    state.antiFall = enabled
    disconnect(antiFallConnection)
    antiFallConnection = nil
    restoreFreefall()
    if enabled then
        antiFallConnection = RunService.PreRender:Connect(function()
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                return
            end
            if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
                if heldFreefallHumanoid and heldFreefallHumanoid ~= humanoid then
                    restoreFreefall()
                end
                heldFreefallHumanoid = humanoid
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
            end
            if heldFreefallHumanoid == humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
                restoreFreefall()
            end
        end)
    end
end

local function restoreHumanoidStats()
    for humanoid, original in pairs(originalHumanoidStats) do
        if humanoid and humanoid.Parent then
            pcall(function()
                humanoid.WalkSpeed = original.speed
                humanoid.UseJumpPower = original.useJumpPower
                humanoid.JumpPower = original.jumpPower
                if original.hipHeight then humanoid.HipHeight = original.hipHeight end
            end)
        end
        originalHumanoidStats[humanoid] = nil
    end
end

local function cleanup(fromGuiDestroy)
    if cleaned then
        return
    end
    cleaned = true
    miscShutdown()
    state.watch = false
    state.nickname = false
    state.esp = false
    state.fullbright = false
    state.antiFall = false
    disconnect(espConnection)
    disconnect(watchConnection)
    disconnect(nicknameConnection)
    disconnect(headlightConnection)
    disconnect(antiFallConnection)
    disconnect(timeConnection)
    for _, connection in ipairs(connections) do
        disconnect(connection)
    end
    destroyHighlights()
    restoreFreefall()
    restoreHumanoidStats()
    removeHeadlight()
    local label = getUsernameLabel()
    if label and originalNickname ~= nil then
        label.Text = originalNickname
    end
    local clock = getGamepassClock()
    if clock then
        if originalWatchVisibility ~= nil then
            clock.Visible = originalWatchVisibility
        end
        if originalWatchText and (clock:IsA("TextLabel") or clock:IsA("TextButton")) then
            clock.Text = originalWatchText
        end
    end
    if env.__3008FluentCleanup == cleanup then
        env.__3008FluentCleanup = nil
    end
    if not fromGuiDestroy then
        pcall(function()
            Fluent:Destroy()
        end)
    end
end

env.__3008FluentCleanup = cleanup

if Fluent.GUI then
    bind(Fluent.GUI.Destroying:Connect(function()
        cleanup(true)
    end))
end

local misc = {
    customHealth = false,
    dayBright = false,
    noFog = false,
    noFallDamage = false,
    loopSpeed = false,
    fly = false,
    flySpeed = 50,
    noclip = false,
    infiniteJump = false,
    hpNotify = false,
    hpBars = false,
    playerESP = false,
    npcESP = false,
    sprint = false,
    sprintSpeed = 32,
    flyVerticalSpeed = 50,
    glide = false,
    glideFallSpeed = 12,
    gravityEnabled = false,
    gravityValue = Workspace.Gravity,
    hipHeightEnabled = false,
    hipHeightValue = 3,
    dash = false,
    dashSpeed = 95,
    dashCooldown = 1.5,
    fovEnabled = false,
    fovValue = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70
}
local miscConnections = {}
local miscOriginalCameraMode = player.CameraMode
local miscOriginalMinZoom = player.CameraMinZoomDistance
local miscOriginalMaxZoom = player.CameraMaxZoomDistance
local miscHealthGui
local miscLightingOriginal
local miscFogDensities = {}
local miscEpoch = {}
local miscDisabledFallScripts = {}
local miscNoclipParts = {}
local miscFlyGyro
local miscFlyVelocity
local miscOverlayFolder
local miscOverlayTargets = {}
local miscHealthBarFolder
local originalGravity = Workspace.Gravity
local originalFovCamera
local originalFovValue
local lastDashTime = -math.huge

local function miscConnect(key, connection)
    if miscConnections[key] then
        disconnect(miscConnections[key])
    end
    miscConnections[key] = connection
    return connection
end

local function miscDisconnect(key)
    disconnect(miscConnections[key])
    miscConnections[key] = nil
end

local function bumpMiscEpoch(key)
    miscEpoch[key] = (miscEpoch[key] or 0) + 1
    return miscEpoch[key]
end

local function getMyHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid"), character
end

local function setCameraMode(value)
    if value == "LockFirstPerson (First-Person)" then
        player.CameraMode = Enum.CameraMode.LockFirstPerson
    else
        player.CameraMode = Enum.CameraMode.Classic
    end
end

local function updateCustomHealthBar()
    if not misc.customHealth or not miscHealthGui then return end
    local bg = miscHealthGui:FindFirstChild("HealthBG")
    local fill = bg and bg:FindFirstChild("HealthBar")
    local label = bg and bg:FindFirstChild("HealthText")
    local humanoid = getMyHumanoid()
    if not fill or not label then return end
    local health = humanoid and humanoid.Health or 0
    local maxHealth = humanoid and math.max(humanoid.MaxHealth, 1) or 100
    local pct = math.clamp(health / maxHealth, 0, 1)
    fill.Size = UDim2.new(pct, -6 * pct, 1, -6)
    fill.BackgroundColor3 = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 60)
    label.Text = string.format("HP: %d/%d", math.ceil(health), math.ceil(maxHealth))
end

local function bindCustomHealth()
    miscDisconnect("customHealthChanged")
    miscDisconnect("customMaxHealthChanged")
    local humanoid = getMyHumanoid()
    if humanoid then
        miscConnect("customHealthChanged", humanoid.HealthChanged:Connect(updateCustomHealthBar))
        miscConnect("customMaxHealthChanged", humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateCustomHealthBar))
    end
    updateCustomHealthBar()
end

local function setCustomHealth(enabled)
    misc.customHealth = enabled
    if not enabled then
        miscDisconnect("customHealthChanged")
        miscDisconnect("customMaxHealthChanged")
        if miscHealthGui then miscHealthGui:Destroy() miscHealthGui = nil end
        return
    end
    if miscHealthGui then miscHealthGui:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "CustomHealthBarGUI"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui
    local background = Instance.new("Frame")
    background.Name = "HealthBG"
    background.Size = UDim2.fromOffset(260, 35)
    background.Position = UDim2.new(0.5, -130, 0.85, 0)
    background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    background.BorderColor3 = Color3.fromRGB(60, 60, 60)
    background.BorderSizePixel = 2
    background.Active = true
    background.Draggable = true
    background.Parent = gui
    local fill = Instance.new("Frame")
    fill.Name = "HealthBar"
    fill.Position = UDim2.fromOffset(3, 3)
    fill.Size = UDim2.new(1, -6, 1, -6)
    fill.BorderSizePixel = 0
    fill.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    fill.Parent = background
    local label = Instance.new("TextLabel")
    label.Name = "HealthText"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.TextScaled = true
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.SourceSansBold
    label.ZIndex = 2
    label.Parent = background
    miscHealthGui = gui
    bindCustomHealth()
end

local function saveLightingOriginal()
    if miscLightingOriginal then return end
    miscLightingOriginal = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows
    }
    for _, item in ipairs(Lighting:GetChildren()) do
        if item:IsA("Atmosphere") then
            miscFogDensities[item] = item.Density
        end
    end
end

local function applyMiscLighting()
    if not miscLightingOriginal then return end
    local old = miscLightingOriginal
    Lighting.Brightness = misc.dayBright and 2 or old.Brightness
    Lighting.ClockTime = misc.dayBright and 14 or old.ClockTime
    Lighting.GlobalShadows = misc.dayBright and false or old.GlobalShadows
    Lighting.FogStart = misc.noFog and 1000000 or old.FogStart
    Lighting.FogEnd = misc.noFog and 1000000 or (misc.dayBright and 100000 or old.FogEnd)
    for _, item in ipairs(Lighting:GetChildren()) do
        if item:IsA("Atmosphere") and miscFogDensities[item] == nil then
            miscFogDensities[item] = item.Density
        end
    end
    for atmosphere, density in pairs(miscFogDensities) do
        if atmosphere.Parent then
            atmosphere.Density = misc.noFog and 0 or density
        end
    end
    if not misc.dayBright and not misc.noFog then
        miscLightingOriginal = nil
        table.clear(miscFogDensities)
    end
end

local function setLightingTest(kind, enabled)
    if enabled then saveLightingOriginal() end
    misc[kind] = enabled
    applyMiscLighting()
    if misc.dayBright or misc.noFog then
        if not miscConnections.lightingRefresh then
            local accumulator = 0
            miscConnect("lightingRefresh", RunService.Heartbeat:Connect(function(dt)
                if cleaned then return end
                accumulator += dt
                if accumulator < 0.5 then return end
                accumulator = 0
                if misc.dayBright or misc.noFog then applyMiscLighting() end
            end))
        end
    else
        miscDisconnect("lightingRefresh")
    end
end

local function disableLocalFallScripts(character)
    if not character then return end
    for _, obj in ipairs(character:GetDescendants()) do
        local name = string.lower(obj.Name)
        if obj:IsA("LocalScript") and string.find(name, "fall", 1, true)
            and string.find(name, "damage", 1, true) then
            if miscDisabledFallScripts[obj] == nil then miscDisabledFallScripts[obj] = obj.Enabled end
            obj.Enabled = false
        end
    end
end

local function setNoFallDamage(enabled)
    misc.noFallDamage = enabled
    miscDisconnect("fallScriptAdded")
    if enabled then
        local character = player.Character
        disableLocalFallScripts(character)
        if character then
            miscConnect("fallScriptAdded", character.DescendantAdded:Connect(function()
                if misc.noFallDamage then disableLocalFallScripts(character) end
            end))
        end
    else
        for obj, original in pairs(miscDisabledFallScripts) do
            if obj.Parent then pcall(function() obj.Enabled = original end) end
            miscDisabledFallScripts[obj] = nil
        end
    end
end

local function setLoopSpeed(enabled)
    misc.loopSpeed = enabled
    miscDisconnect("loopSpeed")
    if enabled then
        miscConnect("loopSpeed", RunService.Stepped:Connect(function()
            local humanoid = getMyHumanoid()
            local speed = misc.sprint and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and misc.sprintSpeed or state.speed
            if humanoid and humanoid.WalkSpeed ~= speed then humanoid.WalkSpeed = speed end
        end))
    end
end

local function stopFly()
    miscDisconnect("fly")
    if miscFlyGyro then miscFlyGyro:Destroy() miscFlyGyro = nil end
    if miscFlyVelocity then miscFlyVelocity:Destroy() miscFlyVelocity = nil end
end

local function setFly(enabled)
    misc.fly = enabled
    stopFly()
    if not enabled then return end
    local humanoid, character = getMyHumanoid()
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then notify("Fly needs a loaded character.", 4) return end
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "ExecBodyGyro"
    gyro.P = 90000
    gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    gyro.CFrame = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or root.CFrame
    gyro.Parent = root
    local vel = Instance.new("BodyVelocity")
    vel.Name = "ExecBodyVelocity"
    vel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    vel.Velocity = Vector3.zero
    vel.Parent = root
    miscFlyGyro, miscFlyVelocity = gyro, vel
    miscConnect("fly", RunService.RenderStepped:Connect(function()
        if not misc.fly or not root.Parent then return end
        local camera = Workspace.CurrentCamera
        if not camera then return end
        gyro.CFrame = camera.CFrame
        local vertical = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then vertical += 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then vertical -= 1 end
        local move = humanoid and humanoid.MoveDirection or Vector3.zero
        vel.Velocity = move * misc.flySpeed + Vector3.new(0, vertical * misc.flyVerticalSpeed, 0)
    end))
end

local function setNoclip(enabled)
    misc.noclip = enabled
    miscDisconnect("noclip")
    if enabled then
        miscConnect("noclip", RunService.Stepped:Connect(function()
            local character = player.Character
            if not character then return end
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    if miscNoclipParts[part] == nil then miscNoclipParts[part] = part.CanCollide end
                    part.CanCollide = false
                end
            end
        end))
    else
        for part, original in pairs(miscNoclipParts) do
            if part.Parent then pcall(function() part.CanCollide = original end) end
            miscNoclipParts[part] = nil
        end
    end
end

local function sendHealthStatus()
    local messages = {}
    for _, other in ipairs(Players:GetPlayers()) do
        local hum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
        if hum then table.insert(messages, string.format("%s: %d/%d HP", other.Name, math.ceil(hum.Health), math.ceil(hum.MaxHealth))) end
    end
    if #messages == 0 then notify("No player health values available.", 3)
    else notify(table.concat(messages, "\n"), 8) end
end

local function setHPNotify(enabled)
    misc.hpNotify = enabled
    local generation = bumpMiscEpoch("hpNotify")
    if enabled then
        task.spawn(function()
            while misc.hpNotify and not cleaned and miscEpoch.hpNotify == generation do
                sendHealthStatus()
                task.wait(15)
            end
        end)
    end
end

local function clearHealthBars()
    if miscHealthBarFolder then miscHealthBarFolder:Destroy() miscHealthBarFolder = nil end
    for key in pairs(miscConnections) do
        if string.sub(key, 1, 7) == "hpbar__" then miscDisconnect(key) end
    end
end

local function refreshHealthBars()
    if not misc.hpBars then return end
    if not miscHealthBarFolder then
        miscHealthBarFolder = Instance.new("Folder")
        miscHealthBarFolder.Name = "3008HealthBarESP_Storage"
        miscHealthBarFolder.Parent = Workspace
    end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local character = other.Character
            local head = character and character:FindFirstChild("Head")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if head and humanoid then
                local key = "hpbar__" .. other.UserId
                local existing = miscHealthBarFolder:FindFirstChild(key)
                if existing and existing.Adornee ~= head then
                    existing:Destroy()
                    miscDisconnect(key)
                    existing = nil
                end
                if not existing then
                    local gui = Instance.new("BillboardGui")
                    gui.Name = key
                    gui.Adornee = head
                    gui.Size = UDim2.new(4, 0, 0.6, 0)
                    gui.StudsOffset = Vector3.new(0, 2.5, 0)
                    gui.AlwaysOnTop = true
                    gui.Parent = miscHealthBarFolder
                    local background = Instance.new("Frame")
                    background.Name = "BG"
                    background.Size = UDim2.fromScale(1, 0.4)
                    background.Position = UDim2.fromScale(0, 0.6)
                    background.BorderSizePixel = 0
                    background.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                    background.Parent = gui
                    local fill = Instance.new("Frame")
                    fill.Name = "Bar"
                    fill.BorderSizePixel = 0
                    fill.BackgroundColor3 = Color3.fromRGB(0, 255, 110)
                    fill.Parent = background
                    local function update()
                        if not gui.Parent or not humanoid.Parent then return end
                        local percent = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                        fill.Size = UDim2.fromScale(percent, 1)
                        fill.BackgroundColor3 = Color3.fromRGB(math.floor(255 * (1 - percent)), math.floor(255 * percent), 70)
                    end
                    miscConnect(key, humanoid.HealthChanged:Connect(update))
                    update()
                end
            end
        end
    end
end

local function setHPBars(enabled)
    misc.hpBars = enabled
    local generation = bumpMiscEpoch("hpBars")
    if enabled then
        task.spawn(function()
            while misc.hpBars and not cleaned and miscEpoch.hpBars == generation do
                refreshHealthBars()
                task.wait(1.5)
            end
        end)
    else
        clearHealthBars()
    end
end

local function ensureOverlayFolder()
    if not miscOverlayFolder then
        miscOverlayFolder = Instance.new("Folder")
        miscOverlayFolder.Name = "3008ExtraESP_Storage"
        miscOverlayFolder.Parent = Workspace
    end
end

local function refreshExtraESP()
    if not misc.playerESP and not misc.npcESP then
        if miscOverlayFolder then miscOverlayFolder:Destroy() miscOverlayFolder = nil end
        table.clear(miscOverlayTargets)
        return
    end
    ensureOverlayFolder()
    for model, highlight in pairs(miscOverlayTargets) do
        local isPlayer = model.Parent and Players:GetPlayerFromCharacter(model) ~= nil
        if not model.Parent or (isPlayer and not misc.playerESP) or (not isPlayer and not misc.npcESP) then
            highlight:Destroy()
            miscOverlayTargets[model] = nil
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local model = obj.Parent
            local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
            local active = (isPlayer and model ~= player.Character and misc.playerESP) or (not isPlayer and misc.npcESP)
            if active and not miscOverlayTargets[model] then
                local highlight = Instance.new("Highlight")
                highlight.Name = "MiscESP"
                highlight.Adornee = model
                highlight.FillColor = isPlayer and Color3.fromRGB(0, 255, 139) or Color3.fromRGB(255, 80, 80)
                highlight.OutlineColor = Color3.new(1, 1, 1)
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 0
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Parent = miscOverlayFolder
                miscOverlayTargets[model] = highlight
            end
        end
    end
end

local function setExtraESP(field, enabled)
    misc[field] = enabled
    if misc.playerESP or misc.npcESP then
        if not miscConnections.extraESP then
            miscConnect("extraESP", Workspace.DescendantAdded:Connect(function(obj)
                if obj:IsA("Humanoid") then task.defer(refreshExtraESP) end
            end))
        end
        refreshExtraESP()
    else
        miscDisconnect("extraESP")
        refreshExtraESP()
    end
end

bind(player.CharacterAdded:Connect(function(character)
    task.defer(function()
        if cleaned then return end
        character:WaitForChild("Humanoid", 10)
        if cleaned then return end
        if misc.customHealth then bindCustomHealth() end
        if misc.noFallDamage then setNoFallDamage(true) end
        if misc.fly then setFly(true) end
        if misc.hipHeightEnabled then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.HipHeight = misc.hipHeightValue end
        end
    end)
end))

bind(UserInputService.JumpRequest:Connect(function()
    if not misc.infiniteJump or cleaned then return end
    local humanoid = getMyHumanoid()
    if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

miscShutdown = function()
    for key, enabled in pairs(misc) do
        if type(enabled) == "boolean" then misc[key] = false end
    end
    for key in pairs(miscConnections) do miscDisconnect(key) end
    stopFly()
    setNoclip(false)
    setNoFallDamage(false)
    Workspace.Gravity = originalGravity
    if originalFovCamera and originalFovCamera.Parent and originalFovValue then
        originalFovCamera.FieldOfView = originalFovValue
    end
    clearHealthBars()
    if miscOverlayFolder then miscOverlayFolder:Destroy() miscOverlayFolder = nil end
    table.clear(miscOverlayTargets)
    if miscHealthGui then miscHealthGui:Destroy() miscHealthGui = nil end
    player.CameraMode = miscOriginalCameraMode
    player.CameraMinZoomDistance = miscOriginalMinZoom
    player.CameraMaxZoomDistance = miscOriginalMaxZoom
    applyMiscLighting()
end

local function setGravityOverride(enabled)
    misc.gravityEnabled = enabled
    Workspace.Gravity = enabled and misc.gravityValue or originalGravity
end

local function setHipHeightOverride(enabled)
    misc.hipHeightEnabled = enabled
    local humanoid = getMyHumanoid()
    if humanoid then
        local old = originalHumanoidStats[humanoid]
        if not old then
            old = {
                speed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                useJumpPower = humanoid.UseJumpPower,
                hipHeight = humanoid.HipHeight
            }
            originalHumanoidStats[humanoid] = old
        end
        humanoid.HipHeight = enabled and misc.hipHeightValue or old.hipHeight
    end
end

local function setFovOverride(enabled)
    misc.fovEnabled = enabled
    if enabled then
        local camera = Workspace.CurrentCamera
        if camera then
            if camera ~= originalFovCamera then
                originalFovCamera, originalFovValue = camera, camera.FieldOfView
            end
            camera.FieldOfView = misc.fovValue
        end
    else
        if originalFovCamera and originalFovCamera.Parent and originalFovValue then
            originalFovCamera.FieldOfView = originalFovValue
        end
        originalFovCamera, originalFovValue = nil, nil
    end
end

bind(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if cleaned or gameProcessed or not misc.dash or input.KeyCode ~= Enum.KeyCode.X then return end
    local now = os.clock()
    if now - lastDashTime < misc.dashCooldown then return end
    local humanoid, character = getMyHumanoid()
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return end
    local direction = humanoid.MoveDirection
    if direction.Magnitude < 0.05 then
        local camera = Workspace.CurrentCamera
        direction = camera and camera.CFrame.LookVector or root.CFrame.LookVector
    end
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.05 then return end
    lastDashTime = now
    direction = direction.Unit
    local current = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(direction.X * misc.dashSpeed, current.Y, direction.Z * misc.dashSpeed)
end))

Tabs.Main:AddParagraph({
    Title = "3008 Mod Menu",
    Content = "Active | Right Shift opens or minimizes the UI. Features are organized into Main, Visuals, and Movement."
})

local cyclesParagraph = Tabs.Main:AddParagraph({
    Title = "Cycles End",
    Content = "Searching for the game countdown..."
})

Tabs.Main:AddToggle("FakeWatch3008", {
    Title = "Fake Watch",
    Description = "Shows the game countdown in the local top bar.",
    Default = false
}):OnChanged(setWatch)

Tabs.Main:AddInput("NicknameText3008", {
    Title = "Custom Nickname",
    Description = "Nickname shown locally when Fake Nickname is on.",
    Default = state.nicknameText,
    Placeholder = "Enter nickname",
    Numeric = false,
    Finished = false,
    Callback = function(value)
        state.nicknameText = tostring(value)
        if state.nickname then
            local label = getUsernameLabel()
            if label then label.Text = state.nicknameText end
        end
    end
})

Tabs.Main:AddToggle("FakeNickname3008", {
    Title = "Fake Nickname",
    Description = "Replaces the nickname display locally (not for other players).",
    Default = false
}):OnChanged(setNickname)

Tabs.Main:AddParagraph({
    Title = "Quick Start",
    Content = "Visuals has Fullbright, No Fog, ESP, and camera tools. Movement has Fly, Noclip, Anti-Fall, and adjustable movement settings."
})

Tabs.Visuals:AddParagraph({Title = "Lighting", Content = "Independent environment-lighting controls; no headlight is added."})

Tabs.Visuals:AddToggle("VisualsDayBright3008", {
    Title = "Fullbright (Always Day & Clear)",
    Description = "Uses the original Misc Fullbright: daytime, brightness 2, no global shadows.",
    Default = false
}):OnChanged(function(enabled) setLightingTest("dayBright", enabled) end)

Tabs.Visuals:AddToggle("VisualsNoFog3008", {
    Title = "No Fog",
    Description = "Pushes fog distances far away and sets Atmosphere density to 0.",
    Default = false
}):OnChanged(function(enabled) setLightingTest("noFog", enabled) end)

Tabs.Visuals:AddParagraph({Title = "ESP", Content = "Choose a highlight style. Multiple ESP styles may overlap on the same player."})

Tabs.Visuals:AddToggle("ESP3008", {
    Title = "Player & NPC ESP",
    Description = "Players blue, NPCs red. Draws highlights through walls.",
    Default = false
}):OnChanged(setESP)

Tabs.Visuals:AddToggle("VisualsPlayerESP3008", {
    Title = "Player ESP (Green)",
    Description = "Experimental green highlight for other players.",
    Default = false
}):OnChanged(function(enabled) setExtraESP("playerESP", enabled) end)

Tabs.Visuals:AddToggle("VisualsNPCEsp3008", {
    Title = "NPC ESP (Red)",
    Description = "Experimental red highlight for humanoid NPCs.",
    Default = false
}):OnChanged(function(enabled) setExtraESP("npcESP", enabled) end)

Tabs.Visuals:AddToggle("VisualsHPBars3008", {
    Title = "Player Health Bars",
    Description = "Shows HP bars above other players' heads.",
    Default = false
}):OnChanged(setHPBars)

Tabs.Visuals:AddToggle("VisualsHPNotify3008", {
    Title = "Notify Player Health",
    Description = "Displays visible player HP summaries every 15 seconds.",
    Default = false
}):OnChanged(setHPNotify)

Tabs.Visuals:AddToggle("VisualsCustomHealth3008", {
    Title = "Custom Health Bar",
    Description = "Draggable health bar for your own character.",
    Default = false
}):OnChanged(setCustomHealth)

Tabs.Visuals:AddParagraph({Title = "Camera", Content = "Third-person camera, first-person and Field of View."})

Tabs.Visuals:AddSlider("VisualsCameraZoom3008", {
    Title = "Camera Max Zoom",
    Description = "Maximum third-person zoom distance in studs.",
    Default = 128,
    Min = 0.5,
    Max = 500,
    Rounding = 1,
    Callback = function(value)
        player.CameraMaxZoomDistance = value
    end
})

Tabs.Visuals:AddDropdown("VisualsCameraMode3008", {
    Title = "Camera Mode",
    Description = "Switch between free third-person and first-person lock.",
    Values = {"Classic (Third-Person / Free)", "LockFirstPerson (First-Person)"},
    Multi = false,
    Default = player.CameraMode == Enum.CameraMode.LockFirstPerson and 2 or 1,
    Callback = setCameraMode
})

Tabs.Visuals:AddSlider("VisualsFov3008", {
    Title = "Field of View",
    Description = "Target camera FOV when the FOV toggle is on.",
    Default = misc.fovValue,
    Min = 40,
    Max = 120,
    Rounding = 0,
    Callback = function(value)
        misc.fovValue = value
        if misc.fovEnabled then setFovOverride(true) end
    end
})

Tabs.Visuals:AddToggle("VisualsCustomFov3008", {
    Title = "Custom FOV",
    Description = "Uses the Field of View slider; off restores original FOV.",
    Default = false
}):OnChanged(setFovOverride)

Tabs.Movement:AddParagraph({Title = "Speed & Jump", Content = "WalkSpeed and JumpPower are managed here instead of Main or Misc."})

Tabs.Movement:AddSlider("MovementSpeed3008", {
    Title = "WalkSpeed",
    Description = "Movement speed when sprint is not active.",
    Default = state.speed,
    Min = 0,
    Max = 500,
    Rounding = 0,
    Callback = function(value) state.speed = value end
})

Tabs.Movement:AddSlider("JumpPower3008", {
    Title = "Jump Power",
    Description = "Regular jump power. Uses the Humanoid JumpPower property.",
    Default = state.jumpPower,
    Min = 0,
    Max = 500,
    Rounding = 0,
    Callback = function(value) state.jumpPower = value end
})

Tabs.Movement:AddToggle("MovementLoopSpeed3008", {
    Title = "Loop Speed",
    Description = "Also enforces the speed value on Stepped for games that reset WalkSpeed.",
    Default = false
}):OnChanged(setLoopSpeed)

Tabs.Movement:AddToggle("MovementSprint3008", {
    Title = "Sprint (Hold Left Shift)",
    Description = "Overrides WalkSpeed with Sprint Speed while holding Left Shift.",
    Default = false
}):OnChanged(function(enabled) misc.sprint = enabled end)

Tabs.Movement:AddSlider("MovementSprintSpeed3008", {
    Title = "Sprint Speed",
    Description = "Movement speed while sprinting and holding Left Shift.",
    Default = 32,
    Min = 16,
    Max = 500,
    Rounding = 0,
    Callback = function(value) misc.sprintSpeed = value end
})

Tabs.Movement:AddParagraph({Title = "Fly & Noclip", Content = "Fly with movement keys. Space/E ascends and Ctrl/Q descends."})

Tabs.Movement:AddToggle("MovementFly3008", {
    Title = "Fly",
    Description = "Camera-facing flight with horizontal and vertical speed controls.",
    Default = false
}):OnChanged(setFly)

Tabs.Movement:AddSlider("MovementFlySpeed3008", {
    Title = "Fly Speed",
    Description = "Horizontal flight velocity in studs per second.",
    Default = 50,
    Min = 5,
    Max = 500,
    Rounding = 0,
    Callback = function(value) misc.flySpeed = value end
})

Tabs.Movement:AddSlider("MovementFlyVerticalSpeed3008", {
    Title = "Fly Vertical Speed",
    Description = "Ascending/descending speed for Space/E and Ctrl/Q.",
    Default = 50,
    Min = 5,
    Max = 300,
    Rounding = 0,
    Callback = function(value) misc.flyVerticalSpeed = value end
})

Tabs.Movement:AddToggle("MovementNoclip3008", {
    Title = "Noclip",
    Description = "Temporarily disables collision on your character parts.",
    Default = false
}):OnChanged(setNoclip)

Tabs.Movement:AddToggle("MovementInfiniteJump3008", {
    Title = "Infinite Jump",
    Description = "Allows jumping again in midair.",
    Default = false
}):OnChanged(function(enabled) misc.infiniteJump = enabled end)

Tabs.Movement:AddParagraph({Title = "Fall & Movement Protection", Content = "Anti-Fall and Glide protect against uncontrolled falling."})

Tabs.Movement:AddToggle("MovementAntiFall3008", {
    Title = "Anti-Fall",
    Description = "Existing freefall-state protection; test separately from Glide/Fly.",
    Default = false
}):OnChanged(setAntiFall)

Tabs.Movement:AddToggle("MovementNoFallDamage3008", {
    Title = "No Fall Damage (Test)",
    Description = "Disables local fall-damage scripts, not server-side fall damage.",
    Default = false
}):OnChanged(setNoFallDamage)

Tabs.Movement:AddToggle("MovementGlide3008", {
    Title = "Glide / Slow Fall",
    Description = "Limits downward velocity while airborne (not during Fly).",
    Default = false
}):OnChanged(function(enabled) misc.glide = enabled end)

Tabs.Movement:AddSlider("MovementGlideSpeed3008", {
    Title = "Glide Fall Speed",
    Description = "Maximum downward speed while Glide is active; lower = slower fall.",
    Default = 12,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(value) misc.glideFallSpeed = value end
})

Tabs.Movement:AddParagraph({Title = "Physics & Height", Content = "Gravity and hip height are optional overrides; disabling restores previous values."})

Tabs.Movement:AddToggle("MovementGravity3008", {
    Title = "Custom Gravity",
    Description = "Overrides client-side world gravity with the slider value.",
    Default = false
}):OnChanged(setGravityOverride)

Tabs.Movement:AddSlider("MovementGravityValue3008", {
    Title = "Gravity",
    Description = "Default Roblox gravity is 196.2.",
    Default = math.clamp(originalGravity, 0, 350),
    Min = 0,
    Max = 350,
    Rounding = 1,
    Callback = function(value)
        misc.gravityValue = value
        if misc.gravityEnabled then Workspace.Gravity = value end
    end
})

Tabs.Movement:AddToggle("MovementHipHeight3008", {
    Title = "Custom Hip Height",
    Description = "Changes character standing height; off restores normal height.",
    Default = false
}):OnChanged(setHipHeightOverride)

Tabs.Movement:AddSlider("MovementHipHeightValue3008", {
    Title = "Hip Height",
    Description = "Distance between character root and floor; high values may affect physics.",
    Default = 3,
    Min = 0,
    Max = 20,
    Rounding = 1,
    Callback = function(value)
        misc.hipHeightValue = value
        if misc.hipHeightEnabled then setHipHeightOverride(true) end
    end
})

Tabs.Movement:AddParagraph({Title = "Dash", Content = "Enable Dash, then press X. Speed and cooldown can be customized."})

Tabs.Movement:AddToggle("MovementDash3008", {
    Title = "Dash (X)",
    Description = "Short horizontal velocity burst in the movement/camera direction.",
    Default = false
}):OnChanged(function(enabled) misc.dash = enabled end)

Tabs.Movement:AddSlider("MovementDashSpeed3008", {
    Title = "Dash Speed",
    Description = "Velocity applied when pressing X.",
    Default = 95,
    Min = 20,
    Max = 350,
    Rounding = 0,
    Callback = function(value) misc.dashSpeed = value end
})

Tabs.Movement:AddSlider("MovementDashCooldown3008", {
    Title = "Dash Cooldown (seconds)",
    Description = "Minimum time between dashes.",
    Default = 1.5,
    Min = 0.1,
    Max = 5,
    Rounding = 1,
    Callback = function(value) misc.dashCooldown = value end
})

bind(RunService.Heartbeat:Connect(function()
    if cleaned then
        return
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    if not originalHumanoidStats[humanoid] then
        originalHumanoidStats[humanoid] = {
            speed = humanoid.WalkSpeed,
            jumpPower = humanoid.JumpPower,
            useJumpPower = humanoid.UseJumpPower,
            hipHeight = humanoid.HipHeight
        }
    end
    local chosenSpeed = misc.sprint and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and misc.sprintSpeed or state.speed
    if humanoid.WalkSpeed ~= chosenSpeed then
        humanoid.WalkSpeed = chosenSpeed
    end
    if not humanoid.UseJumpPower then
        humanoid.UseJumpPower = true
    end
    if humanoid.JumpPower ~= state.jumpPower then
        humanoid.JumpPower = state.jumpPower
    end
    if misc.gravityEnabled and Workspace.Gravity ~= misc.gravityValue then
        Workspace.Gravity = misc.gravityValue
    end
    if misc.hipHeightEnabled and humanoid.HipHeight ~= misc.hipHeightValue then
        humanoid.HipHeight = misc.hipHeightValue
    end
    if misc.glide and not misc.fly and humanoid.FloorMaterial == Enum.Material.Air then
        local root = character:FindFirstChild("HumanoidRootPart")
        if root and root.AssemblyLinearVelocity.Y < -misc.glideFallSpeed then
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, -misc.glideFallSpeed, velocity.Z)
        end
    end
    if misc.fovEnabled then
        local camera = Workspace.CurrentCamera
        if camera then
            if camera ~= originalFovCamera then
                if originalFovCamera and originalFovCamera.Parent and originalFovValue then
                    originalFovCamera.FieldOfView = originalFovValue
                end
                originalFovCamera = camera
                originalFovValue = camera.FieldOfView
            end
            if camera.FieldOfView ~= misc.fovValue then camera.FieldOfView = misc.fovValue end
        end
    end
end))

bind(Players.PlayerAdded:Connect(function(otherPlayer)
    bind(otherPlayer.CharacterAdded:Connect(function(character)
        if state.esp and not cleaned then
            task.defer(function()
                if not cleaned and state.esp then
                    applyHighlight(character)
                end
            end)
        end
    end))
end))

for _, otherPlayer in ipairs(Players:GetPlayers()) do
    if otherPlayer ~= player then
        bind(otherPlayer.CharacterAdded:Connect(function(character)
            if state.esp and not cleaned then
                task.defer(function()
                    if not cleaned and state.esp then
                        applyHighlight(character)
                    end
                end)
            end
        end))
    end
end

task.spawn(function()
    for _ = 1, 25 do
        if cleaned then
            return
        end
        local timeBox = findTimeTextBox()
        if timeBox then
            local function refreshCycles()
                if not cleaned then
                    cyclesParagraph:SetDesc(tostring(timeBox.Text))
                    if state.watch then
                        refreshWatch()
                    end
                end
            end
            refreshCycles()
            timeConnection = timeBox:GetPropertyChangedSignal("Text"):Connect(refreshCycles)
            return
        end
        task.wait(0.8)
    end
    if not cleaned then
        cyclesParagraph:SetDesc("Countdown text box not found")
    end
end)

Window:SelectTab(1)
notify("Fluent UI loaded. Press Right Shift to minimize or restore.", 5)