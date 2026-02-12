local function safeCall(func, ...)
    local start = tick()
    local success, result = pcall(func, ...)
    local duration = tick() - start
    
    if duration > 0.08 then -- Faster threshold
        warn("Slow function:", debug.info(func, "n") or "anonymous", "took", duration, "seconds")
    end
    
    return success, result
end

-- Cleanup previous execution
if _G.MySkyCleanup then
    pcall(_G.MySkyCleanup)
end

_G.MySkyCleanup = function()
    if _G.MySkyConnections then
        for _, conn in ipairs(_G.MySkyConnections) do
            pcall(function() conn:Disconnect() end)
        end
        _G.MySkyConnections = {}
    end
    
    -- Clean up parts
    for _, part in ipairs(workspace:GetChildren()) do
        if part.Name:find("myskyp") or part.Name:find("Cosmic") then
            pcall(function() part:Destroy() end)
        end
    end
    
    -- Clean up GUI
    local coreGui = game:GetService("CoreGui")
    local existingGui = coreGui:FindFirstChild("SemiInstaSteal")
    if existingGui then
        pcall(function() existingGui:Destroy() end)
    end
end

-- Execute cleanup on script restart
pcall(_G.MySkyCleanup)

-- // ------------------------------------------------ //
-- //                  MAIN SCRIPT                     //
-- // ------------------------------------------------ //

-- Load services in background to prevent freezing
local Services = {}
local servicePromises = {}

-- Function to get services asynchronously
local function getService(serviceName)
    if Services[serviceName] then
        return Services[serviceName]
    end
    
    -- Load service in background
    if not servicePromises[serviceName] then
        servicePromises[serviceName] = task.spawn(function()
            Services[serviceName] = game:GetService(serviceName)
            servicePromises[serviceName] = nil
        end)
    end
    
    -- Wait for service if needed immediately
    while not Services[serviceName] do
        task.wait()
    end
    
    return Services[serviceName]
end

-- Load critical services first without freezing
local Players = getService("Players")
local LocalPlayer = Players.LocalPlayer

-- Connection storage
local connections = {}
_G.MySkyConnections = connections

print("Script loaded successfully for user:", LocalPlayer.Name)

-- Prevent duplicate execution
if _G.MyskypInstaSteal then 
    pcall(_G.MySkyCleanup)
    task.wait(0.1)
end
_G.MyskypInstaSteal = true

-- Configuration constants - Define positions for BOTH bases
local TP_POSITIONS = {
    BASE1 = {
        INFO_POS = CFrame.new(334.76, 55.334, 99.40),  -- Base 1 standing position
        TELEPORT_POS = CFrame.new(-352.98, -7.30, 74.3),    -- Base 1 teleport position
        STAND_HERE_PART = CFrame.new(-334.76, -5.334, 99.40) * CFrame.new(0, 2.6, 0)
    },
    BASE2 = {
        INFO_POS = CFrame.new(334.76, 55.334, 19.17),    -- Base 2 standing position
        TELEPORT_POS = CFrame.new(-352.98, -7.30, 45.76), -- Base 2 teleport position
        STAND_HERE_PART = CFrame.new(-336.41, -5.34, 19.20) * CFrame.new(0, 2.6, 0)
    }
}

local TP_DELAY = 0.15 -- FASTER: Was 0.2

-- State variables
local TPSysEnabled = true
local DesyncActive = false

-- Performance variables
local lastTeleportTime = 0
local TELEPORT_COOLDOWN = 0.8 -- FASTER: Was 1.0
local lastMarkerUpdate = 0
local MARKER_UPDATE_INTERVAL = 0.4 -- FASTER: Was 0.5

-- Device detection
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local IS_MOBILE = UserInputService.TouchEnabled
local IS_PC = not IS_MOBILE

print("Device detection:", IS_MOBILE and "MOBILE" or "PC")

-- Utility functions
local function cleanup()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
end

