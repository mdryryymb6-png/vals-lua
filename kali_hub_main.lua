--[[
    Kali Hub | Basketball Legends
    Rayfield UI  |  by @wrl11 & @aylonthegiant
    discord.gg/epNcR8Ce89
    
    Upload this file to GitHub (raw) or paste.ee
    then execute:
        loadstring(game:HttpGet("YOUR_RAW_URL"))()
]]

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService  = game:GetService("TeleportService")

local cloneref = cloneref or function(v) return v end
local player   = Players.LocalPlayer
local Char     = player.Character or player.CharacterAdded:Wait()
local Hrp      = cloneref(Char:WaitForChild("HumanoidRootPart"))

-- ── Rayfield ─────────────────────────────────────────────────────────────────
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ── Park detection ───────────────────────────────────────────────────────────
local isPark = (function()
    local g = workspace:FindFirstChild("Game")
    return g and g:FindFirstChild("Courts") ~= nil
end)()

-- ── Game refs ────────────────────────────────────────────────────────────────
local visualGui       = player.PlayerGui:WaitForChild("Visual")
local shootingElement = visualGui:WaitForChild("Shooting")
local Shoot           = ReplicatedStorage.Packages.Knit.Services.ControlService.RE.Shoot

-- ── State ─────────────────────────────────────────────────────────────────────
local autoShootEnabled       = false
local autoGuardEnabled       = false
local autoGuardToggleEnabled = false
local speedBoostEnabled      = false
local postAimbotEnabled      = false
local magnetEnabled          = false
local followEnabled          = false
local stealReachEnabled      = false
local teleportEnabled        = false
local animationSpoofEnabled  = false

local shootPower             = 0.8
local desiredSpeed           = 16
local predictionTime         = 0.3
local guardDistance          = 10
local postActivationDistance = 10
local MagsDist               = 30
local followOffset           = -10
local offsetDistance         = 3
local stealReachMultiplier   = 1.5

local visibleConn, autoGuardConnection   = nil, nil
local speedBoostConnection, postAimbotConnection = nil, nil
local followConnection  = nil
local lastPositions     = {}
local postHoldActive    = false
local lastPostUpdate    = 0
local POST_UPDATE_INTERVAL = 0.033
local originalRightArmSize, originalLeftArmSize

-- ════════════════════════════════════════════════
--  AUTO GREEN
-- ════════════════════════════════════════════════
local function startAutoGreen()
    if visibleConn then return end
    visibleConn = shootingElement:GetPropertyChangedSignal("Visible"):Connect(function()
        if autoShootEnabled and shootingElement.Visible then
            task.wait(0.25)
            Shoot:FireServer(shootPower)
        end
    end)
end
local function stopAutoGreen()
    if visibleConn then visibleConn:Disconnect(); visibleConn = nil end
end

-- ════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════
local function getPlayerFromModel(model)
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character == model then return p end
    end
end

local function isOnDifferentTeam(model)
    local op = getPlayerFromModel(model)
    if not op then return false end
    if not player.Team or not op.Team then return op ~= player end
    return player.Team ~= op.Team
end

local function findPlayerWithBall()
    if isPark then
        local closest, cd = nil, math.huge
        for _, m in pairs(workspace:GetChildren()) do
            if m:IsA("Model") and m ~= player.Character and m:FindFirstChild("HumanoidRootPart") then
                local t = m:FindFirstChild("Basketball")
                if t and t:IsA("Tool") then
                    local d = (m.HumanoidRootPart.Position - Hrp.Position).Magnitude
                    if d < cd then cd = d; closest = m end
                end
            end
        end
        if closest then return closest, closest.HumanoidRootPart end
        return nil, nil
    end
    local lb = workspace:FindFirstChild("Basketball")
    if lb and lb:IsA("BasePart") then
        local closest, cd = nil, math.huge
        for _, m in pairs(workspace:GetChildren()) do
            if m:IsA("Model") and m ~= player.Character
               and m:FindFirstChild("HumanoidRootPart") and isOnDifferentTeam(m) then
                local d = (lb.Position - m.HumanoidRootPart.Position).Magnitude
                if d < cd and d < 15 then cd = d; closest = m end
            end
        end
        if closest then return closest, closest.HumanoidRootPart end
    end
    for _, m in pairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= player.Character
           and m:FindFirstChild("HumanoidRootPart") and isOnDifferentTeam(m) then
            local b = m:FindFirstChild("Basketball")
            if b and b:IsA("Tool") then return m, m.HumanoidRootPart end
        end
    end
    return nil, nil
