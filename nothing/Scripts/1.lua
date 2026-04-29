-- Bond Auto Farm Script
-- By darkMaster549
-- Please Put Credits if you want modify this script.

if not game:IsLoaded() then
    game.Loaded:Wait()
end

repeat task.wait() until game.Players.LocalPlayer

print("game loaded")

-- Initialize settings
if not getgenv().BondFarmSetting then
    getgenv().BondFarmSetting = {
        tweenDuration = 18,
        AutoExecute = true,
        CheckMissedBonds = true,
    }
end

debugmode = true

local queueOnTeleport = queueonteleport or queue_on_teleport

local RE_EXECUTE_SCRIPT = [[
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    wait(0.5)
    if _G.StoppedReExecute then print("breaked re-execute") return end
    print("re-executed")
    repeat wait() until game.Players.LocalPlayer
    getgenv().BondFarmSetting = {
        tweenDuration = 18,
        AutoExecute = true,
        CheckMissedBonds = true
    }
    debugmode = true
    wait(0.1)
    print("ran script")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/DonjoScripts/Public-Scripts/refs/heads/Slap-Battles/TheFastestBondStealer.lua"))()
]]

local RE_EXECUTE_SCRIPT_NO_DEBUG = [[
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    wait(0.5)
    if _G.StoppedReExecute then print("breaked re-execute") return end
    print("re-executed")
    repeat wait() until game.Players.LocalPlayer
    getgenv().BondFarmSetting = {
        tweenDuration = 18,
        AutoExecute = true,
        CheckMissedBonds = true
    }
    wait(0.1)
    print("ran script")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/DonjoScripts/Public-Scripts/refs/heads/Slap-Battles/TheFastestBondStealer.lua"))()
]]

local BREAK_RE_EXECUTE_SCRIPT = [[
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    print("queue_on_teleport re-execute breaker ran")
    _G.StoppedReExecute = true
    wait(5)
    _G.StoppedReExecute = false
]]

-- Auto-execute on teleport setup
local function notifyNoQueueOnTeleport()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Error",
        Text = "Your executor doesn't support QueueOnTeleport, can't auto execute",
        Icon = "rbxassetid://7733658504",
        Duration = 5,
    })
end

if getgenv().BondFarmSetting.AutoExecute == true then
    if queueOnTeleport then
        if debugmode then
            queueOnTeleport(RE_EXECUTE_SCRIPT)
        else
            queueOnTeleport(RE_EXECUTE_SCRIPT_NO_DEBUG)
        end
    else
        notifyNoQueueOnTeleport()
    end
end

-- Teleport to lobby function
local function teleportToLobby()
    if queueOnTeleport then
        spawn(function()
            wait(0.1)
            while wait() do
                game:GetService("TeleportService"):Teleport(116495829188952)
            end
        end)
    end
end

