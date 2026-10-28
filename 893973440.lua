local REQUIRED_PLACE_ID = 893973440

if game.PlaceId ~= REQUIRED_PLACE_ID then

    print(string.format("[Afright Scripts] Wrong game! Expected PlaceId %s; current PlaceId %s.", tostring(REQUIRED_PLACE_ID), tostring(game.PlaceId)))

    return

end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarterGui = game:GetService("StarterGui")

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")

local lp = Players.LocalPlayer

local BEAST_COLOR = Color3.fromRGB(255, 40, 60)

local PLAYER_COLOR = Color3.fromRGB(0, 255, 0)

local COMPUTER_COLOR = Color3.fromRGB(30, 80, 230)

local COMPUTER_DONE = Color3.fromRGB(120, 120, 130)

local POD_COLOR = Color3.fromRGB(120, 240, 255)

local DOOR_OPEN = Color3.fromRGB(0, 255, 0)

local DOOR_CLOSED = Color3.fromRGB(255, 0, 0)

local EXIT_COLOR = Color3.fromRGB(255, 255, 0)

local ARROW_MARGIN = 60

local CRAWL_HEIGHT = 0.9

local CRAWL_ANIM_REF_SPEED = 8

local CRAWL_SPEED = 8

local THIRD_PERSON_MIN_ZOOM = 0.5

local THIRD_PERSON_MAX_ZOOM = 40

local THIRD_PERSON_START_ZOOM = 12

local LIGHT_BRIGHTNESS = 0.8

local LIGHT_RANGE = 45

local LIGHT_COLOR = Color3.fromRGB(255, 244, 225)

local flags = {

    Players = false,

    Computers = false,

    Pods = false,

    Doors = false,

    ExitDoors = false,

    BeastAlert = false,

    ThirdPerson = false,

    Light = false,

    NoFail = false,

}

local running = true

local currentBeast = nil

local function rs(name)

    local v = ReplicatedStorage:FindFirstChild(name)

    return v and v.Value

end

local function stat(plr, name)

    local folder = plr:FindFirstChild("TempPlayerStatsModule", true)

    local v = folder and folder:FindFirstChild(name)

    return v and v.Value

end

local function notify(title, text, duration)

    pcall(function()

        StarterGui:SetCore("SendNotification", {

            Title = title,

            Text = text,

            Duration = duration or 6,

        })

    end)

end

local function makeHighlight(adornee, name)

    local hl = Instance.new("Highlight")

    hl.Name = name

    hl.FillTransparency = 0.6

    hl.OutlineTransparency = 0

    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    hl.Adornee = adornee

    hl.Parent = adornee

    return hl

end

local function setColor(hl, color)

    hl.FillColor = color

    hl.OutlineColor = color

end

local Window = Fluent:CreateWindow({

    Title = "Flee The Facility Script",

    SubTitle = "Discord: antho.nyx",

    TabWidth = 155,

    Size = UDim2.fromOffset(550, 410),

    Acrylic = false,

    Theme = "Dark",

    MinimizeKey = Enum.KeyCode.RightShift,

})

local ESPTab = Window:AddTab({ Title = "ESP", Icon = "eye" })

local PlayerTab = Window:AddTab({ Title = "Players", Icon = "users" })

local BeastTab = Window:AddTab({ Title = "Beast", Icon = "skull" })

local MovementTab = Window:AddTab({ Title = "Movement", Icon = "person-standing" })

local TPTab = Window:AddTab({ Title = "TP", Icon = "map-pin" })

local SettingsTab = Window:AddTab({ Title = "Settings", Icon = "settings" })

local gui = Instance.new("ScreenGui")

gui.Name = "FTFScriptOverlay"

gui.ResetOnSpawn = false

gui.IgnoreGuiInset = true

gui.DisplayOrder = 50

if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) or not gui.Parent then

    gui.Parent = lp:WaitForChild("PlayerGui")

end

local espObjects = {}

local function clearESP(plr)

    local o = espObjects[plr]

    if o then

        o.hl:Destroy()

        o.bb:Destroy()

        espObjects[plr] = nil

    end

end