end

local function getClosestOpponent()
    local char = player.Character; if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
    local closest, minD = nil, postActivationDistance
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
           and isOnDifferentTeam(p.Character) then
            local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
            if d < minD then minD = d; closest = p.Character.HumanoidRootPart end
        end
    end
    return closest
end

local function playerHasBall()
    local c = player.Character; if not c then return false end
    local t = c:FindFirstChild("Basketball"); return t and t:IsA("Tool")
end

local function detectBallHand()
    local c = player.Character; if not c then return "right" end
    local t = c:FindFirstChild("Basketball")
    if t and t:IsA("Tool") then
        local h = t:FindFirstChild("Handle")
        if h then
            local r = c:FindFirstChild("HumanoidRootPart")
            if r then return r.CFrame:ToObjectSpace(h.CFrame).X > 0 and "right" or "left" end
        end
    end
    return "right"
end

-- ════════════════════════════════════════════════
--  POST AIMBOT
-- ════════════════════════════════════════════════
local function executePostAimbot()
    local now = tick()
    if now - lastPostUpdate < POST_UPDATE_INTERVAL then return end
    lastPostUpdate = now
    if not postHoldActive then return end
    local c = player.Character; if not c then return end
    local root = c:FindFirstChild("HumanoidRootPart"); if not root then return end
    local target = getClosestOpponent(); if not target then return end
    local dir  = (target.Position - root.Position).Unit
    local face = CFrame.new(root.Position, root.Position + dir)
    if playerHasBall() then
        local h = detectBallHand()
        root.CFrame = face * CFrame.Angles(0, h == "left" and math.rad(90) or math.rad(-90), 0)
    else
        root.CFrame = face
    end
end

-- ════════════════════════════════════════════════
--  AUTO GUARD
-- ════════════════════════════════════════════════
local function autoGuard()
    if not autoGuardEnabled then return end
    if player:FindFirstChild("Basketball") then return end
    local c = player.Character; if not c then return end
    local hum  = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local root = c:FindFirstChild("HumanoidRootPart"); if not root then return end
    local bc, bcRoot = findPlayerWithBall()
    if bc and bcRoot then
        local cur = bcRoot.Position
        local vel = Vector3.zero
        if lastPositions[bc] then vel = (cur - lastPositions[bc]) / task.wait() end
        lastPositions[bc] = cur
        local pred   = cur + vel * predictionTime * 60
        local dir    = (pred - root.Position).Unit
        local defPos = Vector3.new((pred - dir*5).X, root.Position.Y, (pred - dir*5).Z)
        local dist   = (root.Position - bcRoot.Position).Magnitude
        local VIM    = game:GetService("VirtualInputManager")
        if dist <= guardDistance then
            hum:MoveTo(defPos)
            VIM:SendKeyEvent(dist <= 10, Enum.KeyCode.F, false, game)
        else
            VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end
    else
        game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end
end

-- ════════════════════════════════════════════════
--  SPEED BOOST (CFrame method)
-- ════════════════════════════════════════════════
local function startCFrameSpeed(spd)
    local conn
    conn = RunService.RenderStepped:Connect(function(dt)
        local c = player.Character; if not c then return end
        local r = c:FindFirstChild("HumanoidRootPart")
        local h = c:FindFirstChildOfClass("Humanoid")
        if not r or not h then return end
        local mv = h.MoveDirection
        if mv.Magnitude > 0 then
            r.CFrame = r.CFrame + mv.Unit * math.max(spd - h.WalkSpeed, 0) * dt
        end
    end)
    return function() if conn then conn:Disconnect() end end