-- ============================================================
-- LOBBY HANDLING (if not in main game)
-- ============================================================
if game.PlaceId ~= 70876832253163 then
    httprequest = syn and syn.request
        or http and http.request
        or http_request
        or fluxus and fluxus.request
        or request

    local function getAvailableServers()
        if not httprequest then return end

        local availableServers = {}
        local response = httprequest({
            Url = string.format(
                "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true",
                game.PlaceId
            ),
        })
        local data = game:GetService("HttpService"):JSONDecode(response.Body)

        if data and data.data then
            for _, server in next, data.data do
                if type(server) == "table"
                    and tonumber(server.playing)
                    and tonumber(server.maxPlayers)
                    and server.playing < server.maxPlayers
                    and server.id ~= game.JobId
                then
                    table.insert(availableServers, 1, server.id)
                end
            end
        end

        if #availableServers <= 0 then
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        else
            game:GetService("TeleportService"):TeleportToPlaceInstance(
                game.PlaceId,
                availableServers[math.random(1, #availableServers)],
                game.Players.LocalPlayer
            )
        end
    end

    local lobbyMessage = Instance.new("Message")
    lobbyMessage.Parent = game.CoreGui
    lobbyMessage.Text = "We're getting you into main game\nTo avoid server stuck bug, automatically server hops after 50 seconds if you're still in lobby."

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local partyZones = workspace.PartyZones

    -- Auto server hop after 48 seconds if stuck
    spawn(function()
        wait(48)
        lobbyMessage:Destroy()

        local hoppingMessage = Instance.new("Message")
        hoppingMessage.Parent = game.CoreGui
        hoppingMessage.Text = "Server hopping"

        wait(2)
        while wait() do
            pcall(getAvailableServers)
        end
    end)

    local function findEmptyPartyZone()
        for index, zone in pairs(partyZones:GetChildren()) do
            if zone.Name == "PartyZone" .. index
                and zone.BillboardGui.PlayerCount.Text == "0/4"
            then
                return zone
            end
        end
        return nil
    end

    local function moveToPartyZone(zone)
        if not zone then return false end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return false end

        local attempts = 0

        while true do
            local playerCountText = zone.BillboardGui.PlayerCount.Text
            local partyCreationGui = LocalPlayer.PlayerGui:FindFirstChild("PartyCreation")
            local partyCreated = partyCreationGui and partyCreationGui.Enabled

            if partyCreated then
                return "party_created"
            end
            if playerCountText ~= "0/4" then
                return "slot_taken"
            end

            if attempts <= 5 then
                pcall(function()
                    character.HumanoidRootPart.CFrame = zone.WorldPivot
                end)
                attempts = attempts + 1
            end

            humanoid:MoveTo(zone.WorldPivot.Position)
            task.wait()
        end
    end

    -- Main lobby loop
    (function()
        while true do
            local emptyZone = findEmptyPartyZone()

            game:GetService("ReplicatedStorage").Shared.Network.RemoteEvent.CreateParty:FireServer({
                trainId = "default",
                maxMembers = 1,
                gameMode = "Normal",
            })

            if emptyZone then
                local result = moveToPartyZone(emptyZone)

                if result == "party_created" then
                    spawn(function()
                        while wait() do
                            game:GetService("ReplicatedStorage").Shared.Network.RemoteEvent.CreateParty:FireServer({
                                trainId = "default",
                                maxMembers = 1,
                                gameMode = "Normal",
                            })
                        end
                    end)
                    return
                elseif result == "slot_taken" then
                    print("target slot is taken")
                end
            else
                task.wait()
            end

            task.wait()
        end
    end)()

    return
end

-- ============================================================
-- MAIN GAME - BOND FARM
-- ============================================================

if getgenv().AlreadyExecutedBondFarm == true then
    print("Script already ran, stopped script")
    return
end

getgenv().AlreadyExecutedBondFarm = true

-- Core references
local LocalPlayer     = game:GetService("Players").LocalPlayer
local character       = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local rootPart        = character.HumanoidRootPart
local humanoid        = character.Humanoid
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- GUI SETUP
-- ============================================================

local function addUICorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius
    corner.Parent = parent
    return corner
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InfoBondCollectedDonjoSx"
screenGui.Parent = LocalPlayer.PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.Position = UDim2.new(0.02, 0, -0.15, 0)
mainFrame.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui
addUICorner(mainFrame, UDim.new(0, 10))

local function makeLabel(size, position, text, parent)
    local label = Instance.new("TextLabel")
    label.Size = size
    label.Position = position
    label.BackgroundColor3 = Color3.new(0.05, 0.05, 0.05)
    label.Text = text
    label.TextScaled = true
    label.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    label.Font = Enum.Font.Arcade
    label.Parent = parent
    addUICorner(label, UDim.new(0, 5))
    return label
end

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0.9, 0, 0.15, 0)
titleLabel.Position = UDim2.new(0.05, 0, 0.03, 0)
titleLabel.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
titleLabel.Text = "Dead rails • Bond auto farm GUI V3.75"
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
titleLabel.Font = Enum.Font.Arcade
titleLabel.Parent = mainFrame
addUICorner(titleLabel, UDim.new(0, 5))

local creditsLabel = Instance.new("TextLabel")
creditsLabel.Size = UDim2.new(0.9, 0, 0.08, 0)
creditsLabel.Position = UDim2.new(0.05, 0, 0.9, 0)
creditsLabel.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
creditsLabel.Text = "Script made by DonjoSyntax(DonjoSX)"
creditsLabel.TextScaled = true
creditsLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
creditsLabel.Font = Enum.Font.Arcade
creditsLabel.Parent = mainFrame
addUICorner(creditsLabel, UDim.new(0, 5))

local runTimeLabel    = makeLabel(UDim2.new(0.8, 0, 0.08, 0), UDim2.new(0.1, 0, 0.3, 0), "Run time: 0 Second(s)", mainFrame)
local elapsedLabel    = makeLabel(UDim2.new(0.8, 0, 0.08, 0), UDim2.new(0.1, 0, 0.4, 0), "Elapsed time: 0 Second(s)", mainFrame)
local statusLabel     = makeLabel(UDim2.new(0.8, 0, 0.08, 0), UDim2.new(0.1, 0, 0.2, 0), "Status: None (if it stuck, it's a bug so please report this to me)", mainFrame)
local bondsLabel      = makeLabel(UDim2.new(0.7, 0, 0.2, 0),  UDim2.new(0.15, 0, 0.5, 0), "Bond(s) Collected: 0", mainFrame)

-- Return to lobby button
local lobbyButton = Instance.new("TextButton")
lobbyButton.Size = UDim2.new(0.1, 0, 0.15, 0)
lobbyButton.Position = UDim2.new(0.15, 0, 0.725, 0)
lobbyButton.BackgroundColor3 = Color3.new(0, 0, 0)
lobbyButton.Text = "Return to lobby"
lobbyButton.TextScaled = true
lobbyButton.BorderColor3 = Color3.new(1, 1, 1)
lobbyButton.TextColor3 = Color3.new(0.8, 0.8, 0.8)
lobbyButton.Font = Enum.Font.Arcade
lobbyButton.Parent = mainFrame

lobbyButton.MouseButton1Click:Connect(function()
    if queueOnTeleport then
        queueOnTeleport(BREAK_RE_EXECUTE_SCRIPT)
    end
    game:GetService("TeleportService"):Teleport(116495829188952)
end)

-- Break re-executor button (only if AutoExecute is on)
if getgenv().BondFarmSetting.AutoExecute == true then
    local breakButton = Instance.new("TextButton")
    breakButton.Size = UDim2.new(0.1, 0, 0.15, 0)
    breakButton.Position = UDim2.new(0.275, 0, 0.725, 0)
    breakButton.BackgroundColor3 = Color3.new(0, 0, 0)
    breakButton.Text = "Break re-executor"
    breakButton.TextScaled = true
    breakButton.BorderColor3 = Color3.new(1, 1, 1)
    breakButton.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    breakButton.Font = Enum.Font.Arcade
    breakButton.Parent = mainFrame

    breakButton.MouseButton1Click:Connect(function()
        if queueOnTeleport then
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Notification!",
                Text = "Stopped in-script auto executor (does not stop the auto executor of your executor)",
                Icon = "rbxassetid://7733658504",
                Duration = 5,
            })
            breakButton:Destroy()
            queueOnTeleport(BREAK_RE_EXECUTE_SCRIPT)
        else
            notifyNoQueueOnTeleport()
        end
    end)