local function updateESP(plr, isBeast)

    if plr == lp or not flags.Players then

        return clearESP(plr)

    end

    local char = plr.Character

    local head = char and char:FindFirstChild("Head")

    if not head then

        return clearESP(plr)

    end

    local o = espObjects[plr]

    if o and (o.char ~= char or not o.hl.Parent or not o.bb.Parent) then

        clearESP(plr)

        o = nil

    end

    if not o then

        local bb = Instance.new("BillboardGui")

        bb.Name = "BeastTag"

        bb.Adornee = head

        bb.AlwaysOnTop = true

        bb.Size = UDim2.fromOffset(220, 36)

        bb.StudsOffset = Vector3.new(0, 3, 0)

        bb.Parent = head

        local label = Instance.new("TextLabel")

        label.Size = UDim2.fromScale(1, 1)

        label.BackgroundTransparency = 1

        label.Font = Enum.Font.GothamBold

        label.TextSize = 26

        label.Text = "BEAST"

        label.TextColor3 = BEAST_COLOR

        label.TextStrokeTransparency = 0

        label.Parent = bb

        o = {hl = makeHighlight(char, "PlayerESP"), bb = bb, char = char}

        espObjects[plr] = o

    end

    setColor(o.hl, isBeast and BEAST_COLOR or PLAYER_COLOR)

    o.bb.Enabled = isBeast

end

Players.PlayerRemoving:Connect(clearESP)

local objects = {}

local lastMapName, lastScan = nil, 0

local function kindOf(inst)

    local n = inst.Name

    if n == "ComputerTable" then return "COMPUTER" end

    if n == "FreezePod" then return "POD" end

    if n:lower() == "exitdoor" then return "EXIT" end

    if n == "SingleDoor" or n == "DoubleDoor" then return "DOOR" end

end

local function adorneeFor(inst)

    if inst.Name == "SingleDoor" then

        return inst:FindFirstChild("Door")

    end

    return inst

end

local function wanted(kind)

    return (kind == "COMPUTER" and flags.Computers)

        or (kind == "POD" and flags.Pods)

        or (kind == "DOOR" and flags.Doors)

        or (kind == "EXIT" and flags.ExitDoors)

end

local function clearObj(inst)

    local o = objects[inst]

    if o then

        o.hl:Destroy()

        objects[inst] = nil

    end

end

local function scanObjects()

    for _, d in ipairs(workspace:GetDescendants()) do

        local kind = kindOf(d)

        if kind and wanted(kind) and not objects[d] then

            local adornee = adorneeFor(d)

            if adornee then

                objects[d] = {kind = kind, hl = makeHighlight(adornee, "ObjESP"), adornee = adornee}

            end

        end

    end

end

local function isHacked(model)

    local screen = model:FindFirstChild("Screen", true)

    return screen ~= nil and screen:IsA("BasePart")

        and screen.BrickColor == BrickColor.new("Dark green")

end

local function teleportToUnhackedComputer()

    local character = lp.Character

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then

        notify("Computer TP", "Your character is not ready.", 4)

        return

    end

    local closest, closestDistance

    for _, inst in ipairs(workspace:GetDescendants()) do

        if inst.Name == "ComputerTable" and inst:IsA("Model") then

            local screen = inst:FindFirstChild("Screen", true)

            if screen and screen:IsA("BasePart") and not isHacked(inst) then

                local distance = (inst:GetPivot().Position - root.Position).Magnitude

                if not closestDistance or distance < closestDistance then

                    closest, closestDistance = inst, distance

                end

            end

        end

    end

    if not closest then

        notify("Computer TP", "No unhacked computers found.", 5)

        return

    end

    local centerCF, size = closest:GetBoundingBox()

    local center = centerCF.Position

    local candidates = {}

    for _, part in ipairs(closest:GetDescendants()) do

        if part:IsA("BasePart") and part.Name:lower():find("computertrigger", 1, true) then

            local outward = Vector3.new(part.Position.X - center.X, 0, part.Position.Z - center.Z)

            if outward.Magnitude > 0.1 then

                table.insert(candidates, part.Position + outward.Unit * 1.8)

            else

                table.insert(candidates, part.Position)

            end

        end

    end

    local right, forward = centerCF.RightVector, centerCF.LookVector

    table.insert(candidates, center + right * (size.X * 0.5 + 2.8))

    table.insert(candidates, center - right * (size.X * 0.5 + 2.8))

    table.insert(candidates, center + forward * (size.Z * 0.5 + 2.8))

    table.insert(candidates, center - forward * (size.Z * 0.5 + 2.8))

    table.sort(candidates, function(a, b)

        return (a - root.Position).Magnitude < (b - root.Position).Magnitude

    end)

    local rayParams = RaycastParams.new()

    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    rayParams.FilterDescendantsInstances = {character, closest}

    local overlapParams = OverlapParams.new()

    overlapParams.FilterType = Enum.RaycastFilterType.Exclude

    overlapParams.FilterDescendantsInstances = {character}

    overlapParams.MaxParts = 60

    local destination, fallback

    for _, point in ipairs(candidates) do

        local startY = math.max(point.Y, center.Y) + 10

        local hit = workspace:Raycast(

            Vector3.new(point.X, startY, point.Z),

            Vector3.new(0, -40, 0),

            rayParams

        )

        local y = hit and (hit.Position.Y + math.max(2.8, humanoid.HipHeight + root.Size.Y * 0.5 + 0.5)) or (point.Y + 3)

        local position = Vector3.new(point.X, y, point.Z)

        fallback = fallback or position

        local clear = true

        for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(position), Vector3.new(2.4, 4, 2.4), overlapParams)) do

            if part.CanCollide then

                clear = false

                break

            end

        end

        if clear then

            destination = position

            break

        end

    end

    destination = destination or fallback

    if not destination then

        notify("Computer TP", "Could not find a teleport position.", 4)

        return

    end

    local lookAt = Vector3.new(center.X, destination.Y, center.Z)

    local targetCFrame = (lookAt - destination).Magnitude > 0.1

        and CFrame.lookAt(destination, lookAt)

        or CFrame.new(destination)

    character:PivotTo(targetCFrame)

    root.AssemblyLinearVelocity = Vector3.zero

    root.AssemblyAngularVelocity = Vector3.zero

    notify("Computer TP", "Teleported beside the nearest unhacked computer.", 4)