end

-- ════════════════════════════════════════════════
--  STEAL REACH
-- ════════════════════════════════════════════════
local function updateHitboxSizes()
    local c = player.Character; if not c then return end
    local function proc(name)
        local arm = c:FindFirstChild(name); if not arm then return end
        if stealReachEnabled then
            if name:find("Right") and not originalRightArmSize then originalRightArmSize = arm.Size end
            if name:find("Left")  and not originalLeftArmSize  then originalLeftArmSize  = arm.Size end
            local base = name:find("Right") and originalRightArmSize or originalLeftArmSize
            if base then
                arm.Size = base * stealReachMultiplier
                arm.Transparency = 1; arm.CanCollide = false; arm.Massless = true
            end
        else
            local base = name:find("Right") and originalRightArmSize or originalLeftArmSize
            if arm and base then
                arm.Size = base; arm.Transparency = 0; arm.CanCollide = false; arm.Massless = false
            end
            if name:find("Right") then originalRightArmSize = nil end
            if name:find("Left")  then originalLeftArmSize  = nil end
        end
    end
    for _, n in ipairs({"Right Arm","RightHand","RightLowerArm","Left Arm","LeftHand","LeftLowerArm"}) do
        proc(n)
    end
end

RunService.RenderStepped:Connect(function()
    if stealReachEnabled then updateHitboxSizes() end
end)

-- ════════════════════════════════════════════════
--  AUTO REBOUND / STEAL  (always-on, gated by flag)
-- ════════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    if not teleportEnabled then return end
    local c = player.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local best, bestD = nil, math.huge
    local maxD = isPark and 100 or math.huge
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "Basketball" then
            local part = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart")
            if part then
                local d = (part.Position - hrp.Position).Magnitude
                if d < bestD and d <= maxD then bestD = d; best = part end
            end
        end
    end
    if best then hrp.CFrame = CFrame.new(best.Position + best.CFrame.LookVector * offsetDistance) end
end)

-- ════════════════════════════════════════════════
--  FOLLOW BALL CARRIER
-- ════════════════════════════════════════════════
local function enableFollow()
    if followEnabled then return end
    followEnabled = true
    followConnection = RunService.Heartbeat:Connect(function()
        if not followEnabled then return end
        local c = player.Character; if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local _, cr = findPlayerWithBall()
        if cr then
            local maxD = isPark and 100 or math.huge
            if (hrp.Position - cr.Position).Magnitude <= maxD then
                hrp.CFrame = cr.CFrame * CFrame.new(0, 0, followOffset)
            end
        end
    end)
end
local function disableFollow()
    followEnabled = false
    if followConnection then followConnection:Disconnect(); followConnection = nil end
end

-- ════════════════════════════════════════════════
--  BALL MAGNET  (always-on heartbeat, gated by flag)
-- ════════════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not magnetEnabled then return end
    local c = player.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and v.Name == "Basketball" then
            if (hrp.Position - v.Position).Magnitude <= MagsDist then
                local touch
                for _, d in ipairs(v:GetDescendants()) do
                    if d:IsA("TouchTransmitter") then touch = d; break end
                end
                touch = touch or v:FindFirstChildOfClass("TouchTransmitter")
                if touch then
                    firetouchinterest(hrp, v, 0)
                    firetouchinterest(hrp, v, 1)
                end
            end
        end
    end
end)

-- ════════════════════════════════════════════════
--  BODY GYRO VISUALS
-- ════════════════════════════════════════════════
local function setBGVisible()
    for _, m in pairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
            local hrp = m.HumanoidRootPart
            for _, o in pairs(hrp:GetDescendants()) do
                if o.Name == "BG" and o:IsA("BodyGyro") then
                    o.Parent = hrp; o.MaxTorque = Vector3.new(9e9,9e9,9e9)
                    o.P = 9e4; o.D = 500; o.CFrame = hrp.CFrame
                end
            end
        end
    end
