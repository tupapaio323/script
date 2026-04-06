local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local character
local humanoid
local humanoidRootPart
local currentTween
local moveUndergroundToPosition
local getPlayerLevel

local autoFarm = false
local autoStand = true
local walkSpeedEnabled = false
local autoPrestige = false
local autoStats = false
local guiExpanded = true
local originalCollision = {}
local takenQuestKey = nil
local skipQuestAfterDeath = false
local respawnCheckpoint = nil
local respawnSpawnPoint = nil
local checkpointQuestKey = nil
local npcCache = {}
local questCache = {}
local lastStatusUpdate = 0
local isRestoringCheckpoint = false
local faceTarget
local setDebug = function() end
local debugMessage = "Debug: listo"
local lastDebugRawMessage = ""
local debugPinnedUntil = 0
local lastAppliedSpeed = nil
local speedSuppressed = false

local customSpeed = 350
local selectedStat = "Strength"
local statAmountValue = 1
local MOVE_SPEED = 42
local QUEST_TWEEN_SPEED = 220
local NPC_TWEEN_SPEED = 260
local UNDERGROUND_Y = -20
local ARRIVAL_TOLERANCE = 6
local QUEST_BEHIND_DISTANCE = 4
local NPC_BEHIND_DISTANCE = 3.5
local NPC_FRONT_DISTANCE = 3.5
local NPC_ABOVE_OFFSET = 4
local QUEST_UNDER_OFFSET = -6
local NPC_UNDER_OFFSET = -6
local TARGET_Y_OFFSET = 0
local COMBAT_REPOSITION_DISTANCE = 18
local CLICK_DELAY = 0.02
local BARRAGE_HOLD_TIME = 3
local SKILL_DELAY = 0.05
local GATHER_BARRAGE_HOLD_TIME = 0.7
local GATHER_SKILL_DELAY = 0.015
local GATHER_CLICK_DELAY = 0.01
local QUEST_PRESS_COUNT = 4
local QUEST_PRESS_DELAY = 0.18
local QUEST_RESET_AFTER = 150
local STATUS_UPDATE_INTERVAL = 0.5
local FARM_MODES = {"Balanced", "M1 Only", "Skills Only", "Barrage", "Gather + Barrage"}
local selectedFarmMode = "Balanced"
local FACE_REFRESH_STEP = 0.05
local WALK_TIMEOUT = 4
local WALKABLE_HEIGHT_DIFFERENCE = 999
local GATHER_TAG_RADIUS = 999
local GATHER_PULL_SECONDS = 0.4
local GATHER_MIN_TARGETS = 1
local GATHER_CLICK_COUNT = 1
local GATHER_TRAVEL_PAUSE = 0
local FINISHER_M1_COUNT = 6
local GATHER_FINISH_RADIUS = 14
local GATHER_FINISH_TARGETS = 2
local CHECKPOINT_RESTORE_ATTEMPTS = 6
local CHECKPOINT_RESTORE_DELAY = 0.35
local BARRAGE_RETREAT_DISTANCE = 18
local BARRAGE_START_DELAY = 0.08
local STUCK_CHECK_INTERVAL = 0.25
local STUCK_DISTANCE_THRESHOLD = 0.75
local WAVE_RESPAWN_WAIT = 8
local ANTI_TS_ENABLED = true
local TARGET_REACH_RETRIES = 3
local TARGET_ATTACK_MAX_DISTANCE = 12
local DEFAULT_WALKSPEED = 16
local M1_DEFENSE_DISTANCE = 8
local STAND_SUMMON_DELAY = 2.5

local QUESTS = {
    {minLevel = 1, maxLevel = 9, questName = "Thug Quest", npcName = "Thug", expectedCount = 5, questGuiName = "ThugQuest"},
    {minLevel = 10, maxLevel = 19, questName = "Brute Quest", npcName = "Brute", expectedCount = 4, questGuiName = "BruteQuest"},
    {minLevel = 20, maxLevel = 29, questName = "🦍😡💢 Quest", npcName = "🦍", expectedCount = 5, questGuiName = "🦍😡💢Quest"},
    {minLevel = 30, maxLevel = 44, questName = "Werewolf Quest", npcName = "Werewolf", expectedCount = 5, questGuiName = "WerewolfQuest"},
    {minLevel = 45, maxLevel = 59, questName = "Zombie Quest", npcName = "Zombie", expectedCount = 5, questGuiName = "ZombieQuest"},
    {minLevel = 60, maxLevel = 79, questName = "Vampire Quest", npcName = "Vampire", expectedCount = 5, questGuiName = "VampireQuest"},
    {minLevel = 80, maxLevel = 100, questName = "Golem Quest", npcName = "HamonGolem", expectedCount = 5, questGuiName = "GolemQuest"},
}

local palette = {
    bg = Color3.fromRGB(12, 12, 14),
    panel = Color3.fromRGB(24, 24, 28),
    sidebar = Color3.fromRGB(18, 18, 22),
    surface = Color3.fromRGB(32, 32, 38),
    surfaceSoft = Color3.fromRGB(39, 39, 47),
    accent = Color3.fromRGB(93, 87, 255),
    accentSoft = Color3.fromRGB(62, 58, 140),
    danger = Color3.fromRGB(190, 70, 70),
    info = Color3.fromRGB(80, 115, 185),
    text = Color3.fromRGB(245, 245, 248),
    muted = Color3.fromRGB(164, 164, 174),
    stroke = Color3.fromRGB(55, 55, 68),
}

local function clampWalkSpeed(value)
    local parsed = tonumber(value)
    if not parsed then
        return customSpeed
    end

    return math.clamp(math.floor(parsed + 0.5), 16, 500)
end

local function extractNumber(rawValue)
    if rawValue == nil then
        return nil
    end

    local direct = tonumber(rawValue)
    if direct then
        return direct
    end

    local digits = tostring(rawValue):match("%d+")
    if digits then
        return tonumber(digits)
    end

    return nil
end

local function readLevelFromInstance(levelInstance)
    if not levelInstance then
        return nil
    end

    if levelInstance:IsA("TextLabel") or levelInstance:IsA("TextButton") or levelInstance:IsA("TextBox") then
        return extractNumber(levelInstance.Text)
    end

    if levelInstance:IsA("IntValue") or levelInstance:IsA("NumberValue") or levelInstance:IsA("StringValue") then
        return extractNumber(levelInstance.Value)
    end

    local okValue, rawValue = pcall(function()
        return levelInstance.Value
    end)
    if okValue then
        local parsed = extractNumber(rawValue)
        if parsed then
            return parsed
        end
    end

    local okText, rawText = pcall(function()
        return levelInstance.Text
    end)
    if okText then
        local parsed = extractNumber(rawText)
        if parsed then
            return parsed
        end
    end

    return nil
end

local function readBooleanInstance(instance)
    if not instance then
        return false
    end

    if instance:IsA("BoolValue") then
        return instance.Value == true
    end

    local okValue, rawValue = pcall(function()
        return instance.Value
    end)
    if okValue then
        if type(rawValue) == "boolean" then
            return rawValue
        end

        local normalizedValue = tostring(rawValue):lower()
        if normalizedValue == "true" or normalizedValue == "on" or normalizedValue == "enabled" or normalizedValue == "1" then
            return true
        end
    end

    local okText, rawText = pcall(function()
        return instance.Text
    end)
    if okText then
        local normalizedText = tostring(rawText):lower()
        if normalizedText:find("on") or normalizedText:find("true") or normalizedText:find("enabled") then
            return true
        end
    end

    return false
end

local function getCoreGuiRoot()
    local playerGui = player:FindFirstChild("PlayerGui")
    return playerGui and (playerGui:FindFirstChild("CoreGUI") or playerGui:FindFirstChild("CoreGui"))
end

local function isAutoRepeatQuestsEnabled()
    local coreGui = getCoreGuiRoot()
    local settings = coreGui and coreGui:FindFirstChild("Settings")
    local stats = settings and settings:FindFirstChild("Stats")
    local toggle = stats and stats:FindFirstChild("AutoRepeatQuests")
    return readBooleanInstance(toggle)