end

local function doorColor(inst)

    local trigger = inst:FindFirstChild("DoorTrigger")

    local sign = trigger and trigger:FindFirstChild("ActionSign")

    local val = sign and sign.Value

    if val == 11 then return DOOR_OPEN end

    if val == 10 then return DOOR_CLOSED end

end

local function updateObjects()

    for inst, o in pairs(objects) do

        if not wanted(o.kind) then clearObj(inst) end

    end

    if not flags.Computers and not flags.Pods and not flags.Doors and not flags.ExitDoors then return end

    local mapName = rs("CurrentMap")

    local now = os.clock()

    if mapName ~= lastMapName or now - lastScan > 5 then

        lastMapName, lastScan = mapName, now

        scanObjects()

    end

    for inst, o in pairs(objects) do

        if not inst.Parent or not o.adornee.Parent or not o.hl.Parent then

            clearObj(inst)

        elseif o.kind == "COMPUTER" then

            setColor(o.hl, isHacked(inst) and COMPUTER_DONE or COMPUTER_COLOR)

        elseif o.kind == "POD" then

            setColor(o.hl, POD_COLOR)

        elseif o.kind == "EXIT" then

            setColor(o.hl, EXIT_COLOR)

        else

            local c = doorColor(inst)

            if c then setColor(o.hl, c) end

        end

    end

end

local arrow = Instance.new("Frame")

arrow.Name = "BeastArrow"

arrow.AnchorPoint = Vector2.new(0.5, 0.5)

arrow.Size = UDim2.fromOffset(60, 60)

arrow.BackgroundTransparency = 1

arrow.Visible = false

arrow.Parent = gui

local HEAD_TIP_Y = 8

local HEAD_HEIGHT = 22

local HEAD_SLOPE = 0.45

local SHAFT_WIDTH = 6

local SHAFT_BOTTOM = 52

local OUTLINE = 2.5

local function rowFrame(y, width, height, color, z)

    local f = Instance.new("Frame")

    f.AnchorPoint = Vector2.new(0.5, 0)

    f.Position = UDim2.fromOffset(30, y)

    f.Size = UDim2.fromOffset(width, height)

    f.BackgroundColor3 = color

    f.BorderSizePixel = 0

    f.ZIndex = z

    f.Parent = arrow

    return f

end

local function head(tipY, height, color, z)

    for i = 0, math.ceil(height) - 1 do

        rowFrame(tipY + i, 2 * HEAD_SLOPE * (i + 1), 2, color, z)

    end

end

local function shaft(topY, bottomY, width, color, z)

    local f = rowFrame(topY, width, bottomY - topY, color, z)

    Instance.new("UICorner", f).CornerRadius = UDim.new(0, math.floor(width / 2))

end

local sinHalf = HEAD_SLOPE / math.sqrt(1 + HEAD_SLOPE * HEAD_SLOPE)

local tipPush = OUTLINE / sinHalf

head(HEAD_TIP_Y - tipPush, HEAD_HEIGHT + tipPush + OUTLINE, Color3.fromRGB(0, 0, 0), 1)

shaft(HEAD_TIP_Y + HEAD_HEIGHT - 4, SHAFT_BOTTOM + OUTLINE, SHAFT_WIDTH + OUTLINE * 2, Color3.fromRGB(0, 0, 0), 1)

head(HEAD_TIP_Y, HEAD_HEIGHT, BEAST_COLOR, 2)

shaft(HEAD_TIP_Y + HEAD_HEIGHT - 4, SHAFT_BOTTOM, SHAFT_WIDTH, BEAST_COLOR, 2)

local distLabel = Instance.new("TextLabel")

distLabel.Name = "BeastDistance"

distLabel.AnchorPoint = Vector2.new(0.5, 0.5)

distLabel.Size = UDim2.fromOffset(120, 20)