end

-- ============================================================
-- TIMER LOOPS
-- ============================================================

local startTime = os.time()

-- Run time display (uses DistributedGameTime)
spawn(function()
    while wait() do
        local currentCamera = workspace.CurrentCamera

        if not debugmode then
            currentCamera.CameraType = Enum.CameraType.Scriptable
            currentCamera.CFrame = CFrame.new(0, -1000, 0)
        end

        -- Anti-tamper checks
        if not screenGui or screenGui.Enabled == false then while true do end end
        if not mainFrame or mainFrame.Visible == false then while true do end end
        if not creditsLabel or creditsLabel.Text ~= "Script made by darkMaster549" then while true do end end

        local totalSeconds = math.floor(workspace.DistributedGameTime)
        local totalMinutes = math.floor(totalSeconds / 60)
        local totalHours   = math.floor(totalMinutes / 60)
        local secs = totalSeconds - totalMinutes * 60
        local mins = totalMinutes - totalHours * 60

        if totalHours >= 1 then
            runTimeLabel.Text = string.format("Run time: %d Hour(s), %d Minute(s), %d Second(s)", totalHours, mins, secs)
        elseif mins >= 1 then
            runTimeLabel.Text = string.format("Run time: %d Minute(s), %d Second(s)", mins, secs)
        else
            runTimeLabel.Text = string.format("Run time: %d Second(s)", secs)
        end
    end
end)