end

local function isQuestGuiObjectVisible(instance)
    local playerGui = player:FindFirstChild("PlayerGui")
    local current = instance

    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end

        current = current.Parent
    end

    return true
end

local function hasActiveQuestUI(config)
    local coreGui = getCoreGuiRoot()
    if not coreGui then
        return false
    end

    local candidates = {
        config.questGuiName,
        (config.questName:gsub("%s+", "")),
        config.questName,
    }

    for _, descendant in ipairs(coreGui:GetDescendants()) do
        for _, candidate in ipairs(candidates) do
            if candidate and descendant.Name == candidate and isQuestGuiObjectVisible(descendant) then
                return true
            end

            if candidate and descendant.Name == "Quest" then
                local parent = descendant.Parent
                if parent and parent.Name == candidate and isQuestGuiObjectVisible(descendant) then
                    return true
                end
            end

        end
    end

    return false
end

local function getDescendantByPath(root, pathParts)
    local current = root
    for _, partName in ipairs(pathParts) do
        current = current and current:FindFirstChild(partName)
    end
    return current
end

local function clickGuiButton(button)
    if not button then
        return false
    end

    local activated = false
    pcall(function()
        activated = true
        button:Activate()
    end)
    pcall(function()
        activated = true
        for _, connection in ipairs(getconnections(button.MouseButton1Click)) do
            connection:Fire()
        end
    end)
    return activated
end

local function getStatsUiRoot()
    local coreGui = getCoreGuiRoot()
    if not coreGui then
        return nil
    end

    return getDescendantByPath(coreGui, {"Stats", "Stats", "Stats"})
end

local function getSkillPointsAmount(statsRoot)
    local amountNode = statsRoot and statsRoot:FindFirstChild("Amount")
    local amount = readLevelFromInstance(amountNode)
    if amount then
        return amount
    end

    for _, descendant in ipairs((statsRoot and statsRoot:GetDescendants()) or {}) do
        if descendant.Name:lower():find("skill") or descendant.Name:lower():find("point") then
            local value = readLevelFromInstance(descendant)
            if value then
                return value
            end
        end
    end

    return 0
end

local function applyAutoStats()
    if not autoStats then
        return false
    end

    local statsRoot = getStatsUiRoot()
    if not statsRoot then
        setDebug("auto stats: StatsRoot no encontrado", 2)
        return false
    end

    local skillPoints = getSkillPointsAmount(statsRoot)
    if skillPoints <= 0 then
        setDebug("auto stats: sin skill points", 2)
        return false
    end

    local amountBox = statsRoot:FindFirstChild("Amount")
    if amountBox then
        if amountBox:IsA("TextBox") or amountBox:IsA("TextLabel") then
            amountBox.Text = tostring(statAmountValue)
        else
            pcall(function()
                amountBox.Value = statAmountValue
            end)
        end
    end

    local targetButton = statsRoot:FindFirstChild(selectedStat)
    local addStatsButton = statsRoot:FindFirstChild("AddStats") or (statsRoot.Parent and statsRoot.Parent:FindFirstChild("AddStats"))

    if not targetButton then
        setDebug("auto stats: boton stat no encontrado " .. tostring(selectedStat), 2)
        return false
    end

    if not addStatsButton then
        setDebug("auto stats: AddStats no encontrado", 2)
        return false
    end

    clickGuiButton(targetButton)

    local clicked = clickGuiButton(addStatsButton)
    if clicked then
        setDebug("auto stats: " .. selectedStat .. " +" .. tostring(statAmountValue), 1.5)
    else
        setDebug("auto stats: no pudo activar AddStats", 2)
    end
    return clicked
end

local function tryAutoPrestige()
    if not autoPrestige or getPlayerLevel() < 100 then
        return false
    end

    setDebug("auto prestige: buscando metodo", 2)

    local coreGui = getCoreGuiRoot()
    if coreGui then
        for _, descendant in ipairs(coreGui:GetDescendants()) do
            local lowered = descendant.Name:lower()
            if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
                if lowered:find("prestige") or lowered:find("rebirth") then
                    if clickGuiButton(descendant) then
                        setDebug("auto prestige: boton " .. descendant.Name, 2)
                        return true
                    end
                end
            end
        end
    end

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            local lowered = descendant.Name:lower()
            if lowered:find("prestige") or lowered:find("rebirth") then
                if fireproximityprompt then
                    fireproximityprompt(descendant)
                    setDebug("auto prestige: prompt " .. descendant.Name, 2)
                    return true
                end
            end
        end
    end

    setDebug("auto prestige: no encontrado en gui/workspace", 2)
    return false
end

local function getRoot(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    return instance:FindFirstChild("HumanoidRootPart")
        or instance.PrimaryPart
        or instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getHumanoid(instance)
    if not instance then
        return nil
    end

    return instance:FindFirstChildWhichIsA("Humanoid")
end

local function isAlive(instance)
    local targetHumanoid = getHumanoid(instance)
    local targetRoot = getRoot(instance)
    return targetHumanoid and targetRoot and targetHumanoid.Health > 0
end

local function setCharacterCollision(enabled)
    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if enabled then
                local original = originalCollision[descendant]
                if original ~= nil then
                    descendant.CanCollide = original
                end
            else
                descendant.CanCollide = false
            end
        end
    end
end

local function stopMomentum()
    if humanoidRootPart then
        humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function ensureWalkSpeed()
    local currentCharacter = player.Character
    local currentHumanoid = currentCharacter and currentCharacter:FindFirstChild("Humanoid")
    if not currentHumanoid then
        lastAppliedSpeed = nil
        speedSuppressed = false
        return
    end

    local currentSpeed = currentHumanoid.WalkSpeed

    if not walkSpeedEnabled then
        if lastAppliedSpeed and math.abs(currentSpeed - lastAppliedSpeed) < 0.05 then
            currentHumanoid.WalkSpeed = DEFAULT_WALKSPEED
        end
        lastAppliedSpeed = nil
        speedSuppressed = false
        return
    end

    if not lastAppliedSpeed and currentSpeed < DEFAULT_WALKSPEED then
        speedSuppressed = true
    end

    local loweredByExternalSystem = lastAppliedSpeed and currentSpeed < lastAppliedSpeed and currentSpeed < customSpeed
    if loweredByExternalSystem then
        speedSuppressed = true
    end

    if speedSuppressed then
        if currentSpeed >= DEFAULT_WALKSPEED then
            speedSuppressed = false
        else
            lastAppliedSpeed = currentSpeed
            return
        end
    end

    if math.abs(currentSpeed - customSpeed) > 0.05 then
        currentHumanoid.WalkSpeed = customSpeed
        lastAppliedSpeed = customSpeed
    end
end

local applyAntiTimeStop

local function syncAutoFarmState()
    if autoFarm then
        setCharacterCollision(false)
        ensureWalkSpeed()
        applyAntiTimeStop()
    else
        setCharacterCollision(true)
    end
end

applyAntiTimeStop = function()
    if not ANTI_TS_ENABLED or not autoFarm or not character then
        return
    end

    if humanoid then
        humanoid.PlatformStand = false
        humanoid.AutoRotate = true
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Anchored then
            descendant.Anchored = false
        end
    end
end

local function destroySpawnCheckpoint()
    if respawnSpawnPoint then
        respawnSpawnPoint:Destroy()
        respawnSpawnPoint = nil
    end
    checkpointQuestKey = nil
end

local function createSpawnCheckpoint(checkpointCFrame, questKey)
    destroySpawnCheckpoint()

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "ScriptFarmCheckpoint"
    spawn.Anchored = true
    spawn.CanCollide = false
    spawn.Transparency = 1
    spawn.Neutral = false
    spawn.Enabled = true
    spawn.AllowTeamChangeOnTouch = false
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.CFrame = checkpointCFrame
    spawn.Parent = workspace

    respawnSpawnPoint = spawn
    checkpointQuestKey = questKey

    pcall(function()
        player.RespawnLocation = spawn
    end)
end

local function restoreCheckpoint()
    if not autoFarm or not humanoidRootPart or not respawnCheckpoint then
        return
    end

    isRestoringCheckpoint = true
    setDebug("personaje murio | iniciando retorno al checkpoint")

    for _ = 1, CHECKPOINT_RESTORE_ATTEMPTS do
        if not humanoidRootPart or not respawnCheckpoint then
            isRestoringCheckpoint = false
            return
        end

        if respawnSpawnPoint and respawnSpawnPoint.Parent then
            pcall(function()
                player.RespawnLocation = respawnSpawnPoint
            end)
        end

        local checkpointPosition = respawnCheckpoint.Position
        moveUndergroundToPosition(checkpointPosition, QUEST_TWEEN_SPEED, "restore checkpoint underground")
        humanoidRootPart.CFrame = respawnCheckpoint
        stopMomentum()
        ensureWalkSpeed()
        if (humanoidRootPart.Position - checkpointPosition).Magnitude <= ARRIVAL_TOLERANCE then
            break
        end

        task.wait(CHECKPOINT_RESTORE_DELAY)
    end

    isRestoringCheckpoint = false
    setDebug("personaje restaurado | retorno al checkpoint completado")
end

local function bindCharacter(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    humanoidRootPart = char:WaitForChild("HumanoidRootPart")
    ensureWalkSpeed()

    table.clear(originalCollision)
    for _, descendant in ipairs(char:GetDescendants()) do
        if descendant:IsA("BasePart") then
            originalCollision[descendant] = descendant.CanCollide
        end
    end

    syncAutoFarmState()

    char.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            originalCollision[descendant] = descendant.CanCollide
            if autoFarm then
                descendant.CanCollide = false
            end
        end
    end)

    humanoid.Died:Connect(function()
        setDebug("personaje murio | guardando posicion", 3)
        if humanoidRootPart then
            respawnCheckpoint = humanoidRootPart.CFrame
            createSpawnCheckpoint(respawnCheckpoint, takenQuestKey)
        end

        if takenQuestKey then
            skipQuestAfterDeath = true
        end
    end)
end

if player.Character then
    bindCharacter(player.Character)
end

player.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    bindCharacter(char)
    setDebug("personaje reaparecio", 2)

    if autoStand then
        task.spawn(function()
            summonStandIfNeeded()
        end)
    end

    if autoFarm and respawnCheckpoint and humanoidRootPart then
        task.spawn(function()
            task.wait(1)
            restoreCheckpoint()
        end)
    end
end)