distLabel.BackgroundTransparency = 1

distLabel.Font = Enum.Font.GothamBold

distLabel.TextSize = 16

distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

distLabel.TextStrokeTransparency = 0

distLabel.Visible = false

distLabel.Parent = gui

local function hideArrow()

    arrow.Visible = false

    distLabel.Visible = false

end

local arrowConn = RunService.RenderStepped:Connect(function()

    if not flags.Players then return hideArrow() end

    local cam = workspace.CurrentCamera

    local theirs = currentBeast and currentBeast ~= lp and currentBeast.Character

        and currentBeast.Character:FindFirstChild("HumanoidRootPart")

    if not (cam and theirs) then return hideArrow() end

    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")

    local from = myRoot and myRoot.Position or cam.CFrame.Position

    local studs = math.floor((theirs.Position - from).Magnitude + 0.5)

    local viewport = cam.ViewportSize

    local sp = cam:WorldToViewportPoint(theirs.Position)

    local inFront = sp.Z > 0

    if inFront and sp.X > ARROW_MARGIN and sp.X < viewport.X - ARROW_MARGIN

        and sp.Y > ARROW_MARGIN and sp.Y < viewport.Y - ARROW_MARGIN then

        return hideArrow()

    end

    local center = viewport / 2

    local dir = Vector2.new(sp.X, sp.Y) - center

    if not inFront then dir = -dir end

    if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end

    dir = dir.Unit

    local tx = dir.X ~= 0 and (center.X - ARROW_MARGIN) / math.abs(dir.X) or math.huge

    local ty = dir.Y ~= 0 and (center.Y - ARROW_MARGIN) / math.abs(dir.Y) or math.huge

    local pos = center + dir * math.min(tx, ty)

    arrow.Position = UDim2.fromOffset(pos.X, pos.Y)

    arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))

    arrow.Visible = true

    distLabel.Text = studs .. " studs"

    local gap = 26 + math.abs(dir.X) * (distLabel.TextBounds.X / 2) + math.abs(dir.Y) * 9

    local lpos = pos - dir * gap

    distLabel.Position = UDim2.fromOffset(lpos.X, lpos.Y)

    distLabel.Visible = true

end)

local notifiedBeast, notifiedPower = nil, nil

local function updateBeast(gameActive, power)

    if not gameActive then

        notifiedBeast, notifiedPower, currentBeast = nil, nil, nil

        return

    end

    currentBeast = nil

    for _, plr in ipairs(Players:GetPlayers()) do

        if stat(plr, "IsBeast") == true then

            currentBeast = plr

            break

        end

    end

    local beast = currentBeast

    if not beast or not flags.BeastAlert then return end

    if notifiedBeast ~= beast.Name then

        notifiedBeast, notifiedPower = beast.Name, power

        local who = (beast == lp) and "You are the Beast" or ("Beast: " .. beast.Name)

        notify(who, "Power: " .. tostring(power or "unknown"), 8)

    elseif power and power ~= notifiedPower then

        notifiedPower = power

        notify("Beast power: " .. tostring(power), beast.Name, 8)

    end

end

local savedCam = nil

local function applyThirdPerson()

    if not flags.ThirdPerson then return end

    pcall(function()

        lp.CameraMode = Enum.CameraMode.Classic

        lp.CameraMinZoomDistance = THIRD_PERSON_MIN_ZOOM

        lp.CameraMaxZoomDistance = THIRD_PERSON_MAX_ZOOM

    end)

end

local function pushOutCamera()

    if not flags.ThirdPerson then return end

    pcall(function()

        lp.CameraMode = Enum.CameraMode.Classic

        lp.CameraMaxZoomDistance = THIRD_PERSON_MAX_ZOOM

        lp.CameraMinZoomDistance = THIRD_PERSON_START_ZOOM

    end)

    task.delay(0.2, applyThirdPerson)

end

local function setThirdPerson(on)

    flags.ThirdPerson = on

    if on then

        savedCam = savedCam or {

            mode = lp.CameraMode,

            min = lp.CameraMinZoomDistance,

            max = lp.CameraMaxZoomDistance,

        }

        pushOutCamera()

    elseif savedCam then

        pcall(function()

            lp.CameraMode = savedCam.mode

            lp.CameraMinZoomDistance = savedCam.min

            lp.CameraMaxZoomDistance = savedCam.max

        end)

        savedCam = nil

    end

end

local function removeLight()

    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")

    local light = root and root:FindFirstChild("FTFLight")

    if light then light:Destroy() end

end

local function applyLight()

    if not flags.Light then return end

    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")

    if not root then return end

    local light = root:FindFirstChild("FTFLight")

    if not light then

        light = Instance.new("PointLight")

        light.Name = "FTFLight"

        light.Shadows = false

        light.Parent = root

    end

    light.Brightness = LIGHT_BRIGHTNESS

    light.Range = LIGHT_RANGE

    light.Color = LIGHT_COLOR