-- Elapsed time display (uses os.time)
spawn(function()
    while true do
        local elapsed = os.time() - startTime
        local hours   = math.floor(elapsed / 3600)
        local mins    = math.floor(elapsed % 3600 / 60)
        local secs    = elapsed % 60

        if hours > 0 then
            elapsedLabel.Text = string.format("Elapsed time: %d Hour(s), %d Minute(s), %d Second(s)", hours, mins, secs)
        elseif mins > 0 then
            elapsedLabel.Text = string.format("Elapsed time: %d Minute(s), %d Second(s)", mins, secs)
        else
            elapsedLabel.Text = string.format("Elapsed time: %d Second(s)", secs)
        end

        wait()
    end
end)

-- ============================================================
-- BOND COLLECTION TRACKING
-- ============================================================

local bondsCollected = 0

workspace.DescendantRemoving:Connect(function(removed)
    if removed.Name == "InfoBondCollectedDonjoSx" then
        setclipboard("sussy activity detected!")
        while true do end
    end

    if removed.Name ~= "Bond" or humanoid.Health == 0 then return end

    local pos = nil
    if removed:IsA("Model") then
        pos = removed.WorldPivot.Position
    elseif removed:IsA("BasePart") then
        pos = removed.Position
    end

    if pos and (rootPart.Position - pos).Magnitude <= 700 then
        bondsCollected = bondsCollected + 1
        bondsLabel.Text = "Bond(s) Collected: " .. bondsCollected
    end
end)

-- ============================================================
-- BOND TRACKING TABLE
-- ============================================================

local initialBondCount = bondsCollected
local trackedBonds = {}

-- Collect existing bonds
for _, item in pairs(workspace.RuntimeItems:GetChildren()) do
    if item.Name == "Bond" and not trackedBonds[item] then
        table.insert(trackedBonds, item)
    end
end

-- Track newly added bonds
workspace.RuntimeItems.ChildAdded:Connect(function(child)
    if child.Name == "Bond" and not trackedBonds[child] then
        table.insert(trackedBonds, child)
    end
end)

-- ============================================================
-- FLIGHT SYSTEM
-- ============================================================

local flightHeartbeat = nil
local flightCharacterAdded = nil

local function stopFlight()
    pcall(function()
        local hrp = LocalPlayer.Character.HumanoidRootPart
        hrp:FindFirstChild("bodyvelocityFlight"):Destroy()
        hrp:FindFirstChild("bodyGyroFlight"):Destroy()
        LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid").PlatformStand = false
        flightCharacterAdded:Disconnect()
        flightHeartbeat:Disconnect()
    end)
end

local function startFlight(speedMultiplier)
    stopFlight()

    LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid").PlatformStand = false

    local speed   = speedMultiplier or 1
    local hrp     = LocalPlayer.Character.HumanoidRootPart
    local camera  = workspace.CurrentCamera
    local zero    = Vector3.new(0, 0, 0)
    local maxForce = Vector3.new(9e9, 9e9, 9e9)
    local controlModule = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

    local function createFlightObjects(targetHrp)
        local bv = Instance.new("BodyVelocity")
        bv.Name = "bodyvelocityFlight"
        bv.Parent = targetHrp
        bv.MaxForce = zero
        bv.Velocity = zero

        local bg = Instance.new("BodyGyro")
        bg.Name = "bodyGyroFlight"
        bg.Parent = targetHrp
        bg.MaxTorque = maxForce
        bg.P = 1000
        bg.D = 50
    end

    createFlightObjects(hrp)

    flightCharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
        createFlightObjects(hrp)
    end)

    flightHeartbeat = RunService.RenderStepped:Connect(function()
        hrp = character.HumanoidRootPart
        camera = workspace.CurrentCamera

        local charHumanoid = LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        local bv = hrp:FindFirstChild("bodyvelocityFlight")
        local bg = hrp:FindFirstChild("bodyGyroFlight")

        if charHumanoid and hrp and bv and bg then
            bv.MaxForce = maxForce
            bg.MaxTorque = maxForce
            bg.CFrame = camera.CoordinateFrame
            bv.Velocity = zero

            local moveVec = controlModule:GetMoveVector()

            if moveVec.X ~= 0 then
                bv.Velocity = bv.Velocity + camera.CFrame.RightVector * (moveVec.X * (speed * 50))
            end
            if moveVec.Z ~= 0 then
                bv.Velocity = bv.Velocity - camera.CFrame.LookVector * (moveVec.Z * (speed * 50))
            end
        end
    end)