end
local function hideBG()
    for _, m in pairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
            for _, o in pairs(m.HumanoidRootPart:GetDescendants()) do
                if o.Name == "BG" and o:IsA("BodyGyro") then o.Parent = nil end
            end
        end
    end
end

-- ════════════════════════════════════════════════
--  ANIMATION SPOOF
-- ════════════════════════════════════════════════
local AnimationsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations_R15")
local selectedDunkAnim  = "Default"
local selectedEmoteAnim = "Dance_Casual"
local dunkConn, emoteConn, charDunk, charEmote

local EmoteAnimations = {
    Default="Dance_Casual", Dance_Sturdy="Dance_Sturdy", Dance_Taunt="Dance_Taunt",
    Dance_TakeFlight="Dance_TakeFlight", Dance_Flex="Dance_Flex", Dance_Bat="Dance_Bat",
    Dance_Twist="Dance_Twist", Dance_Griddy="Dance_Griddy", Dance_Dab="Dance_Dab",
    Dance_Drake="Dance_Drake", Dance_Fresh="Dance_Fresh", Dance_Hype="Dance_Hype",
    Dance_Spongebob="Dance_Spongebob", Dance_Backflip="Dance_Backflip",
    Dance_L="Dance_L", Dance_Facepalm="Dance_Facepalm", Dance_Bow="Dance_Bow"
}
local emoteOptions = {}
for k in pairs(EmoteAnimations) do table.insert(emoteOptions, k) end
table.sort(emoteOptions)

local function setupDunkConn(hum)
    local a = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    return a.AnimationPlayed:Connect(function(track)
        if animationSpoofEnabled and track.Animation.Name == "Dunk_Default" and selectedDunkAnim ~= "Default" then
            track:Stop()
            local ca = AnimationsFolder:FindFirstChild("Dunk_"..selectedDunkAnim)
            if ca then hum:LoadAnimation(ca):Play() end
        end
    end)
end
local function setupEmoteConn(hum)
    local a = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    return a.AnimationPlayed:Connect(function(track)
        if animationSpoofEnabled and track.Animation.Name == "Dance_Casual" and selectedEmoteAnim ~= "Dance_Casual" then
            track:Stop()
            local ca = AnimationsFolder:FindFirstChild(selectedEmoteAnim)
            if ca then hum:LoadAnimation(ca):Play() end
        end
    end)
end
local function enableAnimSpoof()
    local c = player.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then
            if dunkConn  then dunkConn:Disconnect()  end
            if emoteConn then emoteConn:Disconnect() end
            dunkConn  = setupDunkConn(h)
            emoteConn = setupEmoteConn(h)
        end
    end
    if charDunk  then charDunk:Disconnect()  end
    if charEmote then charEmote:Disconnect() end
    charDunk  = player.CharacterAdded:Connect(function(nc)
        local h = nc:WaitForChild("Humanoid")
        if dunkConn then dunkConn:Disconnect() end
        dunkConn = setupDunkConn(h)
    end)
    charEmote = player.CharacterAdded:Connect(function(nc)
        local h = nc:WaitForChild("Humanoid")
        if emoteConn then emoteConn:Disconnect() end
        emoteConn = setupEmoteConn(h)
    end)
end
local function disableAnimSpoof()
    for _, c in ipairs({dunkConn, emoteConn, charDunk, charEmote}) do
        if c then c:Disconnect() end
    end
    dunkConn=nil; emoteConn=nil; charDunk=nil; charEmote=nil
end