end

local function setLight(on)

    flags.Light = on

    if on then applyLight() else removeLight() end

end

local noFailThread = nil

local function setNoFail(on)

    flags.NoFail = on

    if on and not noFailThread then

        noFailThread = task.spawn(function()

            while flags.NoFail and running do

                pcall(function()

                    ReplicatedStorage.RemoteEvent:FireServer("SetPlayerMinigameResult", true)

                end)

                task.wait()

            end

            noFailThread = nil

        end)

    end

end

local CYAN = Color3.fromRGB(0, 229, 255)

local PINK = Color3.fromRGB(255, 46, 136)

local crawling = false

local crawlTrack, savedHip, savedSpeed, crawlConn

local noclipConn, noclipParts = nil, {}

local movement = {

    walkSpeedEnabled = false,

    jumpBoostEnabled = false,

    noclipEnabled = false,

    walkSpeed = 16,

    jumpPower = 70,

}

local movementDefaults = setmetatable({}, {__mode = "k"})

local movementConn

local function currentHumanoid()

    local char = lp.Character

    return char and char:FindFirstChildOfClass("Humanoid")

end

local function getMovementDefaults(hum)

    local defaults = movementDefaults[hum]

    if not defaults then

        defaults = {

            walkSpeed = hum.WalkSpeed,

            jumpPower = hum.JumpPower,

            jumpHeight = hum.JumpHeight,

            useJumpPower = hum.UseJumpPower,

        }

        movementDefaults[hum] = defaults

    end

    return defaults

end

local function applyMovement()

    local hum = currentHumanoid()

    if not hum or hum.Health <= 0 then return end

    if not movement.walkSpeedEnabled and not movement.jumpBoostEnabled then return end

    getMovementDefaults(hum)

    if movement.walkSpeedEnabled and not crawling and hum.WalkSpeed ~= movement.walkSpeed then

        hum.WalkSpeed = movement.walkSpeed

    end

    if movement.jumpBoostEnabled then

        if not hum.UseJumpPower then hum.UseJumpPower = true end

        if hum.JumpPower ~= movement.jumpPower then hum.JumpPower = movement.jumpPower end

    end

end

local function updateMovementLoop()

    if movement.walkSpeedEnabled or movement.jumpBoostEnabled then

        if movementConn then return end

        local elapsed = 0

        movementConn = RunService.Heartbeat:Connect(function(dt)

            elapsed = elapsed + dt

            if elapsed >= 0.12 then

                elapsed = 0

                applyMovement()

            end

        end)

    elseif movementConn then

        movementConn:Disconnect()

        movementConn = nil

    end

end

local function setWalkSpeed(on)

    movement.walkSpeedEnabled = on

    local hum = currentHumanoid()

    if not on and hum and not crawling then

        local defaults = movementDefaults[hum]

        if defaults then hum.WalkSpeed = defaults.walkSpeed end

    end

    updateMovementLoop()

    applyMovement()

end

local function setJumpBoost(on)

    movement.jumpBoostEnabled = on

    local hum = currentHumanoid()

    if not on and hum then

        local defaults = movementDefaults[hum]

        if defaults then

            hum.JumpPower = defaults.jumpPower

            hum.JumpHeight = defaults.jumpHeight

            hum.UseJumpPower = defaults.useJumpPower

        end

    end

    updateMovementLoop()

    applyMovement()

end

local function updateNoclipState()

    if movement.noclipEnabled or crawling then

        if noclipConn then return end

        noclipConn = RunService.Stepped:Connect(function()

            local char = lp.Character

            if not char then return end

            for _, part in ipairs(char:GetDescendants()) do

                if part:IsA("BasePart") and part.CanCollide then

                    if noclipParts[part] == nil then noclipParts[part] = true end

                    part.CanCollide = false

                end

            end

        end)

    else

        if noclipConn then

            noclipConn:Disconnect()

            noclipConn = nil

        end

        for part, original in pairs(noclipParts) do

            if part.Parent then part.CanCollide = original end

        end

        noclipParts = {}

    end

end

local function setNoclip(on)

    movement.noclipEnabled = on

    updateNoclipState()

end

local function restoreMovement()

    movement.walkSpeedEnabled = false

    movement.jumpBoostEnabled = false

    movement.noclipEnabled = false

    updateMovementLoop()

    local hum = currentHumanoid()

    if hum then

        local defaults = movementDefaults[hum]

        if defaults then

            hum.WalkSpeed = defaults.walkSpeed

            hum.JumpPower = defaults.jumpPower

            hum.JumpHeight = defaults.jumpHeight

            hum.UseJumpPower = defaults.useJumpPower

        end

    end

    updateNoclipState()