end

-- ============================================================
-- BOND COLLECTION LOGIC
-- ============================================================

local TRAIN_START_POS = Vector3.new(54, 3, 29970)
local TRAIN_END_POS   = Vector3.new(-420, 10, -49040)
local TWEEN_DURATION  = getgenv().BondFarmSetting.tweenDuration or 20

local function getNearbyBonds()
    local runtimeItems = workspace:FindFirstChild("RuntimeItems")
    if not runtimeItems then return {} end

    local bonds = {}
    for _, item in pairs(runtimeItems:GetChildren()) do
        if item.Name == "Bond" then
            local pos = item.WorldPivot.Position
            if (rootPart.Position - pos).Magnitude < 10000 then
                table.insert(bonds, item)
            end
        end
    end

    return bonds
end

local function collectNearestBond()
    local nearestBond = nil
    local nearestDist = math.huge

    for _, bond in ipairs(getNearbyBonds()) do
        if bond and bond.Parent and bond:IsA("Model") then
            local dist = (rootPart.Position - bond.WorldPivot.Position).Magnitude
            if dist < nearestDist then
                nearestBond = bond
                nearestDist = dist
            end
        end
    end

    if nearestBond then
        repeat
            character.HumanoidRootPart:PivotTo(nearestBond.WorldPivot)
            ReplicatedStorage.Shared.Network.RemotePromise.Remotes.C_ActivateObject:FireServer(nearestBond)
            task.wait()
        until not (nearestBond and nearestBond.Parent)
    end
end

-- ============================================================
-- ANTI-CHEAT BYPASS & SETUP
-- ============================================================

local horseModel  = ReplicatedStorage.Assets.Entities.Animals.Horse.Model_Horse
local vehicleSeat = horseModel.VehicleSeat
local playerHumanoid = (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()):WaitForChild("Humanoid")

-- Sit in vehicle seat briefly to bypass anti-cheat
vehicleSeat.Parent = workspace
vehicleSeat:Sit(playerHumanoid)
wait(0.5)
vehicleSeat.Parent = horseModel

local backpack = LocalPlayer:WaitForChild("Backpack")

local function dropAllTools()
    -- Drop tools from backpack
    for _, tool in pairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name ~= "Sack" then
            LocalPlayer.Character.Humanoid:EquipTool(tool)
            ReplicatedStorage.Remotes.Tool.DropTool:FireServer(tool)
        end
    end

    -- Drop tools from character
    for _, tool in pairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool.Name ~= "Sack" then
            ReplicatedStorage.Remotes.Tool.DropTool:FireServer(tool)
        end
    end
end

-- Disable other ScreenGuis
for _, gui in pairs(game.CoreGui:GetChildren()) do
    if gui:IsA("ScreenGui") and gui.Name ~= "InfoBondCollectedDonjoSx" then
        gui.Enabled = false
    end
end

-- Keep sack equipped
spawn(function()
    while wait() do
        humanoid.JumpPower = 0
        pcall(function()
            spawn(function()
                for _, tool in pairs(backpack:GetChildren()) do
                    if tool.Name == "Sack" then
                        LocalPlayer.Character.Humanoid:EquipTool(tool)
                        wait(1)
                        LocalPlayer.Character.Humanoid:UnequipTools()
                    end
                end
            end)
        end)
    end
end)

dropAllTools()

statusLabel.Text = "Status: Bypassed anti-cheat"

startFlight(5)

-- ============================================================
-- DEATH / DISCONNECT HANDLERS
-- ============================================================

local isActive = true

humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
    if not humanoid.Sit and isActive then
        stopFlight()
        humanoid.Health = 0
        teleportToLobby()
        ReplicatedStorage.Remotes.EndDecision:FireServer(false)
        isActive = false
    end
end)

humanoid:GetPropertyChangedSignal("Health"):Connect(function()
    if humanoid.Health == 0 then
        statusLabel.Text = "Status: Finished collecting bonds, rejoining"
        stopFlight()
        ReplicatedStorage.Remotes.EndDecision:FireServer(false)
    end
end)

-- ============================================================
-- MAIN FARM LOOP
-- ============================================================

statusLabel.Text = "Status: Starting script"

-- Teleport to train start
LocalPlayer.Character.HumanoidRootPart:PivotTo(CFrame.new(55, 9, 29888))

-- Nearby bond vacuum loop (runs in background)
spawn(function()
    while humanoid.Health ~= 0 do
        for _, item in pairs(workspace.RuntimeItems:GetChildren()) do
            if item.Name == "Bond" then
                local pos = item:IsA("Model") and item.WorldPivot.Position or nil
                if pos and (rootPart.Position - pos).Magnitude <= 80 then
                    ReplicatedStorage.Shared.Network.RemotePromise.Remotes.C_ActivateObject:FireServer(item)
                end
            end
        end
        task.wait()
    end
end)

statusLabel.Text = "Status: Collecting bonds"

-- Teleport to starting position a few times
for _ = 1, 5 do
    task.wait()
    LocalPlayer.Character.HumanoidRootPart:PivotTo(CFrame.new(55, 9, 29888))
end

-- Main tween loop: move along train track, collect bonds along the way
while true do
    -- Stop all playing animations
    local animTracker = character:FindFirstChildOfClass("Humanoid") or character:FindFirstChildOfClass("AnimationController")
    for _, track in next, animTracker:GetPlayingAnimationTracks() do
        track:Stop()
    end

    -- If player got kicked off seat, kill and rejoin
    if humanoid.Sit == false then
        humanoid.Health = 0
        teleportToLobby()
        print("stuck while bypassing teleport, reseted player")
        break
    end

    local currentPos = rootPart.Position
    local distToEnd  = (currentPos - TRAIN_END_POS).Magnitude

    -- Stop if near end and no bonds left
    if #getNearbyBonds() <= 1 and distToEnd <= 10 then
        break
    end

    rootPart.CFrame = CFrame.new(currentPos)

    -- Calculate tween duration proportionally
    local tweenTime = TWEEN_DURATION * ((TRAIN_END_POS - currentPos).Magnitude / (TRAIN_END_POS - TRAIN_START_POS).Magnitude)
    local tween = TweenService:Create(
        rootPart,
        TweenInfo.new(tweenTime, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(TRAIN_END_POS) }
    )

    tween:Play()

    local bondFoundDuringTween = false

    while tween.PlaybackState == Enum.PlaybackState.Playing do
        wait(0.1)

        -- If a bond appeared, cancel tween and go collect it
        if #trackedBonds > 0 then
            tween:Cancel()

            local savedPos = rootPart.Position
            collectNearestBond()
            character.HumanoidRootPart:PivotTo(CFrame.new(savedPos))

            bondFoundDuringTween = true
            break
        end
    end

    if not bondFoundDuringTween then
        break
    end
end

-- ============================================================
-- CLEANUP
-- ============================================================

wait()
ReplicatedStorage.Remotes.EndDecision:FireServer(false)

humanoid.Sit = false
humanoid.Health = 0

teleportToLobby()
wait()

-- Report missed bonds
if getgenv().BondFarmSetting.CheckMissedBonds == true then
    local summaryMessage = Instance.new("Message")
    summaryMessage.Parent = game.CoreGui

    local totalDetected = #trackedBonds
    local missed = totalDetected - initialBondCount

    if missed <= 0 then
        summaryMessage.Text = "No bonds were missed!\nTotal Bonds Detected: " .. totalDetected .. " bond(s)."
    else
        summaryMessage.Text = "Bonds Missed: " .. missed .. " bond(s)\nTotal Bonds Detected: " .. totalDetected .. " bond(s)."
    end

    wait(10)
    summaryMessage:Destroy()
end