-- ════════════════════════════════════════════════
--  G KEY  –  GUARD ACTIVATION
-- ════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(inp, gp)
    if inp.KeyCode == Enum.KeyCode.G and not gp and autoGuardToggleEnabled then
        autoGuardEnabled = true; lastPositions = {}
        if not autoGuardConnection then
            autoGuardConnection = RunService.Heartbeat:Connect(autoGuard)
        end
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.KeyCode == Enum.KeyCode.G then
        autoGuardEnabled = false
        if autoGuardConnection then autoGuardConnection:Disconnect(); autoGuardConnection = nil end
        lastPositions = {}
        game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end
end)

-- ════════════════════════════════════════════════
--  BUILD UI
-- ════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    Name            = "Kali Hub  |  Basketball Legends",
    LoadingTitle    = "Kali Hub",
    LoadingSubtitle = "by @wrl11 & @aylonthegiant",
    ConfigurationSaving = { Enabled = true, FolderName = "KaliHub", FileName = "Config" },
    Discord = { Enabled = true, Invite = "epNcR8Ce89", RememberJoins = true },
    KeySystem = false,
})

local MainTab   = Window:CreateTab("Main",   "gamepad-2")
local PlayerTab = Window:CreateTab("Player", "user")
local MiscTab   = Window:CreateTab("Misc",   "settings")
local UITab     = Window:CreateTab("UI",     "monitor")

-- ───────────────── MAIN ─────────────────────────

MainTab:CreateSection("Auto Green (Shot Timing)")
MainTab:CreateToggle({ Name="Auto Green", CurrentValue=false, Flag="AutoGreen",
    Callback=function(v) autoShootEnabled=v; if v then startAutoGreen() else stopAutoGreen() end end })
MainTab:CreateSlider({ Name="Shot Power  (80=Med · 90=Good · 95=Great · 100=Perfect)",
    Range={50,100}, Increment=1, Suffix="%", CurrentValue=80, Flag="ShootPower",
    Callback=function(v) shootPower=v/100 end })

MainTab:CreateSection("Auto Guard  (Hold G)")
MainTab:CreateToggle({ Name="Enable Auto Guard", CurrentValue=false, Flag="AutoGuardToggle",
    Callback=function(v)
        autoGuardToggleEnabled=v
        if not v then
            autoGuardEnabled=false
            if autoGuardConnection then autoGuardConnection:Disconnect(); autoGuardConnection=nil end
            lastPositions={}
            game:GetService("VirtualInputManager"):SendKeyEvent(false,Enum.KeyCode.F,false,game)
        end
    end })
MainTab:CreateSlider({ Name="Guard Distance", Range={5,20}, Increment=1, Suffix=" studs",
    CurrentValue=10, Flag="GuardDist", Callback=function(v) guardDistance=v end })
MainTab:CreateSlider({ Name="Prediction Time", Range={1,8}, Increment=1, Suffix="×0.1s",
    CurrentValue=3, Flag="PredTime", Callback=function(v) predictionTime=v/10 end })

MainTab:CreateSection("Auto Rebound & Steal")
MainTab:CreateToggle({ Name="Auto Rebound & Steal", CurrentValue=false, Flag="ReboundSteal",
    Callback=function(v) teleportEnabled=v end })
MainTab:CreateKeybind({ Name="Rebound & Steal Key", CurrentKeybind="T", HoldToInteract=false,
    Flag="ReboundKey", Callback=function() teleportEnabled=not teleportEnabled end })
MainTab:CreateSlider({ Name="Ball Offset Distance", Range={0,6}, Increment=1, Suffix=" studs",
    CurrentValue=0, Flag="ReboundOffset", Callback=function(v) offsetDistance=v end })

MainTab:CreateSection("Post Aimbot  (Hold P)")
MainTab:CreateToggle({ Name="Post Aimbot", CurrentValue=false, Flag="PostAimbot",
    Callback=function(v)
        postAimbotEnabled=v
        if not v then
            postHoldActive=false
            if postAimbotConnection then postAimbotConnection:Disconnect(); postAimbotConnection=nil end
        end
    end })