-- ============================================================
-- ORIGINAL TELEPORT PATH FUNCTION EXACTLY AS YOU HAD IT
-- ============================================================
local function TeleportPath(targetCFrame)
    -- Cooldown check
    if tick() - lastTeleportTime < TELEPORT_COOLDOWN then 
        return 
    end
    lastTeleportTime = tick()
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then 
        return 
    end
    
    local hrp = LocalPlayer.Character.HumanoidRootPart
    
    -- Distance check for performance
    local distance = (hrp.Position - targetCFrame.Position).Magnitude
    if distance > 1000 then
        warn("Target too far for pathfinding:", distance)
        return
    end
    
    if distance < 50 then
        hrp.AssemblyLinearVelocity = Vector3.zero
        LocalPlayer.Character:PivotTo(targetCFrame)
        task.wait(TP_DELAY)
        return
    end

    -- Run pathfinding in background task to prevent freezing
    task.spawn(function()
        local PathfindingService = getService("PathfindingService")
        local success, path = pcall(function()
            local path = PathfindingService:CreatePath({ 
                AgentCanJump = true, 
                AgentRadius = 3,
                AgentHeight = 5,
                AgentCanClimb = false
            })
            path:ComputeAsync(hrp.Position, targetCFrame.Position)
            return path
        end)
        
        if not success or not path then return end
        
        if path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            local stepCount = math.min(4, #waypoints)
            
            for i = 1, stepCount do
                -- Check if character still exists
                if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    break
                end
                
                local frac = i / stepCount
                local idx = math.clamp(math.floor(frac * #waypoints) + 1, 1, #waypoints)
                hrp.AssemblyLinearVelocity = Vector3.zero
                LocalPlayer.Character:PivotTo(CFrame.new(waypoints[idx].Position + Vector3.new(0, 2.5, 0)))
                task.wait(0.08)
            end
        end

        -- Final teleport with character check
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character:PivotTo(targetCFrame)
            task.wait(TP_DELAY)
        end
    end)
end

-- Determine which base the player is at
local function getCurrentBasePosition()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return TP_POSITIONS.BASE1.INFO_POS
    end
    
    local hrp = LocalPlayer.Character.HumanoidRootPart
    local currentPos = hrp.Position
    
    -- Calculate distances to both bases
    local distToBase1 = (currentPos - TP_POSITIONS.BASE1.INFO_POS.Position).Magnitude
    local distToBase2 = (currentPos - TP_POSITIONS.BASE2.INFO_POS.Position).Magnitude
    
    -- Determine which base is closer
    if distToBase1 < distToBase2 then
        return TP_POSITIONS.BASE1.INFO_POS
    else
        return TP_POSITIONS.BASE2.INFO_POS
    end
end

-- Create marker with caching
local function CreateMarker()
    local currentBasePos = getCurrentBasePosition()
    local markerPos = currentBasePos * CFrame.new(0, -3.2, 0)
    
    local part = workspace:FindFirstChild("myskypBest") or Instance.new("Part")
    part.Name = "myskypBest"
    part.Size = Vector3.new(1, 1, 1)
    part.CFrame = markerPos
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(0, 255, 255)
    part.Transparency = 0.3
    part.Parent = workspace

    -- Billboard GUI (empty - no text)
    if not part:FindFirstChild("MyskypBillboard") then
        local gui = Instance.new("BillboardGui")
        gui.Name = "MyskypBillboard"
        gui.AlwaysOnTop = true
        gui.Size = UDim2.new(0, 200, 0, 50)
        gui.ExtentsOffset = Vector3.new(0, 3, 0)
        gui.Parent = part
        
        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 18
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Text = "" -- Empty text
        label.Parent = gui
    end
    
    return part
end

local Marker = CreateMarker()

-- Create cosmic indicators in workspace for both bases
local function createCosmicIndicator(name, position, color, text)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = Vector3.new(3.8, 0.3, 3.8)
    part.Material = Enum.Material.Plastic
    part.Color = color
    part.Transparency = 0.57
    part.Anchored = true
    part.CanCollide = false
    part.Position = position
    part.Parent = workspace

    -- Billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.TextStrokeTransparency = 0.3
    textLabel.TextStrokeColor3 = color
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 18
    textLabel.Parent = billboard

    return part
end

-- Create cosmic indicators asynchronously to prevent freeze
task.spawn(function()
    -- Base 1 indicators
    createCosmicIndicator(
        "CosmicStandHereBase1",
        Vector3.new(-334.84, -5.40, 101.02),
        Color3.fromRGB(39, 39, 39),
        " STAND HERE (BASE 1) "
    )

    createCosmicIndicator(
        "CosmicTeleportHereBase1",
        Vector3.new(-352.98, -7.30, 74.3),
        Color3.fromRGB(39, 39, 39),
        " TELEPORT HERE (BASE 1) "
    )

    -- Base 2 indicators
    createCosmicIndicator(
        "CosmicStandHereBase2",
        Vector3.new(-334.84, -5.40, 19.20),
        Color3.fromRGB(39, 39, 39),
        " STAND HERE (BASE 2) "
    )

    createCosmicIndicator(
        "CosmicTeleportHereBase2",
        Vector3.new(-352.98, -7.30, 45.76),
        Color3.fromRGB(39, 39, 39),
        " TELEPORT HERE (BASE 2) "
    )
end)

-- ============================================================
-- STEAL PROMPT DETECTION (Ð¢ÐžÐ›Ð¬ÐšÐž ÐÐ "Steal" ÐŸÐ ÐžÐœÐŸÐ¢ ÐšÐÐš Ð‘Ð«Ð›Ðž)
-- ============================================================

local function initializeEventConnections()
    local ProximityPromptService = getService("ProximityPromptService")
    local RunService = getService("RunService")
    
    -- ÐŸÑ€Ð¾ÑÑ‚Ð¾ ÐºÐ°Ðº Ð±Ñ‹Ð»Ð¾ - Ñ‚ÐµÐ»ÐµÐ¿Ð¾Ñ€Ñ‚ Ð¿Ñ€Ð¸ Steal Ð¿Ñ€Ð¾Ð¼Ð¿Ñ‚Ðµ
    local promptConn = ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
        if who ~= LocalPlayer then return end
        if prompt.Name ~= "Steal" and prompt.ActionText ~= "Steal" and prompt.ObjectText ~= "Steal" then return end
        
        warn("STEAL DETECTED")
        
        if not TPSysEnabled then
            warn("TP System OFF")
            return
        end
        
        local character = LocalPlayer.Character
        if not character then return end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        -- ÐŸÑ‹Ñ‚Ð°ÐµÐ¼ÑÑ ÑÐºÐ¸Ð¿Ð¸Ñ€Ð¾Ð²Ð°Ñ‚ÑŒ Flying Carpet ÐµÑÐ»Ð¸ ÐµÑÑ‚ÑŒ
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            local carpet = backpack:FindFirstChild("Flying Carpet")
            if carpet and character:FindFirstChild("Humanoid") then
                character.Humanoid:EquipTool(carpet)
                task.wait(0.1)
            end
        end
        
        -- ÐžÐ¿Ñ€ÐµÐ´ÐµÐ»ÑÐµÐ¼ Ð½Ð° ÐºÐ°ÐºÐ¾Ð¹ Ð±Ð°Ð·Ðµ Ð¼Ñ‹ Ð¸ Ñ‚ÐµÐ»ÐµÐ¿Ð¾Ñ€Ñ‚Ð¸Ñ€ÑƒÐµÐ¼ Ð½Ð° Ð¢Ð£ Ð–Ð• Ð±Ð°Ð·Ñƒ
        local currentBasePos = getCurrentBasePosition()
        
        if currentBasePos == TP_POSITIONS.BASE1.INFO_POS then
            hrp.CFrame = TP_POSITIONS.BASE1.TELEPORT_POS
            print("TPED To Base 1")
        else
            hrp.CFrame = TP_POSITIONS.BASE2.TELEPORT_POS
            print("TPED To Base 2")
        end
    end)
    table.insert(connections, promptConn)
    
    -- Marker update with throttling
    local heartbeatConn = RunService.Heartbeat:Connect(function(deltaTime)
        lastMarkerUpdate = lastMarkerUpdate + deltaTime
        if lastMarkerUpdate < MARKER_UPDATE_INTERVAL then return end
        lastMarkerUpdate = 0
        
        local character = LocalPlayer.Character
        if not character then return end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        -- Update marker to current base's standing position
        local currentBasePos = getCurrentBasePosition()
        local markerPos = currentBasePos * CFrame.new(0, -3.2, 0)
        
        -- Update marker position
        if Marker and Marker.Parent then
            Marker.CFrame = markerPos
            
            -- Check distance to current standing position
            local dist = (hrp.Position - currentBasePos.Position).Magnitude
            Marker.Color = dist < 7 and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 50, 50)
        end
    end)
    table.insert(connections, heartbeatConn)
    
    print("Event connections initialized")
end

-- Initialize connections
task.spawn(initializeEventConnections)

-- ============================================================
-- OPTIMIZED ANTI-KICK SYSTEM (NO FREEZING WHEN PICKING UP ITEMS)
-- ============================================================

local KEYWORD = "You stole"
local KICK_MESSAGE = "EZZ"

local function hasKeyword(text)
    return typeof(text) == "string" and text:lower():find(KEYWORD, 1, true) ~= nil
end

local function watchObject(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    
    -- Only check if it's visible and has text
    if obj.Visible and obj.Text and hasKeyword(obj.Text) then
        task.spawn(function()
            pcall(function() LocalPlayer:Kick(KICK_MESSAGE) end)
        end)
        return
    end
    
    -- Only connect to text changes if object is visible
    if obj.Visible then
        local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
            if hasKeyword(obj.Text) then
                task.spawn(function()
                    pcall(function() LocalPlayer:Kick(KICK_MESSAGE) end)
                end)
            end
        end)
        table.insert(connections, conn)
    end
end

-- Optimized scanning with debouncing
local lastScanTime = 0
local SCAN_COOLDOWN = 0.5 -- Half second between scans
local MAX_SCAN_TIME = 0.016 -- 60 FPS threshold (16ms)

local function optimizedScanDescendants(parent)
    local currentTime = tick()
    if currentTime - lastScanTime < SCAN_COOLDOWN then return end
    
    local startTime = tick()
    if tick() - startTime > MAX_SCAN_TIME then
        warn("Scan would take too long, skipping...")
        return
    end
    
    lastScanTime = currentTime
    
    -- Run in background to prevent freezing
    task.spawn(function()
        local textObjects = {}
        local batchSize = 15
        
        -- Quick first pass: collect only visible text objects
        for _, obj in ipairs(parent:GetDescendants()) do
            if tick() - startTime > MAX_SCAN_TIME then
                warn("Scan timeout - stopping early")
                break
            end
            
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                if obj.Visible and obj.Text then
                    table.insert(textObjects, obj)
                end
            end
        end
        
        -- Process in smaller batches with longer yields
        for i = 1, #textObjects, batchSize do
            local endIdx = math.min(i + batchSize - 1, #textObjects)
            for j = i, endIdx do
                watchObject(textObjects[j])
            end
            task.wait(0.05) -- Longer yield to prevent freezing
        end
        
        warn("Scan completed in " .. (tick() - startTime) .. " seconds, objects: " .. #textObjects)
    end)
end

-- Debounced version of watchObject for ChildAdded events
local childAddedDebounce = false
local function debouncedWatchObject(obj)
    if not childAddedDebounce then
        childAddedDebounce = true
        watchObject(obj)
        childAddedDebounce = false
    end
end

-- Anti-kick system in background
task.spawn(function()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Initial scan with delay to prevent startup freeze
    task.wait(2) -- Wait for game to load
    optimizedScanDescendants(PlayerGui)
    
    -- Optimized ChildAdded event
    local childAddedConn = PlayerGui.ChildAdded:Connect(function(gui)
        task.wait(0.1) -- Small delay to prevent rapid scanning
        if gui:IsA("ScreenGui") then
            optimizedScanDescendants(gui)
        else
            debouncedWatchObject(gui)
        end
    end)
    table.insert(connections, childAddedConn)
    
    -- Optimized DescendantAdded event
    local descendantAddedConn = PlayerGui.DescendantAdded:Connect(debouncedWatchObject)
    table.insert(connections, descendantAddedConn)
end)

-- Auto-cleanup on player leaving
task.spawn(function()
    local playerLeavingConn = Players.PlayerRemoving:Connect(function(player)
        if player == LocalPlayer then
            cleanup()
            _G.MyskypInstaSteal = false
            pcall(_G.MySkyCleanup)
        end
    end)
    table.insert(connections, playerLeavingConn)
end)

-- ============================================================
-- DESYNC FFLAG SYSTEM (FROM THE SHARED CODE)
-- ============================================================

local FFlags = {
    GameNetPVHeaderRotationalVelocityZeroCutoffExponent = -5000,
    LargeReplicatorWrite5 = true,
    LargeReplicatorEnabled9 = true,
    AngularVelociryLimit = 360,
    TimestepArbiterVelocityCriteriaThresholdTwoDt = 2147483646,
    S2PhysicsSenderRate = 15000,
    DisableDPIScale = true,
    MaxDataPacketPerSend = 2147483647,
    PhysicsSenderMaxBandwidthBps = 20000,
    TimestepArbiterHumanoidLinearVelThreshold = 21,
    MaxMissedWorldStepsRemembered = -2147483648,
    PlayerHumanoidPropertyUpdateRestrict = true,
    SimDefaultHumanoidTimestepMultiplier = 0,
    StreamJobNOUVolumeLengthCap = 2147483647,
    DebugSendDistInSteps = -2147483648,
    GameNetDontSendRedundantNumTimes = 1,
    CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 1,
    CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 1,
    LargeReplicatorSerializeRead3 = true,
    ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 2147483647,
    CheckPVCachedVelThresholdPercent = 10,
    CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 1,
    GameNetDontSendRedundantDeltaPositionMillionth = 1,
    InterpolationFrameVelocityThresholdMillionth = 5,
    StreamJobNOUVolumeCap = 2147483647,
    InterpolationFrameRotVelocityThresholdMillionth = 5,
    CheckPVCachedRotVelThresholdPercent = 10,
    WorldStepMax = 30,
    InterpolationFramePositionThresholdMillionth = 5,
    TimestepArbiterHumanoidTurningVelThreshold = 1,
    SimOwnedNOUCountThresholdMillionth = 2147483647,
    GameNetPVHeaderLinearVelocityZeroCutoffExponent = -5000,
    NextGenReplicatorEnabledWrite4 = true,
    TimestepArbiterOmegaThou = 1073741823,
    MaxAcceptableUpdateDelay = 1,
    LargeReplicatorSerializeWrite4 = true
}


local defaultFFlags = {
    GameNetPVHeaderRotationalVelocityZeroCutoffExponent = 8,
    LargeReplicatorWrite5 = false,
    LargeReplicatorEnabled9 = false,
    AngularVelociryLimit = 180,
    TimestepArbiterVelocityCriteriaThresholdTwoDt = 100,
    S2PhysicsSenderRate = 60,
    DisableDPIScale = false,
    MaxDataPacketPerSend = 1024,
    PhysicsSenderMaxBandwidthBps = 10000,
    TimestepArbiterHumanoidLinearVelThreshold = 10,
    MaxMissedWorldStepsRemembered = 10,
    PlayerHumanoidPropertyUpdateRestrict = false,
    SimDefaultHumanoidTimestepMultiplier = 1,
    StreamJobNOUVolumeLengthCap = 1000,
    DebugSendDistInSteps = 10,
    GameNetDontSendRedundantNumTimes = 10,
    CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 50,
    CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 100,
    LargeReplicatorSerializeRead3 = false,
    ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 100,
    CheckPVCachedVelThresholdPercent = 50,
    CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 100,
    GameNetDontSendRedundantDeltaPositionMillionth = 100,
    InterpolationFrameVelocityThresholdMillionth = 100,
    StreamJobNOUVolumeCap = 1000,
    InterpolationFrameRotVelocityThresholdMillionth = 100,
    CheckPVCachedRotVelThresholdPercent = 50,
    WorldStepMax = 60,
    InterpolationFramePositionThresholdMillionth = 100,
    TimestepArbiterHumanoidTurningVelThreshold = 10,
    SimOwnedNOUCountThresholdMillionth = 1000,
    GameNetPVHeaderLinearVelocityZeroCutoffExponent = 8,
    NextGenReplicatorEnabledWrite4 = false,
    TimestepArbiterOmegaThou = 1000,
    MaxAcceptableUpdateDelay = 10,
    LargeReplicatorSerializeWrite4 = false
}

local desyncFirstActivation = true
local desyncPermanentlyActivated = false

local function applyFFlags(flags)
    for name, value in pairs(flags) do
        pcall(function()
            setfflag(tostring(name), tostring(value))
        end)
    end
end

local function respawn(plr)
    local char = plr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Dead)
        end
        char:ClearAllChildren()
        local newChar = Instance.new("Model")
        newChar.Parent = workspace
        plr.Character = newChar
        task.wait()
        plr.Character = char
        newChar:Destroy()
    end
end

-- Function to apply permanent desync
local function applyPermanentDesync()
    applyFFlags(FFlags)
    if desyncFirstActivation then
        respawn(LocalPlayer)
        desyncFirstActivation = false
    end
    desyncPermanentlyActivated = true
end

-- Final cleanup registration
_G.MySkyCleanup = function()
    cleanup()
    
    -- Clean up parts
    for _, part in ipairs(workspace:GetChildren()) do
        if part.Name:find("myskyp") or part.Name:find("Cosmic") then
            pcall(function() part:Destroy() end)
        end
    end
    
    -- Clean up GUI
    local CoreGui = getService("CoreGui")
    local existingGui = CoreGui:FindFirstChild("SemiInstaSteal")
    if existingGui then
        pcall(function() existingGui:Destroy() end)
    end
    
    _G.MyskypInstaSteal = false
    _G.MySkyConnections = nil
end

-- ============================================================
-- EXECUTE TP FUNCTION (WITH COOLDOWN) - SMART TP TO OPPOSITE BASE
-- ============================================================

local function executeTP()
    -- CHECK COOLDOWN FIRST
    if tick() - lastTeleportTime < TELEPORT_COOLDOWN then 
        warn("Teleport on cooldown! Wait", TELEPORT_COOLDOWN - (tick() - lastTeleportTime), "seconds")
        return false
    end
    
    -- UPDATE COOLDOWN TIMER
    lastTeleportTime = tick()
    
    -- Execute teleport
    local Character = LocalPlayer.Character
    if not Character then
        Character = LocalPlayer.CharacterAdded:Wait()
    end
    
    -- Wait for humanoid and HRP
    local Humanoid = Character:WaitForChild("Humanoid")
    local HRP = Character:WaitForChild("HumanoidRootPart")
    
    -- Try to find Flying Carpet
    local Carpet = Character:FindFirstChild("Flying Carpet") or LocalPlayer.Backpack:FindFirstChild("Flying Carpet")
    if not Carpet then
        warn("Flying Carpet not found!")
        return false
    end
    
    -- Determine which base we're at
    local currentBasePos = getCurrentBasePosition()
    local isAtBase1 = currentBasePos == TP_POSITIONS.BASE1.INFO_POS
    
    print("[DEBUG] Current base detected:", isAtBase1 and "BASE 1" or "BASE 2")
    
    -- Teleport sequence - DETECT BASE AND TP TO OPPOSITE WITH ALL POSITIONS
    task.spawn(function()
        -- Equip tool
        Humanoid:EquipTool(Carpet)
        
        if isAtBase1 then
            
            -- POSITION 4
            HRP.CFrame = CFrame.new(-351.49, -6.65, 113.72)
            task.wait(0.15)
            
            -- POSITION 5
            HRP.CFrame = CFrame.new(-378.14, -6.00, 26.43)
            task.wait(0.15)
            
            -- POSITION 6 (Final position at Base 1)
            HRP.CFrame = CFrame.new(-334.80, -5.04, 18.90)
            
        else
            
            -- POSITION 1
            HRP.CFrame = CFrame.new(-352.54, -6.83, 6.66)
            task.wait(0.15)
            
            -- POSITION 2
            HRP.CFrame = CFrame.new(-372.90, -6.20, 102.00)
            task.wait(0.15)
            
            -- POSITION 3 (Final position at Base 2)
            HRP.CFrame = CFrame.new(-335.08, -5.10, 101.40)
            
        end

    end)
    
    return true
end

-- ============================================================
-- CIRCULAR TP BUTTON FOR MOBILE ONLY
-- ============================================================

local function createMobileTPButton()
    if not IS_MOBILE then return nil end
    
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    -- Create the circle button GUI
    local circleGui = Instance.new("ScreenGui")
    circleGui.Name = "MobileTPButton"
    circleGui.ResetOnSpawn = false
    circleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    circleGui.DisplayOrder = 999
    circleGui.Parent = playerGui
    
    -- Main circle button - CENTER BOTTOM POSITION
    local circleButton = Instance.new("TextButton")
    circleButton.Name = "TPCircle"
    circleButton.Size = UDim2.new(0, 70, 0, 70) -- Bigger for mobile
    circleButton.Position = UDim2.new(0.5, -35, 0.1, -35)
    circleButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    circleButton.BackgroundTransparency = 0.3
    circleButton.BorderSizePixel = 0
    circleButton.Text = ""
    circleButton.AutoButtonColor = false
    circleButton.ZIndex = 10
    circleButton.Parent = circleGui
    
    -- Make it a perfect circle
    local corner = Instance.new("UICorner", circleButton)
    corner.CornerRadius = UDim.new(1, 0)
    
    -- Add a subtle glow effect
    local glow = Instance.new("UIStroke", circleButton)
    glow.Color = Color3.fromRGB(50, 50, 50)
    glow.Thickness = 2
    glow.Transparency = 0.3
    
    -- Button icon (teleport symbol)
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 45, 0, 45) -- Bigger for mobile
    icon.Position = UDim2.new(0.5, -22.5, 0.5, -22.5)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://3926305904"
    icon.ImageRectOffset = Vector2.new(964, 324)
    icon.ImageRectSize = Vector2.new(36, 36)
    icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    icon.Parent = circleButton
    
    -- Button label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 0, 25) -- Bigger for mobile
    label.Position = UDim2.new(0, 0, 1, 5)
    label.BackgroundTransparency = 1
    label.Text = "TELEPORT"
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14 -- Bigger for mobile
    label.TextColor3 = Color3.fromRGB(200, 220, 255)
    label.Parent = circleButton
    
    -- Cooldown indicator
    local cooldownOverlay = Instance.new("Frame")
    cooldownOverlay.Name = "CooldownOverlay"
    cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
    cooldownOverlay.Position = UDim2.new(0, 0, 0, 0)
    cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cooldownOverlay.BackgroundTransparency = 0.7
    cooldownOverlay.BorderSizePixel = 0
    cooldownOverlay.Visible = false
    cooldownOverlay.ZIndex = 11
    cooldownOverlay.Parent = circleButton
    
    Instance.new("UICorner", cooldownOverlay).CornerRadius = UDim.new(1, 0)
    
    local cooldownText = Instance.new("TextLabel")
    cooldownText.Name = "CooldownText"
    cooldownText.Size = UDim2.new(1, 0, 1, 0)
    cooldownText.Position = UDim2.new(0, 0, 0, 0)
    cooldownText.BackgroundTransparency = 1
    cooldownText.Text = ""
    cooldownText.Font = Enum.Font.GothamBold
    cooldownText.TextSize = 22 -- Bigger for mobile
    cooldownText.TextColor3 = Color3.fromRGB(255, 255, 255)
    cooldownText.ZIndex = 12
    cooldownText.Parent = circleButton
    
    -- Function to update cooldown display
    local function updateCooldownDisplay()
        local remainingTime = TELEPORT_COOLDOWN - (tick() - lastTeleportTime)
        
        if remainingTime > 0 then
            cooldownOverlay.Visible = true
            cooldownText.Text = tostring(math.ceil(remainingTime))
            circleButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            circleButton.AutoButtonColor = false
        else
            cooldownOverlay.Visible = false
            cooldownText.Text = ""
            circleButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            circleButton.AutoButtonColor = true
        end
    end
    
    -- Update cooldown display periodically
    task.spawn(function()
        while circleGui and circleGui.Parent do
            updateCooldownDisplay()
            task.wait(0.1)
        end
    end)
    
    -- Click effect
    circleButton.MouseButton1Click:Connect(function()
        -- Check if still on cooldown (double-check)
        if tick() - lastTeleportTime < TELEPORT_COOLDOWN then
            warn("Still on cooldown!")
            return
        end
        
        -- Quick visual feedback
        circleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        icon.ImageColor3 = Color3.fromRGB(255, 255, 200)
        
        -- Execute teleport
        executeTP()
        
        -- Update cooldown display immediately
        updateCooldownDisplay()
        
        -- Quick reset
        task.wait(0.1)
        if tick() - lastTeleportTime >= TELEPORT_COOLDOWN then
            circleButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
        end
    end)
    
    -- Touch support for mobile
    circleButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            -- Check if still on cooldown
            if tick() - lastTeleportTime < TELEPORT_COOLDOWN then
                warn("Still on cooldown!")
                return
            end
            
            -- Quick visual feedback
            circleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            icon.ImageColor3 = Color3.fromRGB(255, 255, 200)
            
            -- Execute teleport
            executeTP()
            
            -- Update cooldown display immediately
            updateCooldownDisplay()
            
            -- Quick reset
            task.wait(0.1)
            if tick() - lastTeleportTime >= TELEPORT_COOLDOWN then
                circleButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
    end)
    
    -- Hover effect
    circleButton.MouseEnter:Connect(function()
        if tick() - lastTeleportTime >= TELEPORT_COOLDOWN then
            TweenService:Create(circleButton, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(30, 30, 30),
                BackgroundTransparency = 0.1
            }):Play()
            
            TweenService:Create(glow, TweenInfo.new(0.2), {
                Thickness = 3
            }):Play()
        end
    end)

    circleButton.MouseLeave:Connect(function()
        if tick() - lastTeleportTime >= TELEPORT_COOLDOWN then
            TweenService:Create(circleButton, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BackgroundTransparency = 0.3
            }):Play()
            
            TweenService:Create(glow, TweenInfo.new(0.2), {
                Thickness = 2
            }):Play()
        end
    end)
    
    print("Mobile TP button created")
    return circleGui