local function pressKey(keyCode)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.08)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function holdKey(keyCode, holdTime)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(holdTime)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function holdKeyFacing(keyCode, holdTime, targetRoot)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)

    local startedAt = os.clock()
    while os.clock() - startedAt < holdTime do
        if targetRoot and targetRoot.Parent then
            faceTarget(targetRoot.Position)
        end
        task.wait(FACE_REFRESH_STEP)
    end

    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function summonStandIfNeeded()
    if not autoStand then
        return
    end

    setDebug("auto stand: esperando respawn listo", 2)
    task.wait(STAND_SUMMON_DELAY)

    if not autoStand then
        return
    end

    setDebug("auto stand: presionando Q", 2)
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    setDebug("auto stand: Q enviada", 2)
end

local function jumpIfStuck()
    if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
        humanoid.Jump = true
    end
end

local function clickMouse()
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = math.floor(viewport.X / 2)
    local y = math.floor(viewport.Y / 2)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.03)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

getPlayerLevel = function()
    local playerGui = player:FindFirstChild("PlayerGui")
    local coreGui = playerGui and (playerGui:FindFirstChild("CoreGUI") or playerGui:FindFirstChild("CoreGui"))
    local frame = coreGui and coreGui:FindFirstChild("Frame")
    local expBar = frame and frame:FindFirstChild("EXPBAR")
    local status = expBar and expBar:FindFirstChild("Status")
    local levelValue = status and status:FindFirstChild("Level")

    if levelValue then
        local guiLevel = readLevelFromInstance(levelValue)
        if guiLevel then
            return guiLevel
        end
    end

    local stats = player:FindFirstChild("leaderstats")
    if stats then
        for _, child in ipairs(stats:GetChildren()) do
            local childValue = readLevelFromInstance(child)
            if child.Name:lower():find("level") and childValue then
                return childValue
            end
        end
    end

    for _, child in ipairs(player:GetChildren()) do
        local childValue = readLevelFromInstance(child)
        if child.Name:lower():find("level") and childValue then
            return childValue
        end
    end

    return 1
end