MainTab:CreateKeybind({ Name="Post Aimbot Hold Key", CurrentKeybind="P", HoldToInteract=true,
    Flag="PostKey",
    Callback=function(active)
        if not postAimbotEnabled then return end
        postHoldActive=active
        if active and not postAimbotConnection then
            postAimbotConnection=RunService.Heartbeat:Connect(executePostAimbot)
        elseif not active and postAimbotConnection then
            postAimbotConnection:Disconnect(); postAimbotConnection=nil
        end
    end })
MainTab:CreateSlider({ Name="Activation Distance", Range={5,20}, Increment=1, Suffix=" studs",
    CurrentValue=10, Flag="PostDist", Callback=function(v) postActivationDistance=v end })

MainTab:CreateSection("Follow Ball Carrier")
MainTab:CreateToggle({ Name="Follow Ball Carrier", CurrentValue=false, Flag="FollowCarrier",
    Callback=function(v) if v then enableFollow() else disableFollow() end end })
MainTab:CreateKeybind({ Name="Follow Toggle Key", CurrentKeybind="H", HoldToInteract=false,
    Flag="FollowKey",
    Callback=function()
        if followEnabled then disableFollow() else enableFollow() end
    end })
MainTab:CreateSlider({ Name="Follow Offset", Range={-10,10}, Increment=1, Suffix=" studs",
    CurrentValue=-10, Flag="FollowOffset", Callback=function(v) followOffset=v end })

MainTab:CreateSection("Steal Reach  (Hitbox Extender)")
MainTab:CreateToggle({ Name="Steal Reach", CurrentValue=false, Flag="StealReach",
    Callback=function(v) stealReachEnabled=v; updateHitboxSizes() end })
MainTab:CreateSlider({ Name="Reach Multiplier", Range={10,200}, Increment=1, Suffix="×0.1",
    CurrentValue=15, Flag="ReachMult",
    Callback=function(v) stealReachMultiplier=v/10; if stealReachEnabled then updateHitboxSizes() end end })

MainTab:CreateSection("Ball Magnet")
MainTab:CreateToggle({ Name="Ball Magnet", CurrentValue=false, Flag="BallMagnet",
    Callback=function(v) magnetEnabled=v end })
MainTab:CreateKeybind({ Name="Ball Magnet Key", CurrentKeybind="M", HoldToInteract=false,
    Flag="MagnetKey", Callback=function() magnetEnabled=not magnetEnabled end })
MainTab:CreateSlider({ Name="Magnet Distance", Range={10,85}, Increment=1, Suffix=" studs",
    CurrentValue=30, Flag="MagnetDist", Callback=function(v) MagsDist=v end })

-- ───────────────── PLAYER ───────────────────────

PlayerTab:CreateSection("Speed Boost")
PlayerTab:CreateToggle({ Name="Speed Boost", CurrentValue=false, Flag="SpeedBoost",
    Callback=function(v)
        speedBoostEnabled=v
        if v then
            if speedBoostConnection then speedBoostConnection() end
            speedBoostConnection=startCFrameSpeed(desiredSpeed)
        else
            if speedBoostConnection then speedBoostConnection(); speedBoostConnection=nil end
        end
    end })
PlayerTab:CreateSlider({ Name="Speed Amount", Range={16,23}, Increment=1, Suffix=" studs/s",
    CurrentValue=16, Flag="SpeedAmt",
    Callback=function(v)
        desiredSpeed=v
        if speedBoostEnabled then
            if speedBoostConnection then speedBoostConnection() end
            speedBoostConnection=startCFrameSpeed(desiredSpeed)
        end
    end })

-- ───────────────── MISC ─────────────────────────

MiscTab:CreateSection("Visuals")
MiscTab:CreateToggle({ Name="Show BodyGyro", CurrentValue=false, Flag="ShowBG",
    Callback=function(v) if v then setBGVisible() else hideBG() end end })