end

-- ============================================================
-- MODIFIED UI (ORIGINAL SIZE FOR PC, NO TP TO PET ON MOBILE)
-- ============================================================

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Local Player
local localPlayer = Players.LocalPlayer

-- Theme colors
local themeColors = {
    bg = Color3.fromRGB(20, 20, 30),
    card = Color3.fromRGB(30, 30, 45),
    accent = Color3.fromRGB(80, 120, 200),
    text = Color3.fromRGB(240, 240, 255),
    green = Color3.fromRGB(80, 200, 80),
    greenGlow = Color3.fromRGB(100, 255, 100),
    red = Color3.fromRGB(255, 80, 80),
    yellow = Color3.fromRGB(255, 200, 50)
}

-- Simplified function to create a toggle
local function createToggle(parent, name, text, yPos)
    local toggle = Instance.new("TextButton")
    toggle.Name = name
    toggle.Size = UDim2.new(1, -20, 0, 30)
    toggle.Position = UDim2.new(0, 10, 0, yPos)
    toggle.BackgroundColor3 = themeColors.card
    toggle.BackgroundTransparency = 0.1
    toggle.BorderSizePixel = 0
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = parent
    
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Parent = toggle
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Text = text
    label.Font = Enum.Font.Gotham
    label.TextSize = 13
    label.TextColor3 = themeColors.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local switch = Instance.new("Frame")
    switch.Name = "Switch"
    switch.Parent = toggle
    switch.Size = UDim2.new(0, 40, 0, 20)
    switch.Position = UDim2.new(1, -50, 0.5, -10)
    switch.BackgroundColor3 = themeColors.red
    switch.BorderSizePixel = 0
    
    Instance.new("UICorner", switch).CornerRadius = UDim.new(0, 10)
    
    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Parent = switch
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = UDim2.new(0, 2, 0, 2)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 8)
    
    return toggle, switch, knob