local function getQuestConfig()
    local level = getPlayerLevel()
    for _, config in ipairs(QUESTS) do
        if level >= config.minLevel and level <= config.maxLevel then
            return config, level
        end
    end
    return QUESTS[#QUESTS], level
end

local function formatVector3(value)
    if typeof(value) ~= "Vector3" then
        return tostring(value)
    end

    return string.format("X:%.2f Y:%.2f Z:%.2f", value.X, value.Y, value.Z)
end

local function walkTo(position)
    if not humanoid or not humanoidRootPart then
        return false
    end

    local finished = false
    local connection
    connection = humanoid.MoveToFinished:Connect(function(reached)
        finished = reached
    end)

    humanoid:MoveTo(position)

    local startedAt = os.clock()
    local lastMoveToRefresh = startedAt
    local lastStuckCheck = startedAt
    local lastProgressPosition = humanoidRootPart.Position
    while os.clock() - startedAt < WALK_TIMEOUT do
        if (humanoidRootPart.Position - position).Magnitude <= ARRIVAL_TOLERANCE then
            if connection then
                connection:Disconnect()
            end
            return true
        end

        if finished then
            break
        end

        if os.clock() - lastMoveToRefresh >= 0.2 then
            humanoid:MoveTo(position)
            lastMoveToRefresh = os.clock()
        end

        if os.clock() - lastStuckCheck >= STUCK_CHECK_INTERVAL then
            local progressDistance = (humanoidRootPart.Position - lastProgressPosition).Magnitude
            if progressDistance <= STUCK_DISTANCE_THRESHOLD then
                jumpIfStuck()
                humanoid:MoveTo(position)
            end
            lastProgressPosition = humanoidRootPart.Position
            lastStuckCheck = os.clock()
        end

        task.wait(0.05)
    end

    if connection then
        connection:Disconnect()
    end

    return (humanoidRootPart.Position - position).Magnitude <= ARRIVAL_TOLERANCE
end

local tweenMoveTo

local function moveTo(position)
    if not humanoidRootPart or not character then
        return false
    end

    if currentTween then
        currentTween:Cancel()
    end

    return walkTo(position)
end

tweenMoveTo = function(position, speed)
    if not humanoidRootPart then
        return false
    end

    if currentTween then
        currentTween:Cancel()
    end

    local distance = (humanoidRootPart.Position - position).Magnitude
    local travelTime = math.clamp(distance / speed, 0.05, 1.6)
    currentTween = TweenService:Create(
        humanoidRootPart,
        TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
        {CFrame = CFrame.new(position)}
    )
    currentTween:Play()
    currentTween.Completed:Wait()

    return (humanoidRootPart.Position - position).Magnitude <= ARRIVAL_TOLERANCE
end

moveUndergroundToPosition = function(targetPosition, speed, label)
    if not humanoidRootPart or not targetPosition then
        return false
    end

    local currentPosition = humanoidRootPart.Position
    local startUnder = Vector3.new(currentPosition.X, UNDERGROUND_Y, currentPosition.Z)
    local targetUnder = Vector3.new(targetPosition.X, UNDERGROUND_Y, targetPosition.Z)
    local finalPosition = Vector3.new(targetPosition.X, targetPosition.Y, targetPosition.Z)

    setDebug(
        tostring(label)
            .. ": start="
            .. formatVector3(startUnder)
            .. " | targetUnder="
            .. formatVector3(targetUnder)
            .. " | final="
            .. formatVector3(finalPosition)
    )

    local step1 = tweenMoveTo(startUnder, speed)
    local step2 = step1 and tweenMoveTo(targetUnder, speed)
    local step3 = step2 and tweenMoveTo(finalPosition, speed)
    return step1 and step2 and step3
end

local function moveToQuestUnderground(targetRoot)
    if not humanoidRootPart or not targetRoot then
        return false
    end

    local lookVector = targetRoot.CFrame.LookVector
    local questPosition = Vector3.new(
        targetRoot.Position.X - (lookVector.X * QUEST_BEHIND_DISTANCE),
        targetRoot.Position.Y + TARGET_Y_OFFSET,
        targetRoot.Position.Z - (lookVector.Z * QUEST_BEHIND_DISTANCE)
    )

    return moveUndergroundToPosition(questPosition, QUEST_TWEEN_SPEED, "quest tween underground")
end

local function getBehindPosition(targetRoot, distance)
    local lookVector = targetRoot.CFrame.LookVector
    local targetPosition = targetRoot.Position
    return Vector3.new(
        targetPosition.X - (lookVector.X * distance),
        targetPosition.Y + TARGET_Y_OFFSET,
        targetPosition.Z - (lookVector.Z * distance)
    )
end

local function getCombatPosition(targetRoot)
    return getBehindPosition(targetRoot, NPC_BEHIND_DISTANCE)
end

local function getQuestPosition(targetRoot)
    return getBehindPosition(targetRoot, QUEST_BEHIND_DISTANCE)
end

local function moveToTargetPosition(targetPosition)
    if not humanoidRootPart or not targetPosition then
        return false
    end

    return moveTo(targetPosition)
end

local function isWithinDistanceOf(position, maxDistance)
    if not humanoidRootPart or not position then
        return false
    end

    return (humanoidRootPart.Position - position).Magnitude <= maxDistance
end

local function ensureCloseToTarget(targetRoot, desiredPosition, maxDistance, label)
    if not humanoidRootPart or not targetRoot or not desiredPosition then
        return false
    end

    local debugLabel = label or targetRoot.Parent and targetRoot.Parent.Name or targetRoot.Name

    for attempt = 1, TARGET_REACH_RETRIES do
        local moveOk = moveToTargetPosition(desiredPosition)
        local currentTargetRoot = getRoot(targetRoot.Parent) or targetRoot
        local closeEnough = isWithinDistanceOf(currentTargetRoot.Position, maxDistance)

        if moveOk or closeEnough then
            return true
        end

        setDebug(
            "reintentando acercarse: "
                .. tostring(debugLabel)
                .. " | intento="
                .. tostring(attempt)
                .. " | dist="
                .. string.format("%.2f", (humanoidRootPart.Position - currentTargetRoot.Position).Magnitude)
        )
        task.wait(0.05)
        desiredPosition = getCombatPosition(currentTargetRoot)
        targetRoot = currentTargetRoot
    end

    setDebug(
        "demasiado lejos para pegar: "
            .. tostring(debugLabel)
            .. " | dist="
            .. string.format("%.2f", (humanoidRootPart.Position - targetRoot.Position).Magnitude)
    )
    return false
end

faceTarget = function(worldPosition)
    if not humanoidRootPart then
        return
    end

    local origin = humanoidRootPart.Position
    humanoidRootPart.CFrame = CFrame.new(origin, Vector3.new(worldPosition.X, origin.Y, worldPosition.Z))
end

local function findQuestObjectByName(questName)
    local cached = questCache[questName]
    if cached and cached.Parent then
        local root = getRoot(cached)
        if root then
            return cached
        end
    end

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant.Name == questName then
            local root = getRoot(descendant)
            if root then
                questCache[questName] = descendant
                return descendant
            end
        end
    end
    return nil
end

local function collectNpcTargets(npcName)
    local cached = npcCache[npcName]
    if cached then
        local matches = {}
        local valid = true

        for index = #cached, 1, -1 do
            local npc = cached[index]
            if npc and npc.Parent and npc:IsA("Model") and npc.Name == npcName and getHumanoid(npc) and getRoot(npc) then
                table.insert(matches, npc)
            else
                valid = false
                table.remove(cached, index)
            end
        end

        if valid or #matches > 0 then
            return matches
        end
    end

    local matches = {}
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("Model") and descendant.Name == npcName and getHumanoid(descendant) and getRoot(descendant) then
            table.insert(matches, descendant)
        end
    end
    npcCache[npcName] = matches
    return matches
end

local function collectAliveTargetsSorted(npcName)
    if not humanoidRootPart then
        return {}
    end

    local targets = {}
    for _, npc in ipairs(collectNpcTargets(npcName)) do
        if isAlive(npc) then
            local root = getRoot(npc)
            if root then
                table.insert(targets, {
                    model = npc,
                    distance = (humanoidRootPart.Position - root.Position).Magnitude,
                })
            end
        end
    end

    table.sort(targets, function(a, b)
        return a.distance < b.distance
    end)

    return targets
end

local function collectNearbyAliveTargets(npcName, originPosition, radius)
    local targets = {}

    for _, npc in ipairs(collectNpcTargets(npcName)) do
        if isAlive(npc) then
            local root = getRoot(npc)
            if root then
                local distance = (root.Position - originPosition).Magnitude
                if distance <= radius then
                    table.insert(targets, {
                        model = npc,
                        root = root,
                        distance = distance,
                    })
                end
            end
        end
    end

    table.sort(targets, function(a, b)
        return a.distance < b.distance
    end)

    return targets
end

local function takeQuest(config)
    local questObject = findQuestObjectByName(config.questName)
    local questRoot = getRoot(questObject)
    if not questRoot or not autoFarm then
        setDebug(
            "quest root no encontrado: "
                .. tostring(config.questName)
                .. " | questObject="
                .. tostring(questObject)
                .. " | autoFarm="
                .. tostring(autoFarm)
        )
        return false
    end

    local questPosition = getQuestPosition(questRoot)
    setDebug(
        "takeQuest start: "
            .. tostring(config.questName)
            .. " | root="
            .. tostring(questRoot:GetFullName())
            .. " | rootPos="
            .. formatVector3(questRoot.Position)
            .. " | targetPos="
            .. formatVector3(questPosition)
    )

    local reached = moveToQuestUnderground(questRoot)
    if not reached then
        setDebug(
            "no llego a quest: "
                .. tostring(config.questName)
                .. " | currentPos="
                .. formatVector3(humanoidRootPart and humanoidRootPart.Position)
                .. " | targetPos="
                .. formatVector3(questPosition)
        )
        return false
    end

    setDebug("quest reached: " .. tostring(config.questName) .. " | pressing E")
    faceTarget(questRoot.Position)
    for _ = 1, QUEST_PRESS_COUNT do
        if not autoFarm then
            setDebug("takeQuest cancelada: autoFarm false durante E")
            return false
        end
        pressKey(Enum.KeyCode.E)
        task.wait(QUEST_PRESS_DELAY)
    end

    takenQuestKey = config.questName
    skipQuestAfterDeath = false
    config.lastQuestTime = os.clock()
    setDebug("quest tomada: " .. tostring(config.questName) .. " | done")
    return true
end

local function useBarrage(targetRoot, holdTime, postDelay)
    if not targetRoot or not targetRoot.Parent then
        return
    end

    faceTarget(targetRoot.Position)
    clickMouse()
    task.wait(CLICK_DELAY)
    faceTarget(targetRoot.Position)
    holdKeyFacing(Enum.KeyCode.E, holdTime or BARRAGE_HOLD_TIME, targetRoot)
    task.wait(postDelay or SKILL_DELAY)
end

local function useRetreatingBarrage(targetRoot)
    if not targetRoot or not targetRoot.Parent or not humanoid then
        return
    end

    local targetModel = targetRoot.Parent
    local currentRoot = getRoot(targetModel) or targetRoot

    faceTarget(currentRoot.Position)
    clickMouse()
    task.wait(CLICK_DELAY)
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(BARRAGE_START_DELAY)

    local startedAt = os.clock()
    while os.clock() - startedAt < BARRAGE_HOLD_TIME do
        currentRoot = getRoot(targetModel) or currentRoot
        if not currentRoot or not currentRoot.Parent then
            break
        end

        ensureWalkSpeed()
        faceTarget(currentRoot.Position)
        humanoid:MoveTo(getBehindPosition(currentRoot, BARRAGE_RETREAT_DISTANCE))
        task.wait(FACE_REFRESH_STEP)
    end

    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    task.wait(SKILL_DELAY)
end

local function doCombatRotation(targetRoot)
    faceTarget(targetRoot.Position)

    if selectedFarmMode == "M1 Only" then
        local retreatPosition = getBehindPosition(targetRoot, M1_DEFENSE_DISTANCE)
        if humanoidRootPart and (humanoidRootPart.Position - retreatPosition).Magnitude > ARRIVAL_TOLERANCE then
            moveToTargetPosition(retreatPosition)
        end

        for _ = 1, 5 do
            faceTarget(targetRoot.Position)
            clickMouse()
            task.wait(CLICK_DELAY)

            local currentRoot = getRoot(targetRoot.Parent) or targetRoot
            if currentRoot and humanoid then
                humanoid:MoveTo(getBehindPosition(currentRoot, M1_DEFENSE_DISTANCE))
            end
        end
        return
    end

    if selectedFarmMode == "Skills Only" then
        faceTarget(targetRoot.Position)
        pressKey(Enum.KeyCode.R)
        task.wait(SKILL_DELAY)
        faceTarget(targetRoot.Position)
        pressKey(Enum.KeyCode.T)
        task.wait(SKILL_DELAY)
        return
    end

    if selectedFarmMode == "Barrage" then
        useBarrage(targetRoot)
        return
    end

    if selectedFarmMode == "Gather + Barrage" then
        for _ = 1, 2 do
            faceTarget(targetRoot.Position)
            clickMouse()
            task.wait(GATHER_CLICK_DELAY)
        end

        faceTarget(targetRoot.Position)
        useBarrage(targetRoot, GATHER_BARRAGE_HOLD_TIME, GATHER_SKILL_DELAY)

        for _ = 1, 2 do
            faceTarget(targetRoot.Position)
            pressKey(Enum.KeyCode.R)
            task.wait(GATHER_SKILL_DELAY)
            faceTarget(targetRoot.Position)
            pressKey(Enum.KeyCode.T)
            task.wait(GATHER_SKILL_DELAY)
            faceTarget(targetRoot.Position)
            clickMouse()
            task.wait(GATHER_CLICK_DELAY)
            faceTarget(targetRoot.Position)
            clickMouse()
            task.wait(GATHER_CLICK_DELAY)
        end

        return
    end

    clickMouse()
    task.wait(CLICK_DELAY)
    useBarrage(targetRoot)
    faceTarget(targetRoot.Position)
    pressKey(Enum.KeyCode.R)
    task.wait(SKILL_DELAY)
    faceTarget(targetRoot.Position)
    pressKey(Enum.KeyCode.T)
    task.wait(SKILL_DELAY)
    faceTarget(targetRoot.Position)
    clickMouse()
    task.wait(CLICK_DELAY)
end

local function gatherAndBarrage(config, targets)
    if not autoFarm or not targets or #targets == 0 then
        return
    end

    local lastRoot

    for _, entry in ipairs(targets) do
        if not autoFarm or not humanoid or humanoid.Health <= 0 then
            return
        end

        local currentRoot = getRoot(entry.model)
        if isAlive(entry.model) and currentRoot then
            local closeEnough = ensureCloseToTarget(
                currentRoot,
                getCombatPosition(currentRoot),
                TARGET_ATTACK_MAX_DISTANCE,
                entry.model.Name
            )
            if not closeEnough then
                continue
            end

            faceTarget(currentRoot.Position)
            for _ = 1, GATHER_CLICK_COUNT do
                clickMouse()
                task.wait(CLICK_DELAY)
            end
            lastRoot = currentRoot
            task.wait(GATHER_TRAVEL_PAUSE)
        end
    end

    if not lastRoot then
        return
    end

    ensureCloseToTarget(lastRoot, getCombatPosition(lastRoot), TARGET_ATTACK_MAX_DISTANCE, lastRoot.Parent and lastRoot.Parent.Name)

    local startedAt = os.clock()
    local groupedCount = 0
    while autoFarm and humanoid and humanoid.Health > 0 and os.clock() - startedAt < GATHER_PULL_SECONDS do
        if not lastRoot or not lastRoot.Parent then
            break
        end

        local groupedTargets = collectNearbyAliveTargets(config.npcName, lastRoot.Position, GATHER_FINISH_RADIUS)
        groupedCount = #groupedTargets
        if groupedCount >= GATHER_FINISH_TARGETS then
            break
        end

        faceTarget(lastRoot.Position)
        for _ = 1, GATHER_CLICK_COUNT do
            clickMouse()
            task.wait(CLICK_DELAY)
        end
        task.wait(GATHER_TRAVEL_PAUSE)
    end

    if lastRoot and lastRoot.Parent then
        if not ensureCloseToTarget(lastRoot, getCombatPosition(lastRoot), TARGET_ATTACK_MAX_DISTANCE, lastRoot.Parent and lastRoot.Parent.Name) then
            return
        end

        useRetreatingBarrage(lastRoot)
        if lastRoot and lastRoot.Parent then
            faceTarget(lastRoot.Position)
            useBarrage(lastRoot)
        end
        faceTarget(lastRoot.Position)
        pressKey(Enum.KeyCode.R)
        task.wait(SKILL_DELAY)
        faceTarget(lastRoot.Position)
        pressKey(Enum.KeyCode.T)
        task.wait(SKILL_DELAY)
        faceTarget(lastRoot.Position)
        for _ = 1, FINISHER_M1_COUNT do
            clickMouse()
            task.wait(CLICK_DELAY)
            if lastRoot and lastRoot.Parent then
                faceTarget(lastRoot.Position)
            end
        end
    end
end

local function fightTarget(targetModel)
    if not autoFarm or not isAlive(targetModel) then
        return
    end

    local targetHumanoid = getHumanoid(targetModel)
    local targetRoot = getRoot(targetModel)
    if not targetHumanoid or not targetRoot then
        return
    end

    if not ensureCloseToTarget(targetRoot, getCombatPosition(targetRoot), TARGET_ATTACK_MAX_DISTANCE, targetModel.Name) then
        return
    end

    while autoFarm and humanoid and humanoid.Health > 0 and targetModel.Parent and targetHumanoid.Health > 0 do
        targetRoot = getRoot(targetModel)
        if not targetRoot then
            break
        end

        local desiredPosition = getCombatPosition(targetRoot)

        if (humanoidRootPart.Position - desiredPosition).Magnitude > COMBAT_REPOSITION_DISTANCE then
            if not ensureCloseToTarget(targetRoot, desiredPosition, TARGET_ATTACK_MAX_DISTANCE, targetModel.Name) then
                break
            end
        elseif not isWithinDistanceOf(targetRoot.Position, TARGET_ATTACK_MAX_DISTANCE) then
            if not ensureCloseToTarget(targetRoot, desiredPosition, TARGET_ATTACK_MAX_DISTANCE, targetModel.Name) then
                break
            end
        end

        camera.CFrame = CFrame.new(camera.CFrame.Position, targetRoot.Position)
        doCombatRotation(targetRoot)
        task.wait(0.05)
    end
end

local function clearCurrentWave(config)
    local targets = collectAliveTargetsSorted(config.npcName)
    local targetSearchStartedAt = os.clock()

    while autoFarm and humanoid and humanoid.Health > 0 and #targets == 0 and os.clock() - targetSearchStartedAt < 1.2 do
        npcCache[config.npcName] = nil
        task.wait(0.15)
        targets = collectAliveTargetsSorted(config.npcName)
    end

    if #targets == 0 then
        setDebug("sin npc vivos: " .. tostring(config.npcName))
        return false
    end

    setDebug("yendo a npc: " .. tostring(config.npcName) .. " (" .. tostring(#targets) .. ")")

    if selectedFarmMode == "Gather + Barrage" then
        local respawnWaitStartedAt = os.clock()
        while autoFarm and humanoid and humanoid.Health > 0 and #targets < config.expectedCount and os.clock() - respawnWaitStartedAt < WAVE_RESPAWN_WAIT do
            task.wait(0.3)
            targets = collectAliveTargetsSorted(config.npcName)
        end

        if #targets == 0 then
            return false
        end

        if #targets >= GATHER_MIN_TARGETS then
            gatherAndBarrage(config, targets)
            return true
        end
    end

    for _, entry in ipairs(targets) do
        if not autoFarm or not humanoid or humanoid.Health <= 0 then
            break
        end
        if isAlive(entry.model) then
            fightTarget(entry.model)
            task.wait(0.1)
        end
    end

    return true
end

local function shouldTakeQuest(config)
    if isAutoRepeatQuestsEnabled() then
        takenQuestKey = config.questName
        return false
    end

    if hasActiveQuestUI(config) then
        takenQuestKey = config.questName
        return false
    end

    if takenQuestKey ~= config.questName then
        return not skipQuestAfterDeath
    end

    local age = os.clock() - (config.lastQuestTime or 0)
    if age > QUEST_RESET_AFTER then
        takenQuestKey = nil
        skipQuestAfterDeath = false
        return true
    end

    return false
end

local function clearCheckpointIfQuestChanged(activeQuestName)
    if checkpointQuestKey and activeQuestName ~= checkpointQuestKey then
        destroySpawnCheckpoint()
        respawnCheckpoint = nil
    end
end

local function invalidateCachesForName(name)
    for _, config in ipairs(QUESTS) do
        if config.npcName == name then
            npcCache[name] = nil
        end

        if config.questName == name then
            questCache[name] = nil
        end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "Script Farm"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 560, 0, 430)
frame.Position = UDim2.new(0.05, 0, 0.18, 0)
frame.BackgroundColor3 = palette.panel
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 14)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = palette.stroke
frameStroke.Transparency = 0.2
frameStroke.Parent = frame

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 116, 1, 0)
sidebar.BackgroundColor3 = palette.sidebar
sidebar.BorderSizePixel = 0
sidebar.Parent = frame