end

local crawlBtn, crawlGrad, crawlStroke, crawlStrokeGrad, crawlLabel, crawlDot, crawlScale, crawlDragConn

local crawlDragged = false

local crawlLocked = true

local crawlPos = UDim2.new(1, -150, 0.6, 0)

local function styleCrawlButton()

    if not crawlBtn then return end

    if crawling then

        crawlGrad.Color = ColorSequence.new(Color3.fromRGB(0, 255, 120), Color3.fromRGB(0, 200, 90))

        crawlStrokeGrad.Enabled = false

        crawlStroke.Color = Color3.fromRGB(210, 255, 225)

        crawlLabel.TextColor3 = Color3.fromRGB(4, 24, 12)

        crawlDot.BackgroundColor3 = Color3.fromRGB(4, 24, 12)

    else

        crawlGrad.Color = ColorSequence.new(Color3.fromRGB(30, 30, 44), Color3.fromRGB(14, 14, 22))

        crawlStrokeGrad.Enabled = true

        crawlStroke.Color = Color3.fromRGB(255, 255, 255)

        crawlLabel.TextColor3 = Color3.fromRGB(235, 235, 245)

        crawlDot.BackgroundColor3 = Color3.fromRGB(150, 150, 165)

    end

end

local function findCrawlAnimation()

    for _, root in ipairs({ReplicatedStorage, lp.Character, lp, game:GetService("StarterPlayer")}) do

        for _, d in ipairs(root:GetDescendants()) do

            if d:IsA("Animation") and d.AnimationId ~= ""

                and d.Name:lower():find("crawl", 1, true) then

                return d

            end

        end

    end

end

local function stopCrawl()

    if crawlConn then crawlConn:Disconnect() crawlConn = nil end

    if crawlTrack then

        pcall(function() crawlTrack:Stop() end)

        crawlTrack = nil

    end

    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")

    if hum and savedHip then hum.HipHeight = savedHip end

    if hum and savedSpeed then

        local defaults = movementDefaults[hum]

        hum.WalkSpeed = movement.walkSpeedEnabled and movement.walkSpeed

            or (defaults and defaults.walkSpeed) or savedSpeed

    end

    savedHip, savedSpeed, crawling = nil, nil, false

    updateNoclipState()

    styleCrawlButton()

end

local function startCrawl()

    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")

    if not hum or hum.Health <= 0 then return end

    local anim = findCrawlAnimation()

    if not anim then

        return notify("Crawl", "No crawl animation found in this game.", 5)

    end

    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)

    if not ok or not track then

        return notify("Crawl", "Couldn't load the crawl animation.", 5)

    end

    track.Looped = true

    track.Priority = Enum.AnimationPriority.Action

    track:Play()

    crawlTrack = track

    getMovementDefaults(hum)

    savedHip, savedSpeed = hum.HipHeight, hum.WalkSpeed

    hum.WalkSpeed = CRAWL_SPEED

    crawlConn = RunService.Heartbeat:Connect(function()

        local c = lp.Character

        local h = c and c:FindFirstChildOfClass("Humanoid")

        local root = c and c:FindFirstChild("HumanoidRootPart")

        if not h or not root or h.Health <= 0 then return end

        if h.WalkSpeed ~= CRAWL_SPEED then h.WalkSpeed = CRAWL_SPEED end

        if crawlTrack then

            local v = root.AssemblyLinearVelocity

            local moving = Vector3.new(v.X, 0, v.Z).Magnitude

            crawlTrack:AdjustSpeed(moving > 0.5 and math.clamp(moving / CRAWL_ANIM_REF_SPEED, 0.3, 2) or 0)

        end

        if h.FloorMaterial == Enum.Material.Air then return end

        local params = RaycastParams.new()

        params.FilterType = Enum.RaycastFilterType.Exclude

        params.FilterDescendantsInstances = {c}

        local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)

        if not hit then return end

        local err = CRAWL_HEIGHT - (root.Position.Y - hit.Position.Y)

        if math.abs(err) > 0.05 then

            h.HipHeight = math.clamp(h.HipHeight + err * 0.3, -8, math.max(savedHip or 0, 2))

        end

    end)

    crawling = true

    updateNoclipState()

    styleCrawlButton()

    hum.Died:Once(stopCrawl)

end