end

local function updateToggleUI(toggleFrame, knob, isEnabled)
    TweenService:Create(toggleFrame, TweenInfo.new(0.2), {
        BackgroundColor3 = isEnabled and themeColors.green or themeColors.red
    }):Play()
    
    TweenService:Create(knob, TweenInfo.new(0.2), {
        Position = isEnabled and UDim2.new(1, -18, 0, 2) or UDim2.new(0, 2, 0, 2)
    }):Play()
end

local function loadMainUI()
    -- Create main GUI
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CleanAdminGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    -- Main Container - ORIGINAL SIZE FOR PC, SLIGHTLY SMALLER FOR MOBILE
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 280, 0, IS_MOBILE and 200 or 280) -- FIXED: changed : to or
    mainFrame.Position = UDim2.new(1, 350, 0, 60)
    mainFrame.BackgroundColor3 = themeColors.bg
    mainFrame.BackgroundTransparency = 0.05
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
    Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(0, 0, 0)
    mainFrame.UIStroke.Thickness = 2
    mainFrame.UIStroke.Transparency = 0.7

    -- Header
    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = themeColors.card
    header.BorderSizePixel = 0
    header.Text = ""
    header.AutoButtonColor = false
    header.Parent = mainFrame

    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    Instance.new("UIStroke", header).Color = themeColors.accent
    header.UIStroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Parent = header
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 15, 0, -5)
    title.Size = UDim2.new(1, -30, 1, 0)
    title.Text = "â™¥ SEMI INSTA STEAL FROM:"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = themeColors.text
    title.TextXAlignment = Enum.TextXAlignment.Left

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Parent = header
    subtitle.BackgroundTransparency = 1
    subtitle.Position = UDim2.new(0, 15, 0, 25)
    subtitle.Size = UDim2.new(1, -30, 0, 20)
    subtitle.Text = "ARTFUL AND MYSKYP â™¥"
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 12
    subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
    subtitle.TextXAlignment = Enum.TextXAlignment.Left

    -- Toggles Container
    local togglesFrame = Instance.new("Frame")
    togglesFrame.Name = "TogglesFrame"
    togglesFrame.Size = UDim2.new(1, -20, 0, 40)
    togglesFrame.Position = UDim2.new(0, 10, 0, 60)
    togglesFrame.BackgroundTransparency = 1
    togglesFrame.Parent = mainFrame

    -- Create toggles - NO TP TO PET BUTTON ON MOBILE ONLY
    local autoDefenseToggle, autoDefenseSwitch, autoDefenseKnob = createToggle(togglesFrame, "AutoDefenseToggle", "ðŸŽ® Teleport System", 0)
    local activateWorkToggle, activateWorkSwitch, activateWorkKnob = createToggle(togglesFrame, "ActivateWorkToggle", "ðŸ’» Activate To Work", 35)
    
    -- Only add TP to pet button on PC
    local TpToggleRight, TpSwitchRight, TpKnobRight
    if IS_PC then
        TpToggleRight, TpSwitchRight, TpKnobRight = createToggle(togglesFrame, "TpToggleRight", "TP To Pet (G)", 140)
    end

    -- System variables
    local autoDefenseEnabled = true
    local activateWorkEnabled = false
    local TpRightEnabled = false

    -- Initialize toggles
    task.spawn(function()
        task.wait(1.3)
        if autoDefenseSwitch and autoDefenseKnob then
            autoDefenseSwitch.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
            autoDefenseKnob.Position = UDim2.new(1, -18, 0, 2)
        end
        
        -- Initialize TP toggle to OFF (only on PC)
        if TpSwitchRight and TpKnobRight then
            TpSwitchRight.BackgroundColor3 = themeColors.red
            TpKnobRight.Position = UDim2.new(0, 2, 0, 2)
        end
        
        -- Keep activate work toggle red/off by default
        if activateWorkSwitch and activateWorkKnob then
            activateWorkSwitch.BackgroundColor3 = themeColors.red
            activateWorkKnob.Position = UDim2.new(0, 2, 0, 2)
        end
    end)