local sidebarCorner = Instance.new("UICorner")
sidebarCorner.CornerRadius = UDim.new(0, 14)
sidebarCorner.Parent = sidebar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -128, 1, -12)
content.Position = UDim2.new(0, 122, 0, 6)
content.BackgroundTransparency = 1
content.Parent = frame

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundTransparency = 1
header.Parent = content

local navList = Instance.new("Frame")
navList.Size = UDim2.new(1, -12, 1, -54)
navList.Position = UDim2.new(0, 6, 0, 48)
navList.BackgroundTransparency = 1
navList.Parent = sidebar

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 6)
navLayout.Parent = navList

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 0, 24)
title.Position = UDim2.new(0, 0, 0, 2)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Auto Farm Stands Online V33"
title.TextColor3 = palette.text
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local sidebarTitle = Instance.new("TextLabel")
sidebarTitle.Size = UDim2.new(1, -16, 0, 22)
sidebarTitle.Position = UDim2.new(0, 10, 0, 12)
sidebarTitle.BackgroundTransparency = 1
sidebarTitle.Font = Enum.Font.GothamBold
sidebarTitle.Text = "Farm"
sidebarTitle.TextColor3 = palette.text
sidebarTitle.TextSize = 13
sidebarTitle.TextXAlignment = Enum.TextXAlignment.Left
sidebarTitle.Parent = sidebar