MiscTab:CreateSection("Animation Changer")
MiscTab:CreateToggle({ Name="Enable Animation Changer", CurrentValue=false, Flag="AnimChanger",
    Callback=function(v) animationSpoofEnabled=v; if v then enableAnimSpoof() else disableAnimSpoof() end end })
MiscTab:CreateDropdown({ Name="Dunk Animation",
    Options={"Default","Testing","Testing2","Reverse","360","Testing3","Tomahawk","Windmill"},
    CurrentOption={"Default"}, Flag="DunkAnim",
    Callback=function(v) selectedDunkAnim=v end })
MiscTab:CreateDropdown({ Name="Emote Animation", Options=emoteOptions,
    CurrentOption={"Default"}, Flag="EmoteAnim",
    Callback=function(v) selectedEmoteAnim=EmoteAnimations[v] or "Dance_Casual" end })

MiscTab:CreateSection("Teleporter")
local placesList = {}
local PlaceDrop  = MiscTab:CreateDropdown({ Name="Select Place",
    Options={"Loading..."}, CurrentOption={"Loading..."}, Flag="TeleportPlace",
    Callback=function() end })

task.spawn(function()
    local Http = (syn and syn.request) or (http and http.request)
             or (fluxus and fluxus.request) or (request) or (http_request)
    local url  = "https://develop.roblox.com/v1/universes/"..game.GameId.."/places?limit=100"
    if Http then
        local ok, res = pcall(function()
            return Http({ Url=url, Method="GET", Headers={["Content-Type"]="application/json"} })
        end)
        if ok and res and res.Body then
            local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok2 and data and data.data then
                for _, p in ipairs(data.data) do
                    if p.name and p.id then
                        placesList[p.name..(p.isRootPlace and " (Root)" or "")] = p.id
                    end
                end
            end
        end
    end
    placesList["Current Place"] = game.PlaceId
    local names = {}
    for n in pairs(placesList) do table.insert(names, n) end
    table.sort(names)
    PlaceDrop:Refresh(names, true)
end)

MiscTab:CreateButton({ Name="Teleport to Selected Place",
    Callback=function()
        local sel = Rayfield.Flags["TeleportPlace"]
        if sel and placesList[sel] then
            Rayfield:Notify({ Title="Teleporting", Content="Going to "..sel, Duration=3 })
            TeleportService:Teleport(placesList[sel])
        end
    end })
MiscTab:CreateButton({ Name="Rejoin Current Server",
    Callback=function()
        Rayfield:Notify({ Title="Rejoining", Content="Rejoining...", Duration=3 })
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end })
MiscTab:CreateButton({ Name="Server Hop (Least Players)",
    Callback=function()
        Rayfield:Notify({ Title="Server Hop", Content="Searching...", Duration=3 })
        local servers, cursor = {}, ""
        repeat
            local ok, res = pcall(function()
                return game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId..
                    "/servers/Public?sortOrder=Asc&limit=100&cursor="..cursor)
            end)
            if ok then
                local d = HttpService:JSONDecode(res)
                cursor  = d.nextPageCursor or ""
                for _, s in pairs(d.data) do
                    if s.playing < s.maxPlayers and s.id ~= game.JobId then
                        table.insert(servers, s)
                    end
                end
            else break end
        until cursor=="" or #servers>=20
        if #servers>0 then
            table.sort(servers, function(a,b) return a.playing<b.playing end)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, player)
        else
            Rayfield:Notify({ Title="Failed", Content="No servers found.", Duration=4 })
        end
    end })

-- ───────────────── UI ───────────────────────────

UITab:CreateSection("Menu")
UITab:CreateKeybind({ Name="Toggle UI", CurrentKeybind="LeftControl",
    HoldToInteract=false, Flag="UIKeybind", Callback=function() end })

-- ────────────────────────────────────────────────
Rayfield:Notify({
    Title   = "Kali Hub Loaded",
    Content = "Basketball Legends ready!\ndiscord.gg/epNcR8Ce89",
    Duration = 5,
    Image   = "check-circle"
})