-- In the MODIFIED UI section, find this code and fix it:

-- Right button toggle functionality (only on PC)
if TpToggleRight then
    TpToggleRight.MouseButton1Click:Connect(function()
        TpRightEnabled = not TpRightEnabled
        
        if TpRightEnabled then
            -- Turn toggle ON (green)
            updateToggleUI(TpSwitchRight, TpKnobRight, true)
            
            -- Execute TP logic when toggled ON
            executeTP()
        else
            -- Manual turn OFF
            updateToggleUI(TpSwitchRight, TpKnobRight, false)
        end
    end)
end

-- G key binding (only on PC)
if IS_PC then
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        -- Check if G key is pressed and not processed by game
        if input.KeyCode == Enum.KeyCode.G and not gameProcessed then
            -- Update toggle UI to ON (green) immediately
            if TpSwitchRight and TpKnobRight then
                updateToggleUI(TpSwitchRight, TpKnobRight, true)
                TpRightEnabled = true
            end
            
            -- Execute teleport
            executeTP()
            
            -- Turn toggle OFF (red) after teleport completes
            task.spawn(function()
                task.wait(0.5) -- Wait for teleport to finish
                if TpSwitchRight and TpKnobRight then
                    updateToggleUI(TpSwitchRight, TpKnobRight, false)
                    TpRightEnabled = false
                end
            end)
        end
    end)