for _, itemName in ipairs({"Farm"}) do
    local navButton = Instance.new("TextButton")
    navButton.Size = UDim2.new(1, 0, 0, 24)
    navButton.BackgroundColor3 = itemName == "Farm" and palette.surfaceSoft or palette.sidebar
    navButton.BorderSizePixel = 0
    navButton.Text = itemName
    navButton.TextColor3 = itemName == "Farm" and palette.text or palette.muted
    navButton.Font = Enum.Font.Gotham
    navButton.TextSize = 12
    navButton.TextXAlignment = Enum.TextXAlignment.Left
    navButton.AutoButtonColor = false
    navButton.Parent = navList

    local navPadding = Instance.new("UIPadding")
    navPadding.PaddingLeft = UDim.new(0, 10)
    navPadding.Parent = navButton

    local navCorner = Instance.new("UICorner")
    navCorner.CornerRadius = UDim.new(0, 8)
    navCorner.Parent = navButton
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -8, 0, 54)
statusLabel.Position = UDim2.new(0, 0, 0, 46)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextColor3 = palette.muted
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = content

local mainFarmLabel = Instance.new("TextLabel")
mainFarmLabel.Size = UDim2.new(1, -8, 0, 20)
mainFarmLabel.Position = UDim2.new(0, 0, 0, 94)
mainFarmLabel.BackgroundTransparency = 1
mainFarmLabel.Font = Enum.Font.GothamBold
mainFarmLabel.Text = "Main Farm"
mainFarmLabel.TextColor3 = palette.text
mainFarmLabel.TextSize = 16
mainFarmLabel.TextXAlignment = Enum.TextXAlignment.Left
mainFarmLabel.Parent = content

local utilityLabel = Instance.new("TextLabel")
utilityLabel.Size = UDim2.new(1, -8, 0, 20)
utilityLabel.Position = UDim2.new(0, 0, 0, 236)
utilityLabel.BackgroundTransparency = 1
utilityLabel.Font = Enum.Font.GothamBold
utilityLabel.Text = "Utility"
utilityLabel.TextColor3 = palette.text
utilityLabel.TextSize = 16
utilityLabel.TextXAlignment = Enum.TextXAlignment.Left
utilityLabel.Parent = content

local miscLabel = Instance.new("TextLabel")
miscLabel.Size = UDim2.new(1, -8, 0, 20)
miscLabel.Position = UDim2.new(0, 0, 0, 332)
miscLabel.BackgroundTransparency = 1
miscLabel.Font = Enum.Font.GothamBold
miscLabel.Text = "Diagnostics"
miscLabel.TextColor3 = palette.text
miscLabel.TextSize = 16
miscLabel.TextXAlignment = Enum.TextXAlignment.Left
miscLabel.Parent = content

local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(1, -24, 0, 42)
autoBtn.Position = UDim2.new(0, 0, 0, 112)
autoBtn.BorderSizePixel = 0
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextColor3 = palette.text
autoBtn.TextSize = 15
autoBtn.BackgroundColor3 = palette.surface
autoBtn.Parent = content

local autoCorner = Instance.new("UICorner")
autoCorner.CornerRadius = UDim.new(0, 12)
autoCorner.Parent = autoBtn

local autoStandBtn = Instance.new("TextButton")
autoStandBtn.Size = UDim2.new(1, -24, 0, 38)
autoStandBtn.Position = UDim2.new(0, 0, 0, 162)
autoStandBtn.BorderSizePixel = 0
autoStandBtn.Font = Enum.Font.GothamBold
autoStandBtn.TextColor3 = palette.text
autoStandBtn.TextSize = 14
autoStandBtn.BackgroundColor3 = palette.surface
autoStandBtn.Parent = content

local autoStandCorner = Instance.new("UICorner")
autoStandCorner.CornerRadius = UDim.new(0, 10)
autoStandCorner.Parent = autoStandBtn

local setSpeedBtn = Instance.new("TextButton")
setSpeedBtn.Size = UDim2.new(1, -24, 0, 38)
setSpeedBtn.Position = UDim2.new(0, 0, 0, 210)
setSpeedBtn.BorderSizePixel = 0
setSpeedBtn.Font = Enum.Font.GothamBold
setSpeedBtn.TextColor3 = palette.text
setSpeedBtn.TextSize = 14
setSpeedBtn.BackgroundColor3 = palette.surface
setSpeedBtn.Parent = content

local setSpeedCorner = Instance.new("UICorner")
setSpeedCorner.CornerRadius = UDim.new(0, 10)
setSpeedCorner.Parent = setSpeedBtn