local function createCrawlButton()

    if crawlBtn then return end

    crawlBtn = Instance.new("TextButton")

    crawlBtn.Name = "CrawlButton"

    crawlBtn.Size = UDim2.fromOffset(120, 46)

    crawlBtn.Position = crawlPos

    crawlBtn.BackgroundTransparency = 1

    crawlBtn.Text = ""

    crawlBtn.AutoButtonColor = false

    crawlBtn.Parent = gui

    crawlScale = Instance.new("UIScale", crawlBtn)

    local bg = Instance.new("Frame")

    bg.Size = UDim2.fromScale(1, 1)

    bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

    bg.BorderSizePixel = 0

    bg.Parent = crawlBtn

    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

    crawlGrad = Instance.new("UIGradient", bg)

    crawlGrad.Rotation = 90

    crawlStroke = Instance.new("UIStroke", bg)

    crawlStroke.Thickness = 2.5

    crawlStrokeGrad = Instance.new("UIGradient", crawlStroke)

    crawlStrokeGrad.Color = ColorSequence.new(CYAN, PINK)

    crawlDot = Instance.new("Frame")

    crawlDot.AnchorPoint = Vector2.new(0, 0.5)

    crawlDot.Size = UDim2.fromOffset(12, 12)

    crawlDot.Position = UDim2.new(0, 18, 0.5, 0)

    crawlDot.BorderSizePixel = 0

    crawlDot.Parent = bg

    Instance.new("UICorner", crawlDot).CornerRadius = UDim.new(1, 0)

    crawlLabel = Instance.new("TextLabel")

    crawlLabel.Size = UDim2.new(1, -44, 1, 0)

    crawlLabel.Position = UDim2.fromOffset(38, 0)

    crawlLabel.BackgroundTransparency = 1

    crawlLabel.Font = Enum.Font.GothamBlack

    crawlLabel.TextSize = 17

    crawlLabel.Text = "CRAWL"

    crawlLabel.TextXAlignment = Enum.TextXAlignment.Left

    crawlLabel.Parent = bg

    styleCrawlButton()

    crawlBtn.Activated:Connect(function()

        if crawlDragged then

            crawlDragged = false

            return

        end

        if stat(lp, "IsBeast") ~= true then

            return notify("Beast Crawl", "Wait till you're the Beast!", 4)

        end

        if crawling then stopCrawl() else startCrawl() end

    end)

    local dragging, dragStart, startPos

    crawlBtn.InputBegan:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1

            or input.UserInputType == Enum.UserInputType.Touch then

            crawlScale.Scale = 0.94

            crawlDragged = false

            if not crawlLocked then

                dragging = true

                dragStart = input.Position

                startPos = crawlBtn.Position

            end

            input.Changed:Connect(function()

                if input.UserInputState == Enum.UserInputState.End then

                    dragging = false

                    if crawlScale then crawlScale.Scale = 1 end

                end

            end)

        end

    end)

    crawlDragConn = UserInputService.InputChanged:Connect(function(input)

        if dragging and not crawlLocked and crawlBtn

            and (input.UserInputType == Enum.UserInputType.MouseMovement

            or input.UserInputType == Enum.UserInputType.Touch) then

            local d = input.Position - dragStart

            if d.Magnitude > 6 then crawlDragged = true end

            if crawlDragged then

                crawlPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,

                    startPos.Y.Scale, startPos.Y.Offset + d.Y)

                crawlBtn.Position = crawlPos

            end

        end

    end)

end

local function destroyCrawlButton()

    stopCrawl()

    if crawlDragConn then crawlDragConn:Disconnect() crawlDragConn = nil end

    if crawlBtn then

        crawlBtn:Destroy()

        crawlBtn = nil

    end

    crawlDragged = false

end

lp.CharacterAdded:Connect(function(character)

    if crawlConn then crawlConn:Disconnect() crawlConn = nil end

    for part, original in pairs(noclipParts) do

        if part.Parent then part.CanCollide = original end

    end

    noclipParts = {}

    crawlTrack, savedHip, savedSpeed, crawling = nil, nil, nil, false

    updateNoclipState()

    styleCrawlButton()

    pushOutCamera()

    task.defer(applyLight)

    task.spawn(function()

        local hum = character:WaitForChild("Humanoid", 10)

        if hum and running and lp.Character == character then

            applyMovement()

        end

    end)

end)

local function forceReset()

    stopCrawl()

    local char = lp.Character

    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if hum then

        hum.Health = 0

    elseif char then

        char:BreakJoints()

    end

end

local function refresh()

    updateBeast(rs("IsGameActive") == true, rs("CurrentPower"))

    updateObjects()

    applyThirdPerson()

    applyLight()

    for _, plr in ipairs(Players:GetPlayers()) do

        updateESP(plr, plr == currentBeast)

    end

end

task.spawn(function()

    while running do

        local ok, err = pcall(refresh)

        if not ok then warn("Flee The Facility Script error: " .. tostring(err)) end

        task.wait(0.5)

    end

end)

local function refreshNow()

    task.spawn(pcall, refresh)

end

local function setPlayersESP(on)

    flags.Players = on

    if on then

        refreshNow()

    else

        for plr in pairs(espObjects) do clearESP(plr) end

        hideArrow()

    end