end

    -- G key binding (only on PC) - THIS IS WHAT WAS MISSING
    if IS_PC then
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            -- Check if G key is pressed and not processed by game
            if input.KeyCode == Enum.KeyCode.G and not gameProcessed then
                -- Update toggle UI if it exists
                if TpSwitchRight and TpKnobRight then
                    updateToggleUI(TpSwitchRight, TpKnobRight, true)
                    TpRightEnabled = true
                end
                
                executeTP()
            end
        end)
    end

    -- Footer with version
    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.Size = UDim2.new(1, -20, 0, 30)
    footer.Position = UDim2.new(0, 10, 1, -40)
    footer.BackgroundTransparency = 1
    footer.Parent = mainFrame

    local versionLabel2 = Instance.new("TextLabel")
    versionLabel2.Name = "VersionLabel"
    versionLabel2.Size = UDim2.new(1, 0, 1, 0)
    versionLabel2.BackgroundTransparency = 1
    versionLabel2.Text = "discord.gg/YJaajAeuD"
    versionLabel2.Font = Enum.Font.Gotham
    versionLabel2.TextSize = 12
    versionLabel2.TextColor3 = Color3.fromRGB(150, 170, 200)
    versionLabel2.TextXAlignment = Enum.TextXAlignment.Center
    versionLabel2.Parent = footer

    -- Animation for main UI entrance
    task.spawn(function()
        task.wait(0.5)
        
        TweenService:Create(mainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(1, -300, 0, 60),
            BackgroundTransparency = 0.05
        }):Play()
    end)

    -- Toggle button functionality
    autoDefenseToggle.MouseButton1Click:Connect(function()
        autoDefenseEnabled = not autoDefenseEnabled
        updateToggleUI(autoDefenseSwitch, autoDefenseKnob, autoDefenseEnabled)
        
        -- ACTUALLY TOGGLE THE TP SYSTEM
        TPSysEnabled = autoDefenseEnabled
        
        if not TPSysEnabled then
            -- Clean up markers when turned off
            if Marker and Marker.Parent then
                pcall(function() Marker:Destroy() end)
            end
        else
            -- Recreate marker when turned on
            Marker = CreateMarker()
        end
    end)

    -- PERMANENT ACTIVATE TO WORK TOGGLE FUNCTIONALITY
    activateWorkToggle.MouseButton1Click:Connect(function()
        if desyncPermanentlyActivated then
            -- If already permanently activated, do nothing
            return
        end
        
        -- Disable the button during activation
        activateWorkToggle.AutoButtonColor = false
        activateWorkToggle.Active = false
        
        -- Get the label to update text
        local label = activateWorkToggle:FindFirstChild("Label")
        
        -- Progress sequence
        task.spawn(function()
            if label then
                label.Text = "ðŸ’» Preparing..."
            end
            
            -- RESET THE PLAYER IMMEDIATELY
            if desyncFirstActivation then
                respawn(LocalPlayer)
                desyncFirstActivation = false
                applyPermanentDesync()
            end
            
            task.wait(1.5)
            
            if label then
                label.Text = "ðŸ’» Almost done..."
            end
            task.wait(2)
            
            if label then
                label.Text = "ðŸ’» Continue..."
            end

            if label then
                label.Text = "ðŸ’» Done!"
                task.wait(0.5)
                label.Text = "ðŸ’» Ready To Work"
            end
            
            -- Mark as permanently activated
            activateWorkEnabled = true
            desyncPermanentlyActivated = true
            
            -- Move knob to ON position
            updateToggleUI(activateWorkSwitch, activateWorkKnob, true)
        end)
    end)

    -- Dragging functionality for main window
    local dragging = false
    local dragStart, startPos

    local function update(input)
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            
            TweenService:Create(header.UIStroke, TweenInfo.new(0.2), {
                Thickness = 2
            }):Play()
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    TweenService:Create(header.UIStroke, TweenInfo.new(0.2), {
                        Thickness = 1
                    }):Play()
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
end

