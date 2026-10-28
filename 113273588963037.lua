
local REQUIRED_PLACE_ID = 113273588963037
if game.PlaceId ~= REQUIRED_PLACE_ID then
    print(string.format("[Afright Scripts] Wrong game! Expected PlaceId %s; current PlaceId %s.", tostring(REQUIRED_PLACE_ID), tostring(game.PlaceId)))
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local attackRemote = remotes:WaitForChild("Attack")
local swingRemote = remotes:FindFirstChild("Swing")

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Afright Scripts",
    SubTitle = "1.0.0",
    TabWidth = 150,
    Size = UDim2.fromOffset(520, 360),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift
})

local MainTab = Window:AddTab({ Title = "Combat", Icon = "swords" })
local ESPTab = Window:AddTab({ Title = "ESP", Icon = "eye" })

local ROOT_NAMES = {
    "HumanoidRootPart", "RootPart", "Root", "CharacterRoot", "CollisionRoot",
}
local BODY_NAMES = {"Torso", "LowerTorso", "UpperTorso", "Body", "MainBody", "Head"}

local function getRigHumanoid(character)
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
        or character:FindFirstChildWhichIsA("Humanoid", true)
end

local function getCharacterRoot(character)
    if not character then return nil end
    local humanoid = getRigHumanoid(character)
    if humanoid and humanoid.RootPart and humanoid.RootPart:IsA("BasePart")
        and humanoid.RootPart:IsDescendantOf(character) then
        return humanoid.RootPart
    end
    for _, name in ipairs(ROOT_NAMES) do
        local part = character:FindFirstChild(name, true)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    if character:IsA("Model") and character.PrimaryPart then
        return character.PrimaryPart
    end
    for _, name in ipairs(BODY_NAMES) do
        local part = character:FindFirstChild(name, true)
        if part and part:IsA("BasePart") then return part end
    end
    local fallback
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if not descendant.Anchored then return descendant end
            fallback = fallback or descendant
        end
    end
    return fallback
end

local lastAttack = -math.huge
local attackCount = 0
local cooldown = 0.625
local maxScaledRange = 4
local auraConnection = nil
local targetPriority = "Closest"
local TARGET_ROTATION_SECONDS = 2.0
local rotatingTargetCharacter = nil
local rotatingTargetSince = 0
local MAX_RAYCASTS_PER_ATTACK = 96
local attackInProgress = false
local attackErrorRetryAt = 0
local friendCheckEnabled = true
local friendCache = {} 

local function requestFriendStatus(otherPlayer)
    local userId = otherPlayer.UserId
    if friendCache[userId] ~= nil then
        return
    end

    friendCache[userId] = "pending"
    task.spawn(function()
        local ok, isFriend = pcall(function()
            return player:IsFriendsWith(userId)
        end)
        if ok then
            friendCache[userId] = isFriend 
        else
            friendCache[userId] = "unknown" 
        end
    end)
end

local function canTargetPlayer(otherPlayer)
    if not friendCheckEnabled then
        return true
    end

    requestFriendStatus(otherPlayer)
    return friendCache[otherPlayer.UserId] == false
end

local CURRENT_HEALTH_FIELDS = {
    "CurrentHealth", "CurrentHP", "Health", "HP", "HitPoints", "HealthValue",
}
local MAX_HEALTH_FIELDS = {
    "MaxHealth", "MaximumHealth", "MaxHP", "MaximumHP", "MaxHitPoints",
}
local HEALTH_DATA_CONTAINERS = {
    "Stats", "HealthData", "CombatStats", "PlayerStats", "Status", "Values", "Data", "leaderstats", "Health",
}

local function validNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function readNumber(root, fields)
    if not root then
        return nil, nil, nil
    end

    for _, field in ipairs(fields) do
        local attribute = root:GetAttribute(field)
        if validNumber(attribute) then
            return attribute, root, field
        end
    end

    if root.Name == "Health" and fields == CURRENT_HEALTH_FIELDS then
        for _, field in ipairs({"Current", "Value"}) do
            local child = root:FindFirstChild(field)
            if child and (child:IsA("NumberValue") or child:IsA("IntValue")) and validNumber(child.Value) then
                return child.Value, child, nil
            end
        end
        for _, field in ipairs({"Current", "Value"}) do
            local attribute = root:GetAttribute(field)
            if validNumber(attribute) then
                return attribute, root, field
            end
        end
    end
    for _, field in ipairs(fields) do
        local child = root:FindFirstChild(field)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            local value = child.Value
            if validNumber(value) then
                return value, child, nil
            end
        end
    end

    return nil, nil, nil
end