local autoPrestigeBtn = Instance.new("TextButton")
autoPrestigeBtn.Size = UDim2.new(1, -24, 0, 38)
autoPrestigeBtn.Position = UDim2.new(0, 0, 0, 258)
autoPrestigeBtn.BorderSizePixel = 0
autoPrestigeBtn.Font = Enum.Font.GothamBold
autoPrestigeBtn.TextColor3 = palette.text
autoPrestigeBtn.TextSize = 14
autoPrestigeBtn.BackgroundColor3 = palette.surface
autoPrestigeBtn.Parent = content

local autoPrestigeCorner = Instance.new("UICorner")
autoPrestigeCorner.CornerRadius = UDim.new(0, 10)
autoPrestigeCorner.Parent = autoPrestigeBtn

local autoStatsBtn = Instance.new("TextButton")
autoStatsBtn.Size = UDim2.new(1, -24, 0, 38)
autoStatsBtn.Position = UDim2.new(0, 0, 0, 306)
autoStatsBtn.BorderSizePixel = 0
autoStatsBtn.Font = Enum.Font.GothamBold
autoStatsBtn.TextColor3 = palette.text
autoStatsBtn.TextSize = 14
autoStatsBtn.BackgroundColor3 = palette.surface
autoStatsBtn.Parent = content

local autoStatsCorner = Instance.new("UICorner")
autoStatsCorner.CornerRadius = UDim.new(0, 10)
autoStatsCorner.Parent = autoStatsBtn

local statModeBtn = Instance.new("TextButton")
statModeBtn.Size = UDim2.new(1, -24, 0, 36)
statModeBtn.Position = UDim2.new(0, 0, 0, 354)
statModeBtn.BorderSizePixel = 0
statModeBtn.Font = Enum.Font.GothamBold
statModeBtn.TextColor3 = palette.text
statModeBtn.TextSize = 13
statModeBtn.BackgroundColor3 = palette.surfaceSoft
statModeBtn.Parent = content

local statModeCorner = Instance.new("UICorner")
statModeCorner.CornerRadius = UDim.new(0, 10)
statModeCorner.Parent = statModeBtn

local statAmountBox = Instance.new("TextBox")
statAmountBox.Size = UDim2.new(1, -24, 0, 36)
statAmountBox.Position = UDim2.new(0, 0, 0, 402)
statAmountBox.BackgroundColor3 = palette.surfaceSoft
statAmountBox.BorderSizePixel = 0
statAmountBox.ClearTextOnFocus = false
statAmountBox.Font = Enum.Font.Gotham
statAmountBox.PlaceholderText = "Stat Amount"
statAmountBox.Text = tostring(statAmountValue)
statAmountBox.TextColor3 = palette.text
statAmountBox.PlaceholderColor3 = palette.muted
statAmountBox.TextSize = 14
statAmountBox.Parent = content

local statAmountCorner = Instance.new("UICorner")
statAmountCorner.CornerRadius = UDim.new(0, 10)
statAmountCorner.Parent = statAmountBox

local rejoinBtn = Instance.new("TextButton")
rejoinBtn.Size = UDim2.new(1, -24, 0, 38)
rejoinBtn.Position = UDim2.new(0, 0, 0, 450)
rejoinBtn.BorderSizePixel = 0
rejoinBtn.Font = Enum.Font.GothamBold
rejoinBtn.Text = "Rejoin"
rejoinBtn.TextColor3 = palette.text
rejoinBtn.TextSize = 14
rejoinBtn.BackgroundColor3 = palette.info
rejoinBtn.Parent = content

local rejoinCorner = Instance.new("UICorner")
rejoinCorner.CornerRadius = UDim.new(0, 10)
rejoinCorner.Parent = rejoinBtn

local farmModeBtn = Instance.new("TextButton")
farmModeBtn.Size = UDim2.new(1, -24, 0, 38)
farmModeBtn.Position = UDim2.new(0, 0, 0, 498)
farmModeBtn.BorderSizePixel = 0
farmModeBtn.Font = Enum.Font.GothamBold
farmModeBtn.TextColor3 = palette.text
farmModeBtn.TextSize = 14
farmModeBtn.BackgroundColor3 = palette.surface
farmModeBtn.Parent = content

local farmModeCorner = Instance.new("UICorner")
farmModeCorner.CornerRadius = UDim.new(0, 10)
farmModeCorner.Parent = farmModeBtn

local walkSpeedBox = Instance.new("TextBox")
walkSpeedBox.Size = UDim2.new(1, -24, 0, 36)
walkSpeedBox.Position = UDim2.new(0, 0, 0, 546)
walkSpeedBox.BackgroundColor3 = palette.surfaceSoft
walkSpeedBox.BorderSizePixel = 0
walkSpeedBox.ClearTextOnFocus = false
walkSpeedBox.Font = Enum.Font.Gotham
walkSpeedBox.PlaceholderText = "Set Speed Value"
walkSpeedBox.Text = tostring(customSpeed)
walkSpeedBox.TextColor3 = palette.text
walkSpeedBox.PlaceholderColor3 = palette.muted
walkSpeedBox.TextSize = 14
walkSpeedBox.Parent = content

local walkSpeedCorner = Instance.new("UICorner")
walkSpeedCorner.CornerRadius = UDim.new(0, 10)
walkSpeedCorner.Parent = walkSpeedBox

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -24, 0, 34)
infoLabel.Position = UDim2.new(0, 0, 0, 588)
infoLabel.BackgroundTransparency = 1
infoLabel.Font = Enum.Font.Gotham
infoLabel.Text = "La GUI muestra tu nivel y quest automaticos. Puedes editar el WalkSpeed para caminar mas rapido."
infoLabel.TextColor3 = palette.muted
infoLabel.TextSize = 11
infoLabel.TextWrapped = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.Parent = content

local debugLabel = Instance.new("TextLabel")
debugLabel.Size = UDim2.new(1, -24, 0, 42)
debugLabel.Position = UDim2.new(0, 0, 0, 624)
debugLabel.BackgroundTransparency = 1
debugLabel.Font = Enum.Font.Code
debugLabel.Text = debugMessage
debugLabel.TextColor3 = Color3.fromRGB(255, 210, 130)
debugLabel.TextSize = 11
debugLabel.TextWrapped = true
debugLabel.TextXAlignment = Enum.TextXAlignment.Left
debugLabel.TextYAlignment = Enum.TextYAlignment.Top
debugLabel.Parent = content

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 28, 0, 28)
minimizeBtn.Position = UDim2.new(1, -66, 0, 4)
minimizeBtn.BackgroundColor3 = palette.surface
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.Text = "-"
minimizeBtn.TextColor3 = palette.text
minimizeBtn.TextSize = 16
minimizeBtn.Parent = header

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 10)
minimizeCorner.Parent = minimizeBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = palette.surface
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Text = "X"
closeBtn.TextColor3 = palette.text
closeBtn.TextSize = 14
closeBtn.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 10)
closeCorner.Parent = closeBtn

local function setExpanded(expanded)
    guiExpanded = expanded
    statusLabel.Visible = expanded
    mainFarmLabel.Visible = expanded
    autoBtn.Visible = expanded
    autoStandBtn.Visible = expanded
    setSpeedBtn.Visible = expanded
    autoPrestigeBtn.Visible = expanded
    autoStatsBtn.Visible = expanded
    statModeBtn.Visible = expanded
    statAmountBox.Visible = expanded
    utilityLabel.Visible = expanded
    rejoinBtn.Visible = expanded
    farmModeBtn.Visible = expanded
    walkSpeedBox.Visible = expanded
    miscLabel.Visible = expanded
    infoLabel.Visible = expanded
    debugLabel.Visible = expanded
    sidebar.Visible = expanded
    frame.Size = expanded and UDim2.new(0, 560, 0, 670) or UDim2.new(0, 560, 0, 44)
    minimizeBtn.Text = expanded and "-" or "+"
end

local function updateFarmModeButton()
    farmModeBtn.Text = "Farm Mode: " .. selectedFarmMode
end