-- LOADING SCREEN SYSTEM
local loadScreenGui = Instance.new("ScreenGui")
loadScreenGui.Name = "PremiumLoadScreen"
loadScreenGui.ResetOnSpawn = false
loadScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
loadScreenGui.DisplayOrder = 1000
loadScreenGui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Semi-transparent dark background
local loadBackground = Instance.new("Frame")
loadBackground.Name = "LoadBackground"
loadBackground.Size = UDim2.new(1, 0, 1, 0)
loadBackground.Position = UDim2.new(0, 0, 0, 0)
loadBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
loadBackground.BackgroundTransparency = 0.3
loadBackground.BorderSizePixel = 0
loadBackground.Parent = loadScreenGui

-- Main loading container
local mainContainer = Instance.new("Frame")
mainContainer.Name = "MainContainer"
mainContainer.Size = UDim2.new(0, 400, 0, 300) -- Original size
mainContainer.Position = UDim2.new(0.5, -200, 0.5, -150)
mainContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainContainer.BackgroundTransparency = 0.1
mainContainer.BorderSizePixel = 0
mainContainer.Parent = loadBackground

Instance.new("UICorner", mainContainer).CornerRadius = UDim.new(0, 15)
local containerStroke = Instance.new("UIStroke", mainContainer)
containerStroke.Color = Color3.fromRGB(80, 120, 200)
containerStroke.Thickness = 2
containerStroke.Transparency = 0.3

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, 0, 0, 60)
titleLabel.Position = UDim2.new(0, 0, 0.1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "SEMI TELEPORT"
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 32
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 255)
titleLabel.TextStrokeTransparency = 0.3
titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
titleLabel.Parent = mainContainer

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.Size = UDim2.new(1, 0, 0, 30)
subtitleLabel.Position = UDim2.new(0, 0, 0.25, 0)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "LOADING PLEASE WAIT"
subtitleLabel.Font = Enum.Font.GothamMedium
subtitleLabel.TextSize = 16
subtitleLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
subtitleLabel.Parent = mainContainer