end

local function setObjectESP(flag)

    return function(on)

        flags[flag] = on

        lastScan = 0

        refreshNow()

    end

end

ESPTab:AddToggle("FTFPlayersESP", {

    Title = "Players ESP",

    Default = false,

    Callback = setPlayersESP,

})

ESPTab:AddToggle("FTFComputersESP", {

    Title = "Computers ESP",

    Default = false,

    Callback = setObjectESP("Computers"),

})

ESPTab:AddToggle("FTFPodsESP", {

    Title = "Pods ESP",

    Default = false,

    Callback = setObjectESP("Pods"),

})

ESPTab:AddToggle("FTFDoorsESP", {

    Title = "Doors ESP",

    Default = false,

    Callback = setObjectESP("Doors"),

})

ESPTab:AddToggle("FTFExitsESP", {

    Title = "Exits ESP",

    Default = false,

    Callback = setObjectESP("ExitDoors"),

})

ESPTab:AddButton({

    Title = "Refresh ESP",

    Description = "Rebuild all enabled ESP highlights.",

    Callback = function()

        for inst in pairs(objects) do clearObj(inst) end

        for plr in pairs(espObjects) do clearESP(plr) end

        lastScan = 0

        refreshNow()

    end,

})

PlayerTab:AddToggle("FTFBeastAlert", {

    Title = "Beasts Perk",

    Description = "Notify when the Beast or their power changes.",

    Default = false,

    Callback = function(on)

        flags.BeastAlert = on

        if on then notifiedBeast, notifiedPower = nil, nil end

    end,

})

PlayerTab:AddToggle("FTFFlashlight", {

    Title = "Flashlight",

    Default = false,

    Callback = setLight,

})

PlayerTab:AddToggle("FTFAntiPCError", {

    Title = "Anti PC Error",

    Default = false,

    Callback = setNoFail,

})

PlayerTab:AddButton({

    Title = "Force Reset",

    Callback = forceReset,

})

BeastTab:AddToggle("FTFThirdPerson", {

    Title = "Third Person Camera",

    Default = false,

    Callback = setThirdPerson,

})

BeastTab:AddToggle("FTFBeastCrawl", {

    Title = "Beast Crawl",

    Default = false,

    Callback = function(on)

        if on then

            crawlLocked = true

            createCrawlButton()

        else

            destroyCrawlButton()

        end

    end,

})

MovementTab:AddToggle("FTFWalkSpeedEnabled", {

    Title = "WalkSpeed",

    Description = "Enable custom walking speed.",

    Default = false,

    Callback = setWalkSpeed,

})

MovementTab:AddSlider("FTFWalkSpeedValue", {

    Title = "WalkSpeed Value",

    Description = "Change your movement speed.",

    Default = 16,

    Min = 0,

    Max = 300,

    Rounding = 0,

    Callback = function(value)

        movement.walkSpeed = value

        applyMovement()

    end,

})

MovementTab:AddToggle("FTFJumpBoostEnabled", {

    Title = "Jump Boost",

    Description = "Enable custom jump power.",

    Default = false,

    Callback = setJumpBoost,

})

MovementTab:AddSlider("FTFJumpPowerValue", {

    Title = "Jump Power",

    Description = "Change how high you jump.",

    Default = 70,

    Min = 0,

    Max = 350,

    Rounding = 0,

    Callback = function(value)

        movement.jumpPower = value

        applyMovement()

    end,

})

MovementTab:AddToggle("FTFNoclipEnabled", {

    Title = "Noclip",

    Description = "Move through solid objects. Also works during Beast Crawl.",

    Default = false,

    Callback = setNoclip,

})

TPTab:AddButton({

    Title = "Teleport to Unhacked Computer",

    Description = "Find the nearest unfinished computer and teleport beside it.",

    Callback = teleportToUnhackedComputer,

})

SettingsTab:AddDropdown("FTFTheme", {

    Title = "Theme",

    Description = "Change the Fluent interface theme.",

    Values = Fluent.Themes,

    Multi = false,

    Default = "Dark",

    Callback = function(value)

        Fluent:SetTheme(value)

    end,

})

SettingsTab:AddButton({

    Title = "Unload Script",

    Description = "Remove ESP, overlays, and the Fluent interface.",

    Callback = function()

        running = false

        setThirdPerson(false)

        setLight(false)

        stopCrawl()

        restoreMovement()

        for k in pairs(flags) do flags[k] = false end

        arrowConn:Disconnect()

        destroyCrawlButton()

        for plr in pairs(espObjects) do clearESP(plr) end

        for inst in pairs(objects) do clearObj(inst) end

        gui:Destroy()

        Fluent:Destroy()

    end,

})

Window:SelectTab(1)