setDebug = function(message, holdSeconds)
    local rawMessage = tostring(message)
    if os.clock() < debugPinnedUntil and rawMessage ~= lastDebugRawMessage then
        return
    end
    if rawMessage == lastDebugRawMessage then
        return
    end

    lastDebugRawMessage = rawMessage
    debugMessage = "Debug: " .. rawMessage
    if holdSeconds and holdSeconds > 0 then
        debugPinnedUntil = os.clock() + holdSeconds
    end
    if debugLabel and debugLabel.Parent then
        debugLabel.Text = debugMessage
    end
end

local function updateStatus(force)
    local now = os.clock()
    if not force and now - lastStatusUpdate < STATUS_UPDATE_INTERVAL then
        return
    end
    lastStatusUpdate = now

    local config, level = getQuestConfig()
    clearCheckpointIfQuestChanged(config.questName)
    local detected = #collectNpcTargets(config.npcName)
    local questState = takenQuestKey == config.questName and "Quest tomada" or "Quest pendiente"
    local deathState = skipQuestAfterDeath and "Respawn: directo a NPC" or "Respawn: tomar quest"
    local speedState = "Set Speed: " .. (walkSpeedEnabled and "ON" or "OFF") .. " | Value: " .. tostring(customSpeed)
    local standState = autoStand and "Auto Stand: ON" or "Auto Stand: OFF"
    local prestigeState = autoPrestige and "Auto Prestige: ON" or "Auto Prestige: OFF"
    local statsState = autoStats and ("Auto Stats: ON | " .. selectedStat .. " x" .. tostring(statAmountValue)) or "Auto Stats: OFF"
    local checkpointState = "Checkpoint: no"
    if respawnSpawnPoint and respawnSpawnPoint.Parent then
        local pos = respawnSpawnPoint.Position
        checkpointState = string.format("SpawnPoint X:%d Y:%d Z:%d", math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5), math.floor(pos.Z + 0.5))
    elseif respawnCheckpoint then
        local pos = respawnCheckpoint.Position
        checkpointState = string.format("Checkpoint X:%d Y:%d Z:%d", math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5), math.floor(pos.Z + 0.5))
    end

    statusLabel.Text = string.format(
        "Nivel actual: %d\nQuest activa: %s\nNPC: %s | Detectados: %d/%d\n%s | %s | %s\n%s | %s | %s",
        level,
        config.questName,
        config.npcName,
        detected,
        config.expectedCount,
        questState,
        deathState,
        speedState,
        standState,
        prestigeState,
        statsState,
        checkpointState
    )

    if debugLabel and debugLabel.Parent then
        debugLabel.Text = debugMessage
    end

    autoBtn.Text = autoFarm and "Auto Farm: ON" or "Auto Farm: OFF"
    autoBtn.BackgroundColor3 = autoFarm and palette.danger or palette.accent
    autoStandBtn.Text = autoStand and "Auto Stand: ON" or "Auto Stand: OFF"
    autoStandBtn.BackgroundColor3 = autoStand and palette.accent or Color3.fromRGB(72, 84, 110)
    setSpeedBtn.Text = walkSpeedEnabled and "Set Speed: ON" or "Set Speed: OFF"
    setSpeedBtn.BackgroundColor3 = walkSpeedEnabled and palette.accent or palette.surface
    autoPrestigeBtn.Text = autoPrestige and "Auto Prestige: ON" or "Auto Prestige: OFF"
    autoPrestigeBtn.BackgroundColor3 = autoPrestige and palette.accent or palette.surface
    autoStatsBtn.Text = autoStats and "Auto Stats: ON" or "Auto Stats: OFF"
    autoStatsBtn.BackgroundColor3 = autoStats and palette.accent or palette.surface
    statModeBtn.Text = "Stat Mode: " .. selectedStat .. " x" .. tostring(statAmountValue)
    statAmountBox.Text = tostring(statAmountValue)
end

autoBtn.MouseButton1Click:Connect(function()
    autoFarm = not autoFarm
    syncAutoFarmState()
    stopMomentum()
    ensureWalkSpeed()
    updateStatus(true)
end)

autoStandBtn.MouseButton1Click:Connect(function()
    autoStand = not autoStand
    if autoStand and player.Character then
        task.spawn(function()
            summonStandIfNeeded()
        end)
    end
    updateStatus(true)
end)

setSpeedBtn.MouseButton1Click:Connect(function()
    walkSpeedEnabled = not walkSpeedEnabled
    ensureWalkSpeed()
    updateStatus(true)
end)

autoPrestigeBtn.MouseButton1Click:Connect(function()
    autoPrestige = not autoPrestige
    if autoPrestige then
        tryAutoPrestige()
    end
    updateStatus(true)
end)

autoStatsBtn.MouseButton1Click:Connect(function()
    autoStats = not autoStats
    if autoStats then
        applyAutoStats()
    end
    updateStatus(true)
end)

statModeBtn.MouseButton1Click:Connect(function()
    local statOrder = {"Strength", "Health", "Special", "HTalent"}
    local currentIndex = table.find(statOrder, selectedStat) or 1
    local nextIndex = currentIndex + 1
    if nextIndex > #statOrder then
        nextIndex = 1
    end
    selectedStat = statOrder[nextIndex]
    updateStatus(true)
end)

walkSpeedBox.FocusLost:Connect(function()
    customSpeed = clampWalkSpeed(walkSpeedBox.Text)
    walkSpeedBox.Text = tostring(customSpeed)
    ensureWalkSpeed()
    updateStatus(true)
end)

statAmountBox.FocusLost:Connect(function()
    local parsed = tonumber(statAmountBox.Text)
    statAmountValue = math.clamp(math.floor((parsed or statAmountValue) + 0.5), 1, 100)
    statAmountBox.Text = tostring(statAmountValue)
    updateStatus(true)
end)

rejoinBtn.MouseButton1Click:Connect(function()
    TeleportService:Teleport(game.PlaceId, player)
end)

farmModeBtn.MouseButton1Click:Connect(function()
    local currentIndex = table.find(FARM_MODES, selectedFarmMode) or 1
    local nextIndex = currentIndex + 1
    if nextIndex > #FARM_MODES then
        nextIndex = 1
    end
    selectedFarmMode = FARM_MODES[nextIndex]
    updateFarmModeButton()
end)

minimizeBtn.MouseButton1Click:Connect(function()
    setExpanded(not guiExpanded)
end)

closeBtn.MouseButton1Click:Connect(function()
    autoFarm = false
    syncAutoFarmState()
    stopMomentum()
    gui:Destroy()
end)

task.spawn(function()
    while gui.Parent do
        ensureWalkSpeed()
        if autoPrestige then
            tryAutoPrestige()
        end
        if autoStats then
            applyAutoStats()
        end

        if autoFarm and humanoid and humanoid.Health > 0 and not isRestoringCheckpoint then
            local config = getQuestConfig()

            if shouldTakeQuest(config) then
                setDebug("tomando quest: " .. tostring(config.questName))
                local ok, err = xpcall(function()
                    takeQuest(config)
                    updateStatus(true)
                end, debug.traceback)
                if not ok then
                    setDebug("error takeQuest: " .. tostring(err))
                end
            else
                setDebug("limpiando wave: " .. tostring(config.npcName))
                local ok, err = xpcall(function()
                    clearCurrentWave(config)
                    updateStatus(true)
                end, debug.traceback)
                if not ok then
                    setDebug("error wave: " .. tostring(err))
                end
            end
        end

        updateStatus()
        task.wait(0.2)
    end
end)

RunService.Stepped:Connect(function()
    if character then
        syncAutoFarmState()
    end
end)

RunService.Heartbeat:Connect(function()
    if walkSpeedEnabled then
        ensureWalkSpeed()
    end
end)

workspace.DescendantAdded:Connect(function(descendant)
    invalidateCachesForName(descendant.Name)
end)

workspace.DescendantRemoving:Connect(function(descendant)
    invalidateCachesForName(descendant.Name)
end)

setExpanded(true)
updateFarmModeButton()
updateStatus(true)

print("Script Farm cargado con progresion por nivel.")