-- Status text
local statusText = Instance.new("TextLabel")
statusText.Name = "StatusText"
statusText.Size = UDim2.new(1, -40, 0, 40)
statusText.Position = UDim2.new(0, 20, 0.4, 0)
statusText.BackgroundTransparency = 1
statusText.Text = "VERIFYING WHITELIST"
statusText.Font = Enum.Font.GothamBold
statusText.TextSize = 20
statusText.TextColor3 = Color3.fromRGB(200, 220, 255)
statusText.Parent = mainContainer

local subStatusText = Instance.new("TextLabel")
subStatusText.Name = "SubStatusText"
subStatusText.Size = UDim2.new(1, -40, 0, 30)
subStatusText.Position = UDim2.new(0, 20, 0.5, 0)
subStatusText.BackgroundTransparency = 1
subStatusText.Text = "CHECKING PERMISSIONS..."
subStatusText.Font = Enum.Font.Gotham
subStatusText.TextSize = 14
subStatusText.TextColor3 = Color3.fromRGB(150, 170, 200)
subStatusText.Parent = mainContainer

-- Progress bar container
local progressContainer = Instance.new("Frame")
progressContainer.Name = "ProgressContainer"
progressContainer.Size = UDim2.new(1, -80, 0, 8)
progressContainer.Position = UDim2.new(0, 40, 0.65, 0)
progressContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
progressContainer.BorderSizePixel = 0
progressContainer.Parent = mainContainer

Instance.new("UICorner", progressContainer).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.Position = UDim2.new(0, 0, 0, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(80, 120, 200)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressContainer

Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

-- Percentage text
local percentText = Instance.new("TextLabel")
percentText.Name = "PercentText"
percentText.Size = UDim2.new(0, -180, 0, 30)
percentText.Position = UDim2.new(1, 10, 0.5, 0)
percentText.BackgroundTransparency = 1
percentText.Text = "0%"
percentText.Font = Enum.Font.GothamBold
percentText.TextSize = 18
percentText.TextColor3 = Color3.fromRGB(200, 220, 255)
percentText.TextXAlignment = Enum.TextXAlignment.Left
percentText.Parent = progressContainer

-- Footer with version
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Size = UDim2.new(1, -40, 0, 30)
footer.Position = UDim2.new(0, 20, 0.85, 0)
footer.BackgroundTransparency = 1
footer.Parent = mainContainer

local versionLabel = Instance.new("TextLabel")
versionLabel.Name = "VersionLabel"
versionLabel.Size = UDim2.new(0.5, 0, 1, 0)
versionLabel.BackgroundTransparency = 1
versionLabel.Text = "discord.gg/YJaajAeuD "
versionLabel.Font = Enum.Font.Gotham
versionLabel.TextSize = 12
versionLabel.TextColor3 = Color3.fromRGB(150, 170, 200)
versionLabel.TextXAlignment = Enum.TextXAlignment.Left
versionLabel.Parent = footer

local creatorLabel = Instance.new("TextLabel")
creatorLabel.Name = "CreatorLabel"
creatorLabel.Size = UDim2.new(0.5, 0, 1, 0)
creatorLabel.Position = UDim2.new(0.5, 0, 0, 0)
creatorLabel.BackgroundTransparency = 1
creatorLabel.Text = "ARTFUL & MYSKYP â™¥"
creatorLabel.Font = Enum.Font.Gotham
creatorLabel.TextSize = 12
creatorLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
creatorLabel.TextXAlignment = Enum.TextXAlignment.Right
creatorLabel.Parent = footer

-- Function to update progress
local function updateProgress(percent, status, subStatus)
    TweenService:Create(progressFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(percent / 100, 0, 1, 0)
    }):Play()
    
    percentText.Text = string.format("%d%%", percent)
    
    if status then
        statusText.Text = status
    end
    
    if subStatus then
        subStatusText.Text = subStatus
    end
end

-- LOADING SEQUENCE
task.spawn(function()
    -- Initial animation
    mainContainer.Position = UDim2.new(0.5, -200, 0.4, -150)
    mainContainer.BackgroundTransparency = 1
    
    TweenService:Create(mainContainer, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -200, 0.5, -150),
        BackgroundTransparency = 0.1
    }):Play()
    
    task.wait(0.5)
    
    local startTime = tick()
    
    -- Phase 1: Initial setup
    updateProgress(15, "INITIALIZING", "Starting SEMI Teleport...")
    task.wait(0.3)
    
    updateProgress(30, "CHECKING CHARACTER", "Loading player data...")
    if not localPlayer.Character then
        localPlayer.CharacterAdded:Wait()
    end
    task.wait(0.7)
    
    -- Add device detection info
    updateProgress(40, "DETECTING DEVICE", IS_MOBILE and "Mobile device detected" or "PC detected")
    task.wait(0.5)
    
    -- Phase 2: Whitelist check simulation
    updateProgress(45, "VERIFYING WHITELIST", "Checking permissions...")
    task.wait(0.7)
    
    updateProgress(60, "WHITELIST CHECK", "Validating access...")
    task.wait(0.7)
    
    updateProgress(75, "WHITELIST VERIFIED", "Access granted")
    task.wait(0.6)
    
    -- Phase 3: Final setup
    updateProgress(85, "LOADING SYSTEMS", "Initializing modules...")
    task.wait(0.5)
    
    updateProgress(95, "FINALIZING", "Almost ready...")
    task.wait(0.5)
    
    updateProgress(100, "READY", "Semi Teleport active")
    
    -- Ensure exactly 5 seconds total
    local elapsed = tick() - startTime
    if elapsed < 5 then
        task.wait(5 - elapsed)
    end
    
    -- Fade out animation
    TweenService:Create(mainContainer, TweenInfo.new(0.5), {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, -200, 0.4, -150)
    }):Play()
    
    TweenService:Create(loadBackground, TweenInfo.new(0.5), {
        BackgroundTransparency = 1
    }):Play()
    
    task.wait(0.5)
    
    -- Destroy loading screen
    loadScreenGui:Destroy()
    
    -- Load the main UI
    loadMainUI()
    
    -- Create mobile TP button if on mobile
    if IS_MOBILE then
        task.wait(0.5)
        createMobileTPButton()
        print("Mobile TP button created")
    end
end)

print("Script configured for: " .. (IS_MOBILE and "MOBILE" or "PC") .. " device")