local function healthRoots(character, owner)
    local roots = {character}
    local humanoid = getRigHumanoid(character)
    if humanoid then
        roots[#roots + 1] = humanoid 
    end
    for _, name in ipairs(HEALTH_DATA_CONTAINERS) do
        local child = character:FindFirstChild(name)
        if child then
            roots[#roots + 1] = child
        end
    end
    if owner then
        roots[#roots + 1] = owner
        for _, name in ipairs(HEALTH_DATA_CONTAINERS) do
            local child = owner:FindFirstChild(name)
            if child then
                roots[#roots + 1] = child
            end
        end
    end
    return roots
end


local function getHealthInfo(character, owner)
    if not character or not character:IsDescendantOf(Workspace) then
        return nil
    end

    local humanoid = getRigHumanoid(character)
    if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then
        return nil
    end
    if character:GetAttribute("Dead") == true or character:GetAttribute("IsDead") == true then
        return nil
    end

    local roots = healthRoots(character, owner)
    local customHealth, healthSource, healthAttribute
    for _, root in ipairs(roots) do
        customHealth, healthSource, healthAttribute = readNumber(root, CURRENT_HEALTH_FIELDS)
        if customHealth ~= nil then
            break
        end
    end

    local health = customHealth ~= nil and customHealth or humanoid.Health
    if not validNumber(health) or health <= 0 then
        return nil
    end

    local maximum
    
    if customHealth ~= nil then
        for _, root in ipairs(roots) do
            if root == healthSource or (healthSource and healthSource.Parent == root) then
                maximum = readNumber(root, MAX_HEALTH_FIELDS)
                if maximum ~= nil then
                    break
                end
            end
        end
        if maximum == nil then
            for _, root in ipairs(roots) do
                maximum = readNumber(root, MAX_HEALTH_FIELDS)
                if maximum ~= nil then
                    break
                end
            end
        end
    end
    if maximum == nil then
        maximum = humanoid.MaxHealth
    end
    if not validNumber(maximum) or maximum <= 0 then
        maximum = health
    end

    return health, math.max(health, maximum), humanoid, healthSource, healthAttribute
end

Players.PlayerRemoving:Connect(function(otherPlayer)
    friendCache[otherPlayer.UserId] = nil
    if otherPlayer.Character == rotatingTargetCharacter then
        rotatingTargetCharacter = nil
    end
end)

local function getAttackOrigins(character)
    local root = getCharacterRoot(character)
    if not root or not root:IsA("BasePart") then
        return nil
    end

    local eye = root.Position + Vector3.new(0, 2.16, 0)
    local right = root.CFrame.RightVector
    return {
        eye,                               
        eye + right * 0.40,                
        eye - right * 0.40,
        eye + Vector3.new(0, -0.45, 0),   
        eye + Vector3.new(0, 0.30, 0),    
    }
end

local function getAimPoints(character, full)
    local points = {}
    for _, name in ipairs({"HumanoidRootPart", "UpperTorso", "Torso", "Head", "LowerTorso"}) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            points[#points + 1] = part.Position
            if full and (name == "Head" or name == "UpperTorso" or name == "Torso") then
                local x = math.min(part.Size.X * 0.36, 0.65)
                points[#points + 1] = part.CFrame:PointToWorldSpace(Vector3.new(-x, 0, 0))
                points[#points + 1] = part.CFrame:PointToWorldSpace(Vector3.new( x, 0, 0))
            end
        end
    end
    if #points == 0 then
        local root = getCharacterRoot(character)
        if root then points[#points + 1] = root.Position end
    end
    return points
end

local function findClearShot(localCharacter, targetCharacter, origins, budget, full)
    local points = getAimPoints(targetCharacter, full)
    if #points == 0 then
        return nil
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {localCharacter, targetCharacter}
    rayParams.IgnoreWater = true
    rayParams.RespectCanCollide = false 

    local originLimit = full and #origins or 1
    for i = 1, originLimit do
        local origin = origins[i]
        
        if i > 1 then
            if budget.remaining <= 0 then
                return nil
            end
            budget.remaining -= 1
            if Workspace:Raycast(origins[1], origin - origins[1], rayParams) then
                continue
            end
        end

        for _, aimPoint in ipairs(points) do
            local worldDirection = aimPoint - origin
            local distance = worldDirection.Magnitude
            if distance > 0.01 and distance <= maxScaledRange * 3 then
                if budget.remaining <= 0 then
                    return nil
                end
                budget.remaining -= 1
                if not Workspace:Raycast(origin, worldDirection, rayParams) then
                    return origin / 3, (worldDirection / 3).Unit
                end
            end
        end
    end
    return nil
end

local function orderedStartIndex(candidates, now)
    if targetPriority ~= "Lowest Health" or #candidates == 0 then
        return 1
    end

    local currentIndex
    for index, candidate in ipairs(candidates) do
        if candidate.character == rotatingTargetCharacter then
            currentIndex = index
            break
        end
    end

    if not currentIndex then
        rotatingTargetCharacter = nil
        return 1
    end
    if now - rotatingTargetSince >= TARGET_ROTATION_SECONDS then
        return (currentIndex % #candidates) + 1
    end
    return currentIndex
end

local function attackPriorityTarget()
    local now = os.clock()
    if attackInProgress or now < attackErrorRetryAt or now - lastAttack < cooldown then
        return
    end

    local character = player.Character
    local localHealth = character and getHealthInfo(character, player)
    if not localHealth then
        return
    end
    local localRoot = getCharacterRoot(character)
    local origins = getAttackOrigins(character)
    if not localRoot or not origins then
        return
    end

    local candidates = {}
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and canTargetPlayer(otherPlayer) then
            local targetCharacter = otherPlayer.Character
            local root = getCharacterRoot(targetCharacter)
            if root and root:IsA("BasePart") then
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance <= maxScaledRange * 3 + 3 then
                    local health = getHealthInfo(targetCharacter, otherPlayer)
                    if health then
                        candidates[#candidates + 1] = {
                            character = targetCharacter,
                            userId = otherPlayer.UserId,
                            distance = distance,
                            health = health,
                        }
                    end
                end
            end
        end
    end
    if #candidates == 0 then
        rotatingTargetCharacter = nil
        return
    end

    table.sort(candidates, function(a, b)
        if targetPriority == "Farthest" and a.distance ~= b.distance then
            return a.distance > b.distance
        elseif targetPriority == "Lowest Health" and a.health ~= b.health then
            return a.health < b.health
        elseif targetPriority == "Highest Health" and a.health ~= b.health then
            return a.health > b.health
        elseif targetPriority == "Closest" and a.distance ~= b.distance then
            return a.distance < b.distance
        end
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.userId < b.userId 
    end)

    local startIndex = orderedStartIndex(candidates, now)
    local budget = {remaining = MAX_RAYCASTS_PER_ATTACK}
    local chosen, chosenEye, chosenDirection

    for pass = 1, 2 do
        for offset = 0, #candidates - 1 do
            local idx = ((startIndex + offset - 1) % #candidates) + 1
            local candidate = candidates[idx]
            local eye, direction = findClearShot(character, candidate.character, origins, budget, pass == 2)
            if eye then
                chosen, chosenEye, chosenDirection = candidate, eye, direction
                break
            end
            if budget.remaining <= 0 then
                break
            end
        end
        if chosen or budget.remaining <= 0 then
            break
        end
    end
    if not chosen then
        return 
    end

    attackInProgress = true
    local ok, errorMessage = pcall(function()
        if swingRemote and swingRemote.Parent then
            swingRemote:FireServer()
        end
        attackRemote:FireServer(chosen.character, {
            sprint = false,
            charge = 1,
            vt = Workspace:GetServerTimeNow(),
            dir = chosenDirection,
            eye = chosenEye,
            t = Workspace.DistributedGameTime,
            crit = true,
            n = attackCount + 1,
        })
    end)
    attackInProgress = false

    if not ok then
        attackErrorRetryAt = now + 1.5 
        warn("[Fluent Aura] Attack remote failed: " .. tostring(errorMessage))
        return
    end

    if ok then
        lastAttack = now
        attackCount += 1
        if targetPriority == "Lowest Health" then
            if rotatingTargetCharacter ~= chosen.character then
                rotatingTargetCharacter = chosen.character
                rotatingTargetSince = now
            elseif now - rotatingTargetSince >= TARGET_ROTATION_SECONDS then
                
                rotatingTargetSince = now
            end
        end
    end
end

local KillAuraToggle = MainTab:AddToggle("KillAuraToggle", {
    Title = "Kill Aura",
    Description = "Attack visible nearby players with multi-angle raycasting.",
    Default = false,
})

KillAuraToggle:OnChanged(function(enabled)
    if auraConnection then
        auraConnection:Disconnect()
        auraConnection = nil
    end

    if enabled then
        lastAttack = -math.huge
        rotatingTargetCharacter = nil
        rotatingTargetSince = 0
        auraConnection = RunService.Heartbeat:Connect(attackPriorityTarget)
        attackPriorityTarget() 
    end
end)

local PriorityDropdown = MainTab:AddDropdown("KillAuraPriority", {
    Title = "Target Priority",
    Description = "Choose which in-range visible target to attack first.",
    Values = {"Closest", "Farthest", "Lowest Health", "Highest Health"},
    Multi = false,
    Default = 1,
})

PriorityDropdown:OnChanged(function(value)
    if value == "Closest" or value == "Farthest"
        or value == "Lowest Health" or value == "Highest Health" then
        targetPriority = value
        rotatingTargetCharacter = nil
        rotatingTargetSince = 0
    end
end)

local FriendCheckToggle = MainTab:AddToggle("KillAuraFriendCheck", {
    Title = "Friend Check",
    Description = "Ignore Roblox friends. Players are skipped until friendship is checked.",
    Default = true,
})

FriendCheckToggle:OnChanged(function(value)
    friendCheckEnabled = value
    if value then
        table.clear(friendCache)
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player then
                requestFriendStatus(otherPlayer)
            end
        end
    end
end)

if friendCheckEnabled then
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            requestFriendStatus(otherPlayer)
        end
    end
end

local espEnabled = false
local includeBots = false
local showDistance = true
local showHealth = true
local showName = true
local showBoxes = false
local boxStyle = "2D" 
local playerESPColor = Color3.fromRGB(100, 226, 255)
local botESPColor = Color3.fromRGB(255, 186, 83)

local function getESPColor(isBot)
    return isBot and botESPColor or playerESPColor
end

local espEntries = {}
local botCandidates = {}
local espHeartbeat = nil
local botAddedConnection = nil
local espContainer = nil
local espOverlay = nil
local espRenderConnection = nil
local espDrawAccumulator = 0

local function getESPPart(character)
    if not character or not character:IsA("Model") then
        return nil
    end

    return character:FindFirstChild("Head")
        or getCharacterRoot(character)
end

local function getLivingHumanoid(character)
    local _, _, humanoid = getHealthInfo(character, Players:GetPlayerFromCharacter(character))
    return humanoid
end

local function ensureESPOverlay()
    if espOverlay then
        return espOverlay
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "FluentESP_2DOverlay"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 4
    gui.Parent = player:WaitForChild("PlayerGui")
    espOverlay = gui
    return gui
end


local function make2DBox(isBot)
    local overlay = ensureESPOverlay()
    local color = getESPColor(isBot)

    local box = Instance.new("Frame")
    box.Name = "ESP2DBox"
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.ZIndex = 2
    box.Parent = overlay

    local shadow = Instance.new("UIStroke")
    shadow.Color = Color3.fromRGB(15, 15, 15)
    shadow.Thickness = 3.6
    shadow.Transparency = 0.2
    shadow.Parent = box

    local inner = Instance.new("Frame")
    inner.Name = "ColoredBorder"
    inner.BackgroundTransparency = 1
    inner.BorderSizePixel = 0
    inner.Size = UDim2.fromScale(1, 1)
    inner.ZIndex = 3
    inner.Parent = box

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 1.8
    stroke.Parent = inner
    return box
end

local function make3DBox(character, isBot)
    local box = Instance.new("SelectionBox")
    box.Name = "ESP3DBox"
    box.Adornee = character
    box.Color3 = getESPColor(isBot)
    box.LineThickness = 0.045
    box.SurfaceTransparency = 1
    box.Visible = false
    box.Parent = espContainer
    return box
end

local function getScreenBounds(character, camera, viewport)
    local boundsCFrame, size = character:GetBoundingBox()
    local half = size * 0.5
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local point = boundsCFrame:PointToWorldSpace(Vector3.new(
                    half.X * x, half.Y * y, half.Z * z
                ))
                local screen = camera:WorldToViewportPoint(point)
                if screen.Z <= 0 then
                    return nil
                end
                minX = math.min(minX, screen.X)
                minY = math.min(minY, screen.Y)
                maxX = math.max(maxX, screen.X)
                maxY = math.max(maxY, screen.Y)
            end
        end
    end

    if maxX < 0 or maxY < 0 or minX > viewport.X or minY > viewport.Y then
        return nil
    end

    minX = math.clamp(minX, 0, viewport.X)
    minY = math.clamp(minY, 0, viewport.Y)
    maxX = math.clamp(maxX, 0, viewport.X)
    maxY = math.clamp(maxY, 0, viewport.Y)

    if maxX - minX < 2 or maxY - minY < 2 then
        return nil
    end

    return minX, minY, maxX, maxY
end

local function updateESPGeometry()
    if not espEnabled or not showBoxes or boxStyle ~= "2D" then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    for character, entry in pairs(espEntries) do
        local box = entry.box2D
        if box then
            box.Visible = false
        end

        if box and getLivingHumanoid(character) then
            local success, minX, minY, maxX, maxY = pcall(getScreenBounds, character, camera, viewport)
            if not success then
                minX = nil 
            end
            if minX then
                box.Position = UDim2.fromOffset(minX, minY)
                box.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
                box.Visible = true
            end
        end
    end
end

local function updateBoxVisibility()
    local use2D = espEnabled and showBoxes and boxStyle == "2D"
    local use3D = espEnabled and showBoxes and boxStyle == "3D"

    for character, entry in pairs(espEntries) do
        if use2D and not entry.box2D then
            entry.box2D = make2DBox(entry.isBot)
        end
        if use3D and not entry.box3D then
            entry.box3D = make3DBox(character, entry.isBot)
        end
        if entry.box2D then
            entry.box2D.Visible = false 
        end
        if entry.box3D then
            entry.box3D.Visible = use3D
        end
    end

    if use2D then
        updateESPGeometry()
    end
end

local function removeESP(character)
    local entry = espEntries[character]
    if not entry then
        return
    end

    if entry.connections then
        for _, connection in ipairs(entry.connections) do
            connection:Disconnect()
        end
    end
    entry.gui:Destroy()
    entry.highlight:Destroy()
    if entry.box2D then
        entry.box2D:Destroy()
    end
    if entry.box3D then
        entry.box3D:Destroy()
    end
    espEntries[character] = nil
end

local function createESP(character, displayName, isBot, part)
    if not espContainer then
        espContainer = Instance.new("Folder")
        espContainer.Name = "FluentESP_Local"
        espContainer.Parent = Workspace
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = getESPColor(isBot)
    highlight.OutlineColor = getESPColor(isBot)
    highlight.FillTransparency = 0.80
    highlight.OutlineTransparency = 0
    highlight.Parent = espContainer

    local gui = Instance.new("BillboardGui")
    gui.Name = "ESPLabel"
    gui.Adornee = part
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.Size = UDim2.fromOffset(220, 82)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.7, 0)
    gui.MaxDistance = 5000
    gui.Parent = player:WaitForChild("PlayerGui")

    local label = Instance.new("TextLabel")
    label.Name = "Details"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.TextColor3 = getESPColor(isBot)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.15
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = gui

    local botTag = nil
    if isBot then
        gui.Size = UDim2.fromOffset(220, 108)
        botTag = Instance.new("TextLabel")
        botTag.Name = "BotTag"
        botTag.BackgroundTransparency = 1
        botTag.Position = UDim2.fromOffset(0, 0)
        botTag.Size = UDim2.new(1, 0, 0, 26)
        botTag.Text = "BOT"
        botTag.TextColor3 = getESPColor(true)
        botTag.TextStrokeColor3 = Color3.new(0, 0, 0)
        botTag.TextStrokeTransparency = 0.05
        botTag.Font = Enum.Font.GothamBlack
        botTag.TextSize = 18
        botTag.TextXAlignment = Enum.TextXAlignment.Center
        botTag.TextYAlignment = Enum.TextYAlignment.Center
        botTag.Parent = gui

        label.Position = UDim2.fromOffset(0, 26)
        label.Size = UDim2.new(1, 0, 1, -26)
    end

    local box2D = showBoxes and boxStyle == "2D" and make2DBox(isBot) or nil
    local box3D = showBoxes and boxStyle == "3D" and make3DBox(character, isBot) or nil
    if box3D then
        box3D.Visible = espEnabled
    end

    espEntries[character] = {
        box2D = box2D,
        box3D = box3D,
        gui = gui,
        label = label,
        botTag = botTag,
        highlight = highlight,
        name = displayName,
        isBot = isBot,
        connections = {},
    }

    local entry = espEntries[character]
    local humanoid = getRigHumanoid(character)
    if humanoid then
        entry.connections[#entry.connections + 1] = humanoid.Died:Connect(function()
            removeESP(character)
        end)
        entry.connections[#entry.connections + 1] = humanoid.HealthChanged:Connect(function()
            if not getHealthInfo(character, Players:GetPlayerFromCharacter(character)) then
                removeESP(character)
            end
        end)
    end
    entry.connections[#entry.connections + 1] = character.AncestryChanged:Connect(function()
        if not character:IsDescendantOf(Workspace) then
            removeESP(character)
        end
    end)
    local owner = Players:GetPlayerFromCharacter(character)
    if owner then
        entry.connections[#entry.connections + 1] = owner.CharacterRemoving:Connect(function(removed)
            if removed == character then
                removeESP(character)
            end
        end)
    end
    
    local _, _, _, healthSource, healthAttribute = getHealthInfo(character, owner)
    if healthSource then
        local signal
        if healthAttribute then
            signal = healthSource:GetAttributeChangedSignal(healthAttribute)
        elseif healthSource:IsA("NumberValue") or healthSource:IsA("IntValue") then
            signal = healthSource:GetPropertyChangedSignal("Value")
        end
        if signal then
            entry.connections[#entry.connections + 1] = signal:Connect(function()
                if not getHealthInfo(character, owner) then
                    removeESP(character)
                end
            end)
        end
    end
end

local function scanExistingBots()
    
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Humanoid") then
            local character = descendant.Parent
            if character and character:IsA("Model") and not Players:GetPlayerFromCharacter(character) then
                botCandidates[character] = true
            end
        end
    end
end

local function syncBotTracking()
    if botAddedConnection then
        botAddedConnection:Disconnect()
        botAddedConnection = nil
    end

    if not espEnabled or not includeBots then
        table.clear(botCandidates)
        return
    end

    scanExistingBots()
    botAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Humanoid") then
            local character = descendant.Parent
            if character and character:IsA("Model") and not Players:GetPlayerFromCharacter(character) then
                botCandidates[character] = true
            end
        end
    end)
end

local function refreshESPTargets()
    if not espEnabled then
        return
    end

    local wanted = {}

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local character = otherPlayer.Character
            if character and getLivingHumanoid(character) then
                local part = getESPPart(character)
                if part then
                    wanted[character] = {
                        name = otherPlayer.DisplayName,
                        isBot = false,
                        part = part,
                    }
                end
            end
        end
    end

    if includeBots then
        for character in pairs(botCandidates) do
            if not character:IsDescendantOf(Workspace) then
                botCandidates[character] = nil
            elseif character ~= player.Character and not Players:GetPlayerFromCharacter(character) then
                if getLivingHumanoid(character) then
                    local part = getESPPart(character)
                    if part then
                        wanted[character] = {
                            name = character.Name,
                            isBot = true,
                            part = part,
                        }
                    end
                end
            end
        end
    end

    for character in pairs(espEntries) do
        if not wanted[character] then
            removeESP(character)
        end
    end

    for character, target in pairs(wanted) do
        local entry = espEntries[character]
        if not entry then
            createESP(character, target.name, target.isBot, target.part)
        else
            entry.name = target.name
            entry.gui.Adornee = target.part
        end
    end
end

local function updateESPLabels()
    if not espEnabled then
        return
    end
    local localRoot = getCharacterRoot(player.Character)
    local localPosition = localRoot and localRoot.Position

    for character, entry in pairs(espEntries) do
        local owner = Players:GetPlayerFromCharacter(character)
        local health, maximum = getHealthInfo(character, owner)
        local part = getESPPart(character)
        if not health or not part then
            removeESP(character) 
        else
            local lines = {}
            if showName then
                lines[#lines + 1] = entry.name
            end
            if showHealth then
                lines[#lines + 1] = string.format("Health: %s / %s", tostring(math.floor(health + 0.5)), tostring(math.floor(maximum + 0.5)))
            end
            if showDistance and localPosition then
                local studs = (part.Position - localPosition).Magnitude
                lines[#lines + 1] = string.format("Distance: %d studs", math.floor(studs + 0.5))
            end
            entry.gui.Adornee = part
            entry.label.Text = table.concat(lines, "\n")
            entry.gui.Enabled = entry.isBot or #lines > 0
        end
    end
end

local function refreshESPColors()
    for _, entry in pairs(espEntries) do
        local color = getESPColor(entry.isBot)
        entry.highlight.FillColor = color
        entry.highlight.OutlineColor = color
        entry.label.TextColor3 = color

        if entry.botTag then
            entry.botTag.TextColor3 = color
        end
        if entry.box3D then
            entry.box3D.Color3 = color
        end
        if entry.box2D then
            local border = entry.box2D:FindFirstChild("ColoredBorder")
            local stroke = border and border:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = color
            end
        end
    end
end

local function stopESP()
    if espRenderConnection then
        espRenderConnection:Disconnect()
        espRenderConnection = nil
    end

    if espHeartbeat then
        espHeartbeat:Disconnect()
        espHeartbeat = nil
    end

    if botAddedConnection then
        botAddedConnection:Disconnect()
        botAddedConnection = nil
    end

    for character in pairs(espEntries) do
        removeESP(character)
    end

    table.clear(botCandidates)

    if espContainer then
        espContainer:Destroy()
        espContainer = nil
    end

    if espOverlay then
        espOverlay:Destroy()
        espOverlay = nil
    end
end

local ESPToggle = ESPTab:AddToggle("ESPToggle", {
    Title = "ESP",
    Description = "Highlight other players and show their details through walls.",
    Default = false,
})

local BoxesToggle = ESPTab:AddToggle("ESPShowBoxes", {
    Title = "ESP Boxes",
    Description = "Show an outline around each tracked character.",
    Default = false,
})

local BoxStyleDropdown = ESPTab:AddDropdown("ESPBoxStyle", {
    Title = "Box Style",
    Description = "2D screen outlines or 3D wireframe boxes.",
    Values = {"2D", "3D"},
    Multi = false,
    Default = 1,
})

local IncludeBotsToggle = ESPTab:AddToggle("ESPIncludeBots", {
    Title = "Include Bots",
    Description = "Also show NPCs with a Humanoid.",
    Default = false,
})

local PlayerColorPicker = ESPTab:AddColorpicker("ESPPlayerColor", {
    Title = "Player ESP Color",
    Description = "Color for player highlights, boxes, and text.",
    Default = playerESPColor,
})

local BotColorPicker = ESPTab:AddColorpicker("ESPBotColor", {
    Title = "Bot ESP Color",
    Description = "Color for NPC highlights, boxes, BOT tag, and text.",
    Default = botESPColor,
})

local DistanceToggle = ESPTab:AddToggle("ESPShowDistance", {
    Title = "Distance",
    Description = "Show distance in studs.",
    Default = true,
})

local HealthToggle = ESPTab:AddToggle("ESPShowHealth", {
    Title = "Health",
    Description = "Show current and maximum health.",
    Default = true,
})

local NameToggle = ESPTab:AddToggle("ESPShowName", {
    Title = "Name",
    Description = "Show player display names or bot names.",
    Default = true,
})

ESPToggle:OnChanged(function(value)
    espEnabled = value
    stopESP()

    if espEnabled then
        syncBotTracking()
        refreshESPTargets()
        updateESPLabels()
        updateBoxVisibility()
        espDrawAccumulator = 0
        espRenderConnection = RunService.RenderStepped:Connect(function(dt)
            if espEnabled and showBoxes and boxStyle == "2D" then
                espDrawAccumulator += dt
                if espDrawAccumulator >= 0.04 then
                    espDrawAccumulator = 0
                    updateESPGeometry()
                end
            end
        end)

        local refreshElapsed = 0
        local labelElapsed = 0
        espHeartbeat = RunService.Heartbeat:Connect(function(dt)
            refreshElapsed += dt
            labelElapsed += dt

            if refreshElapsed >= 0.45 then
                refreshElapsed = 0
                refreshESPTargets()
            end

            if labelElapsed >= 0.075 then
                labelElapsed = 0
                updateESPLabels()
            end
        end)
    end
end)

IncludeBotsToggle:OnChanged(function(value)
    includeBots = value
    if not value then
        for character, entry in pairs(espEntries) do
            if entry.isBot then
                removeESP(character)
            end
        end
    end
    syncBotTracking()
    refreshESPTargets()
    updateESPLabels()
end)

PlayerColorPicker:OnChanged(function()
    if typeof(PlayerColorPicker.Value) == "Color3" then
        playerESPColor = PlayerColorPicker.Value
        refreshESPColors()
    end
end)

BotColorPicker:OnChanged(function()
    if typeof(BotColorPicker.Value) == "Color3" then
        botESPColor = BotColorPicker.Value
        refreshESPColors()
    end
end)

DistanceToggle:OnChanged(function(value)
    showDistance = value
    updateESPLabels()
end)

HealthToggle:OnChanged(function(value)
    showHealth = value
    updateESPLabels()
end)

NameToggle:OnChanged(function(value)
    showName = value
    updateESPLabels()
end)

BoxesToggle:OnChanged(function(value)
    showBoxes = value
    updateBoxVisibility()
end)

BoxStyleDropdown:OnChanged(function(value)
    if value == "2D" or value == "3D" then
        boxStyle = value
        updateBoxVisibility()
    end
end)

local function initializeAutoFight()
    
    
    local autoFightEnabled = false
    local autoSprintEnabled = true
    local autoAvoidHoles = true
    local autoWaterEscape = true
    local autoApproachDistance = 10 
    local autoFightSession = 0
    local autoFightTarget = nil
    local autoTargetCheckAt = 0
    local autoUnreachableUntil = {}
    local autoStuckCount = 0
    local autoProgressAt = 0
    local autoProgressPosition = nil
    local steeringDirection = Vector3.zero
    local steeringJump = false
    local steeringHumanoid = nil
    local steeringController = nil
    local steeringTargetSide = 0
    local steerSideLockUntil = 0
    local lastSteerAt = 0
    local autoRenderBound = false
    local AUTO_RENDER_NAME = "FluentAutoFight_DirectSteer"
    local activeControls = nil
    local restoreControls = false

    local sprintInputHeld = false
    local sprintInputMethod = nil
    local fallbackSprintHumanoid = nil
    local fallbackOriginalSpeed = nil
    local fallbackAppliedSpeed = nil
    local lastSprintAttemptAt = 0
    local knownHumanoid = nil
    local auraWasEnabledBeforeAutoFight = false
    
    
    local navigationMode = "Auto" 
    local movementDriver = "keyboard"
    local movementDriverSince = 0
    local movementLastPosition = nil
    local movementLastCheck = 0
    local movementFailedAttempts = 0
    local lastMovementDiagnostic = 0
    local activeMoveKeys = {}
    local activeMoveRoot = nil
    local movementRenderConnection = nil
    local lastNavDiagnostic = 0
    local lastNoTargetDiagnostic = 0
    local lastBadRigDiagnostic = 0
    local autoLookAtTarget = true 
    local autoStuckRecovery = true
    local autoLookPart = nil
    local recoveryPhase = nil
    local recoveryUntil = 0
    local recoveryAttempt = 0
    local recoveryStart = 0
    local lastRecoverySide = 1
    local lastRecoveryLog = 0
    local detourWaypoints = {}
    local detourGoalPosition = nil
    local nextDetourAt = 0
    local lastRealMovement = 0
    local lastGoalProgressAt = 0
    local bestGoalDistance = math.huge
    local bestHeightGap = math.huge

    local function resetRouteState()
        recoveryPhase = nil
        recoveryUntil = 0
        recoveryAttempt = 0
        recoveryStart = 0
        bestGoalDistance = math.huge
        bestHeightGap = math.huge
        lastGoalProgressAt = os.clock()
        table.clear(detourWaypoints)
        detourGoalPosition = nil
        nextDetourAt = 0
        autoLookPart = nil
    end

    local function simulatedKey(code, isDown)
        local keyFunction = isDown and keypress or keyrelease
        if type(keyFunction) == "function" then
            local winVK = ({
                [Enum.KeyCode.W] = 0x57, [Enum.KeyCode.A] = 0x41,
                [Enum.KeyCode.S] = 0x53, [Enum.KeyCode.D] = 0x44,
                [Enum.KeyCode.Space] = 0x20,
            })[code] or code.Value
            local ok = pcall(keyFunction, winVK)
            if ok then return true end
        end
        local ok, virtualInput = pcall(function()
            return game:GetService("VirtualInputManager")
        end)
        if ok and virtualInput then
            return pcall(function()
                virtualInput:SendKeyEvent(isDown, code, false, game)
            end)
        end
        return false
    end

    local MOVE_KEYS = {
        W = Enum.KeyCode.W, A = Enum.KeyCode.A,
        S = Enum.KeyCode.S, D = Enum.KeyCode.D,
        Space = Enum.KeyCode.Space,
    }

    local function releaseMoveKeys()
        for key, held in pairs(activeMoveKeys) do
            if held then simulatedKey(MOVE_KEYS[key], false) end
            activeMoveKeys[key] = nil
        end
    end

    local function pressMoveKey(key, down)
        if (activeMoveKeys[key] == true) == down then return true end
        local ok = simulatedKey(MOVE_KEYS[key], down)
        if ok then activeMoveKeys[key] = down or nil end
        return ok
    end

    local function applyKeyboardSteering(direction, jump)
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        if forward.Magnitude < 0.001 then return false end
        forward = forward.Unit
        local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
        right = right.Magnitude > 0.01 and right.Unit or Vector3.new(-forward.Z,0,forward.X)
        local flat = Vector3.new(direction.X,0,direction.Z)
        local f = flat.Magnitude > 0.01 and flat.Unit:Dot(forward) or 0
        local r = flat.Magnitude > 0.01 and flat.Unit:Dot(right) or 0
        local success = true
        
        local wants = {W=f>0.35, S=f< -0.35, D=r>0.35, A=r< -0.35, Space=jump}
        for key, held in pairs(activeMoveKeys) do
            if held and not wants[key] then
                success = pressMoveKey(key, false) and success
            end
        end
        for key, wanted in pairs(wants) do
            if wanted and not activeMoveKeys[key] then
                success = pressMoveKey(key, true) and success
            end
        end
        return success
    end

    local function sendSprintKey(pressed)
        if type(keypress) == "function" and type(keyrelease) == "function" then
            local ok = pcall(function()
                if pressed then keypress(0x11) else keyrelease(0x11) end
            end)
            if ok then return "keypress" end
        end
        local serviceOK, virtualInput = pcall(function()
            return game:GetService("VirtualInputManager")
        end)
        if serviceOK and virtualInput then
            local ok = pcall(function()
                virtualInput:SendKeyEvent(pressed, Enum.KeyCode.LeftControl, false, game)
            end)
            if ok then return "virtual-input" end
        end
        return nil
    end

    local function releaseSprint()
        if sprintInputHeld then
            if sprintInputMethod == "keypress" and type(keyrelease) == "function" then
                pcall(function() keyrelease(0x11) end)
            elseif sprintInputMethod == "virtual-input" then
                pcall(function()
                    game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
                end)
            end
        end
        sprintInputHeld = false
        sprintInputMethod = nil
        if fallbackSprintHumanoid and fallbackSprintHumanoid.Parent
            and fallbackSprintHumanoid.WalkSpeed == fallbackAppliedSpeed then
            fallbackSprintHumanoid.WalkSpeed = fallbackOriginalSpeed
        end
        fallbackSprintHumanoid = nil
        fallbackOriginalSpeed = nil
        fallbackAppliedSpeed = nil
    end

    local function applySprint(humanoid)
        if not autoSprintEnabled then
            releaseSprint()
            return
        end
        if sprintInputHeld or (fallbackSprintHumanoid and fallbackSprintHumanoid == humanoid) then return end
        if os.clock() - lastSprintAttemptAt < 0.75 then return end
        lastSprintAttemptAt = os.clock()
        local method = sendSprintKey(true)
        if method then
            sprintInputHeld = true
            sprintInputMethod = method
        elseif humanoid and humanoid.Parent then
            fallbackSprintHumanoid = humanoid
            fallbackOriginalSpeed = humanoid.WalkSpeed
            fallbackAppliedSpeed = math.max(fallbackOriginalSpeed, 23)
            if fallbackAppliedSpeed > fallbackOriginalSpeed then
                humanoid.WalkSpeed = fallbackAppliedSpeed
            end
        end
    end

    local function acquireControls()
        
        
        local playerScripts = player:FindFirstChild("PlayerScripts")
        local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
        if not playerModule then return end
        local ok, controls = pcall(function()
            return require(playerModule):GetControls()
        end)
        if ok and controls then
            local wasEnabled = controls.controlsEnabled ~= false
            local disabled = pcall(function() controls:Disable() end)
            if disabled then
                activeControls = controls
                restoreControls = wasEnabled
            end
        end
    end

    local function releaseControls()
        if activeControls and restoreControls then
            pcall(function() activeControls:Enable() end)
        end
        activeControls = nil
        restoreControls = false
    end

    local function getMovableRoot(character, humanoid)
        if not character then return nil end
        local options = {}
        local seen = {}
        local function offer(part, priority)
            if not part or not part:IsA("BasePart") or seen[part] then return end
            seen[part] = true
            if not part:IsDescendantOf(Workspace) then return end
            if part.Anchored then priority -= 1000 end
            local assembly = part.AssemblyRootPart
            if assembly and not assembly.Anchored and assembly:IsDescendantOf(character) then
                part = assembly
                priority += 18
            end
            if part.Anchored then priority -= 1000 end
            if part.CanCollide then priority += 4 end
            if part.AssemblyMass > 0 then priority += 3 end
            if part.Name == "HumanoidRootPart" then priority += 12 end
            if part.Name == "CollisionRoot" or part.Name == "RootPart" then priority += 10 end
            options[#options+1] = {part=part, score=priority}
        end
        if humanoid then offer(humanoid.RootPart, 90) end
        if character:IsA("Model") then offer(character.PrimaryPart, 70) end
        for _, name in ipairs(ROOT_NAMES) do
            local found = character:FindFirstChild(name, true)
            if found and found:IsA("BasePart") then offer(found, 65) end
        end
        local camera = Workspace.CurrentCamera
        local cameraSubject = camera and camera.CameraSubject
        if cameraSubject and cameraSubject:IsA("BasePart")
            and cameraSubject:IsDescendantOf(character) then
            offer(cameraSubject, 85)
        end
        for _, obj in ipairs(character:GetDescendants()) do
            if obj:IsA("BasePart") and not obj.Anchored
                and not obj:FindFirstAncestorWhichIsA("Accessory") then
                offer(obj, obj.CanCollide and 30 or 15)
            end
        end
        table.sort(options, function(a, b) return a.score > b.score end)
        return options[1] and options[1].part or nil
    end

    local cachedRigCharacter = nil
    local cachedRigHumanoid = nil
    local cachedRigRoot = nil
    local cachedRigController = nil
    local cachedRigExpiration = 0
    local function getActiveLocalRig()
        local character = player.Character
        if not character then return nil end
        if cachedRigCharacter == character and os.clock() < cachedRigExpiration
            and cachedRigRoot and cachedRigRoot:IsDescendantOf(Workspace) then
            return character, cachedRigHumanoid, cachedRigRoot, cachedRigController
        end
        local humanoid = getRigHumanoid(character)
        local controller = character:FindFirstChildWhichIsA("ControllerManager", true)
        local root = getMovableRoot(character, humanoid)

        if (not root or root.Anchored) and Workspace.CurrentCamera then
            local subject = Workspace.CurrentCamera.CameraSubject
            local part = subject and (subject:IsA("BasePart") and subject
                or (subject:IsA("Humanoid") and subject.RootPart))
            if part and not part.Anchored and part:IsDescendantOf(Workspace) then
                local pawn = part:FindFirstAncestorWhichIsA("Model")
                if pawn and (part:IsDescendantOf(character)
                    or pawn.Name == player.Name or pawn.Name == player.DisplayName) then
                    root = part.AssemblyRootPart or part
                end
            end
        end
        cachedRigCharacter = character
        cachedRigHumanoid = humanoid
        cachedRigRoot = root
        cachedRigController = controller
        cachedRigExpiration = os.clock() + 0.8
        return character, humanoid, root, controller
    end

    local function setSteering(direction, humanoid, controller, jumping)
        steeringDirection = direction
        steeringHumanoid = humanoid
        steeringController = controller
        steeringJump = jumping or false
        lastSteerAt = os.clock()
    end

    local function clearSteering()
        steeringDirection = Vector3.zero
        steeringJump = false
        releaseMoveKeys()
        if steeringHumanoid and steeringHumanoid.Parent then
            pcall(function() steeringHumanoid:Move(Vector3.zero, false) end)
        end
        if steeringController and steeringController.Parent then
            pcall(function() steeringController.MovingDirection = Vector3.zero end)
        end
        if movementDriver == "physics" and activeMoveRoot
            and activeMoveRoot.Parent and not activeMoveRoot.Anchored then
            
            pcall(function()
                local velocity = activeMoveRoot.AssemblyLinearVelocity
                activeMoveRoot.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            end)
        end
    end

    local function chooseMovementDriver(mode)
        if movementDriver == mode then return end
        releaseMoveKeys()
        movementDriver = mode
        movementDriverSince = os.clock()
        movementLastCheck = os.clock()
        movementLastPosition = activeMoveRoot and activeMoveRoot.Position or nil
        movementFailedAttempts = 0
        print("[Fluent Aura] Auto Fight movement method: " .. mode)
    end

    local function applyDirectMovement(dt)
        if not autoFightEnabled then return end
        
        
        if autoLookAtTarget and autoLookPart and autoLookPart:IsDescendantOf(Workspace) then
            local camera = Workspace.CurrentCamera
            if camera then
                local viewPosition = camera.CFrame.Position
                local aimPosition = autoLookPart.Position + Vector3.new(0, 1.1, 0)
                if (aimPosition - viewPosition).Magnitude > 0.25 then
                    pcall(function()
                        camera.CFrame = CFrame.lookAt(viewPosition, aimPosition)
                    end)
                end
            end
        end
        local humanoid, controller, root = steeringHumanoid, steeringController, activeMoveRoot
        if not root or not root.Parent then
            releaseMoveKeys()
            return
        end
        local direction = (os.clock()-lastSteerAt < 0.4) and steeringDirection or Vector3.zero
        local moving = direction.Magnitude > 0.03
        if not moving then
            if movementDriver == "keyboard" and steeringJump then
                applyKeyboardSteering(Vector3.zero, true)
            else
                releaseMoveKeys()
            end
            if movementDriver == "native" and humanoid and humanoid.Parent then
                pcall(function() humanoid:Move(Vector3.zero, false) end)
            end
            return
        end
        if movementDriver == "keyboard" then
            if controller and controller.Parent and autoLookPart then
                local toTarget = autoLookPart.Position - root.Position
                toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
                if toTarget.Magnitude > 0.01 then
                    pcall(function() controller.FacingDirection = toTarget.Unit end)
                end
            end
            if not applyKeyboardSteering(direction, steeringJump) then
                
                if navigationMode == "Auto" and not root.Anchored then
                    chooseMovementDriver("physics")
                elseif os.clock() - lastBadRigDiagnostic > 5 then
                    lastBadRigDiagnostic = os.clock()
                    warn("[Fluent Aura] Auto Fight: simulated movement keys are unavailable. " ..
                        "This game may require its own native movement input interface.")
                end
            end
            return
        end
        if movementDriver == "physics" then
            
            
            for _, moveKey in ipairs({"W", "A", "S", "D"}) do
                pressMoveKey(moveKey, false)
            end
            pressMoveKey("Space", steeringJump)
            if root.Anchored then
                
                
                if navigationMode == "Auto" then chooseMovementDriver("keyboard") end
                return
            end
            
            
            local walkSpeed = (humanoid and humanoid.WalkSpeed > 0)
                and humanoid.WalkSpeed or 16
            local speed = math.clamp(walkSpeed, 9, 24)
            pcall(function()
                local oldVelocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(
                    direction.X * speed, oldVelocity.Y, direction.Z * speed)
            end)
            if steeringJump and humanoid then
                pcall(function() humanoid.Jump = true end)
            end
            return
        end
        
        
        if humanoid and humanoid.Parent then
            pcall(function() humanoid:Move(direction, false) end)
            if steeringJump then pcall(function() humanoid.Jump = true end) end
        end
        pcall(function() player:Move(direction, false) end)
        if controller and controller.Parent then
            pcall(function()
                controller.MovingDirection = direction
                controller.FacingDirection = direction.Unit
            end)
        end
    end

    local function bindMovement()
        if autoRenderBound then return end
        local ok, errorMessage = pcall(function()
            RunService:BindToRenderStep(AUTO_RENDER_NAME,
                Enum.RenderPriority.Character.Value + 10, applyDirectMovement)
        end)
        if ok then
            autoRenderBound = true
        else
            warn("[Fluent Aura] Auto Fight could not bind direct movement: " .. tostring(errorMessage))
            if not movementRenderConnection then
                movementRenderConnection = RunService.RenderStepped:Connect(applyDirectMovement)
            end
        end
    end

    local ledgeRayParams = RaycastParams.new()
    ledgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
    ledgeRayParams.IgnoreWater = false
    ledgeRayParams.RespectCanCollide = true
    local obstacleRayParams = RaycastParams.new()
    obstacleRayParams.FilterType = Enum.RaycastFilterType.Exclude
    obstacleRayParams.IgnoreWater = true
    obstacleRayParams.RespectCanCollide = true

    local function horizontalVector(vector)
        return Vector3.new(vector.X, 0, vector.Z)
    end

    local function rotateHeading(heading, angle)
        return CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(heading)
    end

    local function getSurfaceUnder(point, character, root)
        ledgeRayParams.FilterDescendantsInstances = {character}
        local up = math.max(5, root.Size.Y * 0.5 + 3)
        local depth = math.max(20, root.Size.Y + 16)
        local hit = Workspace:Raycast(point + Vector3.new(0, up, 0),
            Vector3.new(0, -depth, 0), ledgeRayParams)
        return hit and hit.Material ~= Enum.Material.Water and hit or nil
    end

    local function groundSafe(point, character, root, referenceSurface)
        if not autoAvoidHoles then return true end
        local hit = getSurfaceUnder(point, character, root)
        if not hit then return false end
        local delta = hit.Position.Y - referenceSurface
        local allowedDrop = math.clamp(root.Size.Y * 0.5 + 3, 3.5, 7)
        local allowedRise = math.clamp(root.Size.Y * 0.5 + 2, 2.5, 5)
        return delta >= -allowedDrop and delta <= allowedRise
    end

    local function clearForward(character, opponentCharacter, root, direction, distance)
        obstacleRayParams.FilterDescendantsInstances = opponentCharacter
            and {character, opponentCharacter} or {character}
        local origin = root.Position
        local side = root.CFrame.RightVector
        local radius = math.clamp(math.min(root.Size.X, root.Size.Z) * 0.35, 0.35, 1.1)
        for _, offset in ipairs({0, -radius, radius}) do
            local startPoint = origin + side * offset + Vector3.new(0, 0.55, 0)
            if Workspace:Raycast(startPoint, direction * distance, obstacleRayParams) then
                return false
            end
        end
        
        local shoulder = math.clamp(root.Size.Y * 0.4 + 1.5, 2, 4)
        return Workspace:Raycast(origin + Vector3.new(0, shoulder, 0),
            direction * distance, obstacleRayParams) == nil
    end

    local function directionIsSafe(character, targetCharacter, root, direction, lookAhead, floorY)
        if not clearForward(character, targetCharacter, root, direction, lookAhead) then
            return false
        end
        if not autoAvoidHoles then return true end
        
        local near = math.min(2.6, lookAhead)
        local mid = math.max(near, lookAhead * 0.60)
        return groundSafe(root.Position + direction * near, character, root, floorY)
            and groundSafe(root.Position + direction * mid, character, root, floorY)
            and groundSafe(root.Position + direction * lookAhead, character, root, floorY)
    end

    local function routeSegmentSafe(character, targetCharacter, root, position, direction, distance)
        if direction.Magnitude < 0.1 or distance < 0.1 then return false end
        obstacleRayParams.FilterDescendantsInstances = targetCharacter
            and {character, targetCharacter} or {character}
        local side = Vector3.new(-direction.Z, 0, direction.X)
        local halfWidth = math.clamp(math.min(root.Size.X, root.Size.Z) * 0.3, 0.35, 1.0)
        for _, sideways in ipairs({0, -halfWidth, halfWidth}) do
            local origin = position + side * sideways + Vector3.new(0, 1.0, 0)
            if Workspace:Raycast(origin, direction * distance, obstacleRayParams) then
                return false
            end
        end
        if Workspace:Raycast(position + Vector3.new(0, 2.8, 0),
            direction * distance, obstacleRayParams) then return false end
        if not autoAvoidHoles then return true end
        local surface = getSurfaceUnder(position, character, root)
        if not surface then return false end
        for _, fraction in ipairs({0.38, 0.72, 1}) do
            if not groundSafe(position + direction * (distance * fraction),
                character, root, surface.Position.Y) then return false end
        end
        return true
    end

    local ROUTE_ANGLES = {0, 32, -32, 62, -62, 90, -90, 125, -125, 180}
    local function calculateDetour(character, targetCharacter, root, goal)
        local start = root.Position
        local rootOffset = horizontalVector(goal - start)
        if rootOffset.Magnitude < 1 then return nil end
        local nodes = {{position=start, cost=0, first=nil, previous=nil}}
        local bestNode, bestScore = nil, math.huge
        local stepLength = math.clamp(rootOffset.Magnitude * 0.26, 4.5, 6.2)
        for depth = 1, 3 do
            local candidates = {}
            local seen = {}
            for _, node in ipairs(nodes) do
                local toward = horizontalVector(goal - node.position)
                if toward.Magnitude > 0.1 then
                    toward = toward.Unit
                    for _, angle in ipairs(ROUTE_ANGLES) do
                        local heading = rotateHeading(toward, math.rad(angle))
                        if routeSegmentSafe(character, targetCharacter, root,
                            node.position, heading, stepLength) then
                            local position = node.position + heading * stepLength
                            local key = math.floor(position.X / 3 + 0.5) .. ":" ..
                                math.floor(position.Z / 3 + 0.5)
                            if not seen[key] and horizontalVector(position-start).Magnitude > 2 then
                                seen[key] = true
                                local goalDistance = horizontalVector(goal-position).Magnitude
                                local moveAwayPenalty = math.max(0, goalDistance - rootOffset.Magnitude) * 0.8
                                local pathCost = node.cost + stepLength + math.abs(angle) / 95 + moveAwayPenalty
                                local exitDirection = horizontalVector(goal-position)
                                local hasClearExit = goalDistance > 0.2 and goalDistance < 13
                                    and routeSegmentSafe(character, targetCharacter, root,
                                        position, exitDirection.Unit,
                                        math.max(0.2, goalDistance - autoApproachDistance * 0.5))
                                local score = pathCost + goalDistance - (hasClearExit and 13 or 0)
                                local nextNode = {
                                    position=position, cost=pathCost, previous=node,
                                    first=node.first or position, score=score,
                                }
                                candidates[#candidates+1] = nextNode
                                if score < bestScore then
                                    bestNode, bestScore = nextNode, score
                                end
                            end
                        end
                    end
                end
            end
            if #candidates == 0 then break end
            table.sort(candidates, function(a,b) return a.score < b.score end)
            nodes = {}
            for index=1,math.min(3,#candidates) do nodes[index] = candidates[index] end
            if bestNode and bestScore < stepLength * depth + 6 then break end
        end
        if not bestNode then return nil end
        local points = {}
        local current = bestNode
        while current and current.previous do
            table.insert(points, 1, current.position)
            current = current.previous
        end
        return points
    end

    local function refreshDetour(character, targetCharacter, root, goal, now)
        if now < nextDetourAt then return end
        nextDetourAt = now + 1.25
        local points = calculateDetour(character, targetCharacter, root, goal)
        table.clear(detourWaypoints)
        if points then
            for _, point in ipairs(points) do
                detourWaypoints[#detourWaypoints+1] = point
            end
            detourGoalPosition = goal
            if now-lastRecoveryLog > 3 then
                lastRecoveryLog = now
                print("[Fluent Aura] Auto Fight: recomputed local route (" ..
                    tostring(#points) .. " waypoints).")
            end
        end
    end

    local function nextDetourWaypoint(character, targetCharacter, root, goal, now)
        if detourGoalPosition and horizontalVector(goal-detourGoalPosition).Magnitude > 12 then
            table.clear(detourWaypoints)
            detourGoalPosition = nil
            nextDetourAt = 0
        end
        while #detourWaypoints > 0
            and horizontalVector(root.Position - detourWaypoints[1]).Magnitude < 2.0 do
            table.remove(detourWaypoints, 1)
        end
        if #detourWaypoints == 0 then return nil end
        local waypoint = detourWaypoints[1]
        local offset = horizontalVector(waypoint - root.Position)
        if offset.Magnitude < 0.1 then return nil end
        if not routeSegmentSafe(character, targetCharacter, root, root.Position,
            offset.Unit, math.min(offset.Magnitude, 6)) then
            table.clear(detourWaypoints)
            nextDetourAt = 0
            return nil
        end
        return waypoint
    end

    local RECOVERY_PHASES = {
        {name="jump", duration=0.76},
        {name="left", duration=0.75},
        {name="right", duration=0.80},
        {name="reverse", duration=0.60},
        {name="repath", duration=0.45},
    }
    local function beginRecovery(now)
        if not autoStuckRecovery then return end
        recoveryAttempt += 1
        recoveryStart = now
        recoveryPhase = 1
        recoveryUntil = now + RECOVERY_PHASES[1].duration
        table.clear(detourWaypoints)
        detourGoalPosition = nil
        nextDetourAt = 0
        if now-lastRecoveryLog > 2 then
            lastRecoveryLog = now
            print("[Fluent Aura] Auto Fight stuck: trying jump, left/right, " ..
                "backward, and local repathing.")
        end
    end

    local function nextRecoveryPhase(now)
        if not recoveryPhase then return end
        recoveryPhase += 1
        if recoveryPhase > #RECOVERY_PHASES then
            recoveryPhase = nil
            return
        end
        recoveryUntil = now + RECOVERY_PHASES[recoveryPhase].duration
    end

    local function recoveryDirection(character, targetCharacter, root, goal, now)
        if not recoveryPhase then return nil end
        if now >= recoveryUntil then nextRecoveryPhase(now) end
        if not recoveryPhase then return nil end
        local phase = RECOVERY_PHASES[recoveryPhase].name
        local offset = horizontalVector(goal-root.Position)
        if offset.Magnitude < 0.1 then return Vector3.zero, false end
        local toward = offset.Unit
        if phase == "repath" then
            refreshDetour(character, targetCharacter, root, goal, now)
            local waypoint = nextDetourWaypoint(character, targetCharacter, root, goal, now)
            if waypoint then
                local path = horizontalVector(waypoint-root.Position)
                if path.Magnitude > 0.01 then return path.Unit, false end
            end
            return Vector3.zero, false
        end
        if phase == "jump" then
            
            
            if routeSegmentSafe(character, targetCharacter, root,
                root.Position, toward, 2.3) then
                return toward, true
            end
            return Vector3.zero, true
        end
        local turn = (phase == "left" and 90)
            or (phase == "right" and -90) or 180
        local candidate = rotateHeading(toward, math.rad(turn * lastRecoverySide))
        local reference = getSurfaceUnder(root.Position, character, root)
        if reference and directionIsSafe(character, targetCharacter, root,
            candidate, 3.2, reference.Position.Y) then
            return candidate, false
        end
        return Vector3.zero, false
    end

    local climbLastProbeAt = 0
    local climbLastGoal = nil
    local climbCachedDirection = nil
    local climbCachedJump = false
    local function findClimbStep(character, targetCharacter, root, humanoid, goal, now)
        local riseToTarget = goal.Y - root.Position.Y
        if riseToTarget < 2.0 then
            climbCachedDirection = nil
            return nil, false
        end
        if now - climbLastProbeAt < 0.30 and climbLastGoal
            and (goal - climbLastGoal).Magnitude < 2.5 then
            return climbCachedDirection, climbCachedJump
        end
        climbLastGoal = goal
        climbLastProbeAt = now
        climbCachedDirection, climbCachedJump = nil, false
        local currentSurface = getSurfaceUnder(root.Position, character, root)
        if not currentSurface then return nil, false end
        local baseY = currentSurface.Position.Y
        local maxRise = 8.0
        if humanoid then
            local estimate = humanoid.UseJumpPower
                and (humanoid.JumpPower * humanoid.JumpPower
                    / math.max(Workspace.Gravity * 2, 1))
                or humanoid.JumpHeight
            if type(estimate) == "number" and estimate > 0 then
                maxRise = math.clamp(estimate + 0.75, 4.5, 12)
            end
        end
        local forward = horizontalVector(goal - root.Position)
        if forward.Magnitude < 0.05 then return nil, false end
        forward = forward.Unit
        ledgeRayParams.FilterDescendantsInstances = {character, targetCharacter}
        obstacleRayParams.FilterDescendantsInstances = {character, targetCharacter}
        local best, bestScore, bestNear = nil, -math.huge, false
        for _, degree in ipairs({0, 30, -30, 55, -55, 85, -85}) do
            local direction = rotateHeading(forward, math.rad(degree))
            for _, sampleDistance in ipairs({2.5, 4.25, 5.75}) do
                local sample = root.Position + direction * sampleDistance
                local probeFrom = Vector3.new(sample.X, baseY + maxRise + 3, sample.Z)
                local landing = Workspace:Raycast(probeFrom,
                    Vector3.new(0, -(maxRise + 9), 0), ledgeRayParams)
                if landing and landing.Material ~= Enum.Material.Water
                    and landing.Normal.Y >= 0.70 then
                    local rise = landing.Position.Y - baseY
                    if rise >= 1.25 and rise <= maxRise then
                        
                        local upperStart = Vector3.new(root.Position.X,
                            landing.Position.Y + math.max(1.4, root.Size.Y * 0.35), root.Position.Z)
                        local blockedAtTop = Workspace:Raycast(upperStart,
                            direction * sampleDistance, obstacleRayParams)
                        if not blockedAtTop then
                            local score = rise * 1.3 - math.abs(degree) * 0.06
                                - sampleDistance * 0.2
                            if score > bestScore then
                                best = direction
                                bestScore = score
                                bestNear = sampleDistance <= 4.5
                            end
                        end
                    end
                end
            end
        end
        if best then
            climbCachedDirection = best
            climbCachedJump = bestNear
            return best, bestNear
        end
        return nil, false
    end

    local function findSteeringDirection(character, targetCharacter, root, goal, now)
        local flat = horizontalVector(goal - root.Position)
        if flat.Magnitude <= 0.15 then return Vector3.zero, false end
        local desired = flat.Unit
        local reference = getSurfaceUnder(root.Position, character, root)

        if autoAvoidHoles and not reference then
            for _, offset in ipairs({0, 25, -25, 60, -60}) do
                local candidate = rotateHeading(desired, math.rad(offset))
                if clearForward(character, targetCharacter, root, candidate, 3.0) then
                    return candidate, false
                end
            end
            return Vector3.zero, false
        end
        local floorY = reference and reference.Position.Y or root.Position.Y - 3
        local lookAhead = math.clamp(flat.Magnitude, 3.5, 7.5)

        if directionIsSafe(character, targetCharacter, root, desired, lookAhead, floorY) then
            steeringTargetSide = 0
            return desired, false
        end

        local best, bestScore, bestSide
        local angles = {20, -20, 42, -42, 65, -65, 90, -90, 120, -120, 150, -150, 180}
        for _, degrees in ipairs(angles) do
            local radians = math.rad(degrees)
            local direction = rotateHeading(desired, radians)
            if directionIsSafe(character, targetCharacter, root, direction, 5.0, floorY) then
                local side = degrees >= 0 and 1 or -1
                local score = direction:Dot(desired) * 3 - math.abs(degrees) / 180
                if steeringTargetSide == side and now < steerSideLockUntil then
                    score += 1.6 
                end
                if not bestScore or score > bestScore then
                    bestScore, best, bestSide = score, direction, side
                end
            end
        end
        if best then
            steeringTargetSide = bestSide
            steerSideLockUntil = now + 1.3
            return best, false
        end

        
        if groundSafe(root.Position + desired * 3.5, character, root, floorY) then
            obstacleRayParams.FilterDescendantsInstances = {character, targetCharacter}
            local highOrigin = root.Position + Vector3.new(0, 3.5, 0)
            if Workspace:Raycast(highOrigin, desired * 3, obstacleRayParams) == nil then
                return desired, true
            end
        end
        return Vector3.zero, false
    end

    local function canFightTarget(otherPlayer)
        if otherPlayer == player or not otherPlayer.Parent or not canTargetPlayer(otherPlayer) then
            return false
        end
        local character = otherPlayer.Character
        if not character or not character:IsDescendantOf(Workspace)
            or character:GetAttribute("Dead") == true
            or character:GetAttribute("IsDead") == true then
            return false
        end
        if not getCharacterRoot(character) then return false end
        
        
        local humanoid = getRigHumanoid(character)
        if not humanoid then return true end
        return humanoid:GetState() ~= Enum.HumanoidStateType.Dead
            and getHealthInfo(character, otherPlayer) ~= nil
    end

    local function getClosestAutoFightTarget(localPosition)
        local best, bestDistance = nil, math.huge
        local now = os.clock()
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if (autoUnreachableUntil[otherPlayer.UserId] or 0) <= now
                and canFightTarget(otherPlayer) then
                local theirRoot = getCharacterRoot(otherPlayer.Character)
                local distance = (theirRoot.Position - localPosition).Magnitude
                if distance < bestDistance then
                    best, bestDistance = otherPlayer, distance
                end
            end
        end
        return best, bestDistance
    end

    local function resetAutoTarget()
        autoFightTarget = nil
        autoStuckCount = 0
        autoProgressPosition = nil
        steeringTargetSide = 0
        resetRouteState()
        clearSteering()
    end

    local function giveUpCurrentTarget()
        if autoFightTarget then
            autoUnreachableUntil[autoFightTarget.UserId] = os.clock() + 4
        end
        resetAutoTarget()
    end

    local swimShorePosition = nil
    local nextSwimSearchAt = 0
    local function findShore(root, character, targetPosition)
        ledgeRayParams.FilterDescendantsInstances = {character}
        local toward = horizontalVector(targetPosition - root.Position)
        toward = toward.Magnitude > 0.01 and toward.Unit or Vector3.xAxis
        local favorite, bestScore
        for _, radius in ipairs({6, 11, 17}) do
            for index = 0, 11 do
                local angle = index * math.pi / 6
                local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
                local point = root.Position + direction * radius
                local hit = Workspace:Raycast(point + Vector3.new(0, 8, 0),
                    Vector3.new(0, -19, 0), ledgeRayParams)
                if hit and hit.Material ~= Enum.Material.Water
                    and hit.Position.Y >= root.Position.Y - 6
                    and hit.Position.Y <= root.Position.Y + 7 then
                    local score = radius - direction:Dot(toward) * 4
                    if not bestScore or score < bestScore then
                        bestScore = score
                        favorite = hit.Position + Vector3.new(0, 2, 0)
                    end
                end
            end
        end
        return favorite
    end

    local function autoFightStep()
        local character, humanoid, root, controller = getActiveLocalRig()
        if not character or not root then
            clearSteering()
            releaseSprint()
            resetAutoTarget()
            if os.clock() - lastBadRigDiagnostic > 5 then
                lastBadRigDiagnostic = os.clock()
                warn("[Fluent Aura] Auto Fight: no movable character root found. " ..
                    "Character=" .. tostring(character and character:GetFullName()) ..
                    "; custom server-controlled rigs may require game-specific movement.")
            end
            return
        end
        if root ~= activeMoveRoot then
            releaseMoveKeys()
            activeMoveRoot = root
            movementLastPosition = root.Position
            movementLastCheck = os.clock()
            movementDriverSince = os.clock()
            if navigationMode == "Input Keys" then movementDriver = "keyboard"
            elseif navigationMode == "Physics" then movementDriver = "physics"
            elseif navigationMode == "Native" then movementDriver = "native"
            else movementDriver = "keyboard" end
            print("[Fluent Aura] Auto Fight rig: " .. root:GetFullName() ..
                ", anchored=" .. tostring(root.Anchored) ..
                ", humanoid=" .. tostring(humanoid ~= nil) ..
                ", controller=" .. tostring(controller ~= nil))
        end
        if knownHumanoid ~= humanoid then
            releaseSprint()
            knownHumanoid = humanoid
            
            movementLastCheck = os.clock()
        end
        if root.Anchored and os.clock()-lastBadRigDiagnostic > 5 then
            lastBadRigDiagnostic = os.clock()
            warn("[Fluent Aura] Auto Fight: anchored custom root; " ..
                "only a game's native movement controller or simulated input can move it: " ..
                root:GetFullName())
            if navigationMode == "Auto" and movementDriver == "native" then
                chooseMovementDriver("keyboard")
            end
        end
        applySprint(humanoid)
        if not KillAuraToggle.Value then KillAuraToggle:SetValue(true) end

        local now = os.clock()
        if not autoFightTarget or not canFightTarget(autoFightTarget)
            or (autoUnreachableUntil[autoFightTarget.UserId] or 0) > now then
            resetAutoTarget()
        end
        if now >= autoTargetCheckAt then
            autoTargetCheckAt = now + 0.35
            local closest, distance = getClosestAutoFightTarget(root.Position)
            if closest then
                if not autoFightTarget then
                    autoFightTarget = closest
                else
                    local oldRoot = getCharacterRoot(autoFightTarget.Character)
                    local oldDistance = oldRoot and (oldRoot.Position - root.Position).Magnitude or math.huge
                    if closest ~= autoFightTarget and distance < oldDistance * 0.65 then
                        autoFightTarget = closest
                        resetRouteState()
                    end
                end
            end
        end
        local targetRoot = autoFightTarget and getCharacterRoot(autoFightTarget.Character)
        if not targetRoot then
            autoLookPart = nil
            setSteering(Vector3.zero, humanoid, controller, false)
            if now - lastNoTargetDiagnostic > 8 then
                lastNoTargetDiagnostic = now
                print("[Fluent Aura] Auto Fight: no eligible alive player to chase (friend check and health filters still apply).")
            end
            return
        end
        local targetPos = targetRoot.Position
        autoLookPart = targetRoot
        local delta = horizontalVector(targetPos - root.Position)
        local distance = delta.Magnitude
        if bestGoalDistance == math.huge then
            bestGoalDistance = distance
            lastGoalProgressAt = now
        elseif distance < bestGoalDistance - 0.9 then
            bestGoalDistance = distance
            lastGoalProgressAt = now
        end
        
        
        local remainingRise = math.max(0, targetPos.Y - root.Position.Y)
        if remainingRise < bestHeightGap - 0.8 then
            bestHeightGap = remainingRise
            lastGoalProgressAt = now
        end

        if autoWaterEscape and humanoid
            and humanoid:GetState() == Enum.HumanoidStateType.Swimming then
            if now >= nextSwimSearchAt then
                swimShorePosition = findShore(root, character, targetPos)
                nextSwimSearchAt = now + 1.1
            end
            local toward = (swimShorePosition or targetPos) - root.Position
            local swimVector = Vector3.new(toward.X, math.max(0.85, toward.Y), toward.Z)
            setSteering(swimVector.Magnitude > 0.01 and swimVector.Unit or Vector3.yAxis,
                humanoid, controller, true)
            return
        end
        swimShorePosition = nil
        nextSwimSearchAt = 0

        
        obstacleRayParams.FilterDescendantsInstances = {character, autoFightTarget.Character}
        local directSight = Workspace:Raycast(
            root.Position + Vector3.new(0, 1.2, 0),
            targetPos - root.Position, obstacleRayParams) == nil
        
        local heightGap = targetPos.Y - root.Position.Y
        if distance <= autoApproachDistance and directSight and heightGap < 2.25 then
            setSteering(Vector3.zero, humanoid, controller, false)
            autoProgressPosition = root.Position
            autoProgressAt = now
            recoveryPhase = nil
            bestGoalDistance = distance
            lastGoalProgressAt = now
            table.clear(detourWaypoints)
            return
        end
        local approachGoal = targetPos
        if distance > autoApproachDistance + 1 then
            approachGoal = targetPos - delta.Unit * math.max(2, autoApproachDistance - 2)
        end

        local direction, jump = findClimbStep(character,
            autoFightTarget.Character, root, humanoid, targetPos, now)
        if direction then
            recoveryPhase = nil
            table.clear(detourWaypoints)
        else
            direction, jump = recoveryDirection(
                character, autoFightTarget.Character, root, approachGoal, now)
        end
        if not direction then
            local waypoint = nextDetourWaypoint(character, autoFightTarget.Character,
                root, approachGoal, now)
            if waypoint then
                local towardWaypoint = horizontalVector(waypoint-root.Position)
                direction, jump = towardWaypoint.Magnitude > 0.01 and towardWaypoint.Unit
                    or Vector3.zero, false
            else
                direction, jump = findSteeringDirection(
                    character, autoFightTarget.Character, root, approachGoal, now)
                if direction.Magnitude < 0.02 then
                    refreshDetour(character, autoFightTarget.Character, root, approachGoal, now)
                    waypoint = nextDetourWaypoint(character, autoFightTarget.Character,
                        root, approachGoal, now)
                    if waypoint then
                        local toWaypoint = horizontalVector(waypoint-root.Position)
                        direction = toWaypoint.Magnitude > 0.01 and toWaypoint.Unit or Vector3.zero
                    elseif not recoveryPhase and autoStuckRecovery then
                        beginRecovery(now)
                        direction, jump = recoveryDirection(character,
                            autoFightTarget.Character, root, approachGoal, now)
                    end
                end
            end
        end
        setSteering(direction or Vector3.zero, humanoid, controller, jump)
        if (not direction or direction.Magnitude < 0.05) and now - lastNavDiagnostic > 7 then
            lastNavDiagnostic = now
            print("[Fluent Aura] Auto Fight: no safe direction found. " ..
                "Try turning off Avoid Holes temporarily to check whether " ..
                "this custom rig has a nonstandard ground collider.")
        end

        if navigationMode == "Auto" and direction and direction.Magnitude > 0.15
            and distance > autoApproachDistance + 1 then
            if not movementLastPosition then
                movementLastPosition = root.Position
                movementLastCheck = now
            elseif now - movementLastCheck > 1.20 then
                local advanced = horizontalVector(root.Position - movementLastPosition).Magnitude
                movementLastPosition = root.Position
                movementLastCheck = now
                if advanced < 0.5 then
                    movementFailedAttempts += 1
                    if movementDriver == "native" then
                        chooseMovementDriver("keyboard")
                    elseif movementDriver == "keyboard" and not root.Anchored then
                        chooseMovementDriver("physics")
                    elseif movementDriver == "physics" and now-lastMovementDiagnostic > 5 then
                        lastMovementDiagnostic = now
                        warn("[Fluent Aura] Auto Fight: native, simulated keys, and assembly steering " ..
                            "have not moved the model. Root=" .. root:GetFullName() ..
                            "; anchored=" .. tostring(root.Anchored) ..
                            "; assembly speed=" .. string.format("%.2f",root.AssemblyLinearVelocity.Magnitude) ..
                            ". If server-controlled, send this F9 message and the game's movement setup.")
                    end
                else
                    movementFailedAttempts = 0
                end
            end
        else
            movementLastPosition = root.Position
            movementLastCheck = now
        end

        if now - lastGoalProgressAt > 5.0 and not recoveryPhase
            and distance > autoApproachDistance + 1 and autoStuckRecovery then
            lastRecoverySide *= -1
            beginRecovery(now)
            bestGoalDistance = distance
            lastGoalProgressAt = now
        end

        if not autoProgressPosition then
            autoProgressPosition = root.Position
            autoProgressAt = now
        elseif now - autoProgressAt >= 0.90 then
            local displacement = root.Position - autoProgressPosition
            local travel = horizontalVector(displacement).Magnitude
            local climbed = displacement.Y >= 1.0
            autoProgressPosition = root.Position
            autoProgressAt = now
            if travel >= 0.75 or climbed then
                autoStuckCount = 0
                lastRealMovement = now
                
                
                recoveryPhase = nil
            elseif distance > autoApproachDistance + 1 then
                autoStuckCount += 1
                if not recoveryPhase and autoStuckRecovery then
                    lastRecoverySide *= -1
                    beginRecovery(now)
                end
                if autoStuckCount >= 11 then
                    if now-lastRecoveryLog > 2 then
                        lastRecoveryLog = now
                        warn("[Fluent Aura] Auto Fight: character never advanced. " ..
                            "Check F9 for input restrictions or a server-controlled custom rig.")
                    end
                    giveUpCurrentTarget()
                end
            end
        end
    end

    local function stopAutoFight()
        autoFightEnabled = false
        autoFightSession += 1
        clearSteering()
        if autoRenderBound then
            RunService:UnbindFromRenderStep(AUTO_RENDER_NAME)
            autoRenderBound = false
        end
        if movementRenderConnection then
            movementRenderConnection:Disconnect()
            movementRenderConnection = nil
        end
        releaseControls()
        releaseMoveKeys()
        releaseSprint()
        activeMoveRoot = nil
        movementLastPosition = nil
        knownHumanoid = nil
        resetAutoTarget()
        lastSprintAttemptAt = 0
        table.clear(autoUnreachableUntil)
        if not auraWasEnabledBeforeAutoFight and KillAuraToggle.Value then
            KillAuraToggle:SetValue(false)
        end
    end

    local AutoFightToggle = MainTab:AddToggle("AutoFightToggle", {
        Title = "Auto Fight [BETA]",
        Description = "All features enabled: target pursuit, instant look, jump climbing, sprint, obstacle/ledge avoidance, recovery and repathing.",
        Default = false,
    })

    AutoFightToggle:OnChanged(function(enabled)
        if not enabled then
            stopAutoFight()
            return
        end
        if autoFightEnabled then return end
        autoFightEnabled = true
        autoFightSession += 1
        local session = autoFightSession
        auraWasEnabledBeforeAutoFight = KillAuraToggle.Value == true
        autoTargetCheckAt = 0
        lastSprintAttemptAt = 0
        resetAutoTarget()
        activeMoveRoot = nil
        movementLastCheck = 0
        movementLastPosition = nil
        navigationMode = "Auto"
        chooseMovementDriver("keyboard")
        bindMovement()
        if not KillAuraToggle.Value then KillAuraToggle:SetValue(true) end
        task.spawn(function()
            while autoFightEnabled and autoFightSession == session do
                local ok, message = pcall(autoFightStep)
                if not ok then
                    warn("[Fluent Aura] Auto Fight navigation error: " .. tostring(message))
                    task.wait(0.5)
                else
                    task.wait(0.10)
                end
            end
        end)
    end)

    
    player.CharacterRemoving:Connect(function()
        releaseSprint()
        releaseMoveKeys()
        activeMoveRoot = nil
        movementLastPosition = nil
        knownHumanoid = nil
        resetAutoTarget()
    end)

end

initializeAutoFight()

Window:SelectTab(1)