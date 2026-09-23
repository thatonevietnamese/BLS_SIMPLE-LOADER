--========================================================--
--   ULTRA FAST AUTO STEAL & AUTO GOAL
--   CLEAN / NO DUPLICATE CONNECTIONS / SAFE RE-EXECUTE
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local BALL_NAME = "Ball"
local MIN_SPEED = 1
local MAX_SPEED = 1000
local SHOOT_FORCE = 100
local DEFAULT_STEAL_DISTANCE = 3
local GK_ROLE_NAMES = {"gk", "goalkeeper", "goal keeper", "keeper"}
local GK_TP_OFFSET = Vector3.new(0, 2.5, 0)
local TP_GOAL_OFFSET = Vector3.new(0, 3, 10)

--========================================================--
-- GLOBAL CLEANUP
-- A unique key lets a new execution destroy the previous
-- script instance and all of its connections.
--========================================================--

local GLOBAL_KEY = "__AutoGoalSpam_Cleanup_V1"

local oldCleanup = getgenv and getgenv()[GLOBAL_KEY]
if typeof(oldCleanup) == "function" then
    pcall(oldCleanup)
end

local Connections = {}
local Destroyed = false

local function addConnection(connection)
    if connection then
        Connections[#Connections + 1] = connection
    end
    return connection
end

local function disconnectAll()
    for i = #Connections, 1, -1 do
        local connection = Connections[i]
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
        Connections[i] = nil
    end
end

local screenGui

local function cleanup()
    if Destroyed then return end
    Destroyed = true

    disconnectAll()

    if screenGui then
        pcall(function()
            screenGui:Destroy()
        end)
        screenGui = nil
    else
        local oldGui = PlayerGui:FindFirstChild("AutoGoalSpamGui")
        if oldGui then
            pcall(function()
                oldGui:Destroy()
            end)
        end
    end
end

if getgenv then
    getgenv()[GLOBAL_KEY] = cleanup
end

--========================================================--
-- STATE
--========================================================--

local State = {
    AutoGoalEnabled = false,
    IsExecutingGoal = false,
}

--========================================================--
-- REMOTE
--========================================================--

local shootBallRemote = nil

local function resolveShootRemote()
    local ok, remote = pcall(function()
        local events = ReplicatedStorage:FindFirstChild("Events")
        return events and events:FindFirstChild("ShootBall")
    end)

    shootBallRemote = ok and remote or nil
    return shootBallRemote
end

resolveShootRemote()

local function fireShootRemote(direction, force, thirdArg)
    if Destroyed then return false end

    if not shootBallRemote or not shootBallRemote.Parent then
        resolveShootRemote()
    end

    if not shootBallRemote or not shootBallRemote:IsA("RemoteEvent") then
        return false
    end

    if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
        return false
    end

    direction = direction.Unit
    force = math.clamp(tonumber(force) or MIN_SPEED, MIN_SPEED, MAX_SPEED)

    local ok = pcall(function()
        shootBallRemote:FireServer(
            direction,
            force,
            thirdArg == nil and false or thirdArg
        )
    end)

    return ok
end

--========================================================--
-- HELPERS
--========================================================--

local function getCharacter()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")

    return char, hum, hrp
end

local function localHasBall()
    local char = LocalPlayer.Character
    if not char then return false end

    local ball = char:FindFirstChild(BALL_NAME, true)
    return ball ~= nil and ball:IsA("BasePart")
end

local function getRoleName()
    local roleObj =
        LocalPlayer:FindFirstChild("Role")
        or (
            LocalPlayer:FindFirstChild("Values")
            and LocalPlayer.Values:FindFirstChild("Role")
        )

    if roleObj and roleObj.Value ~= nil then
        return string.lower(tostring(roleObj.Value))
    end

    return ""
end

local function localIsGoalkeeper()
    local role = string.gsub(getRoleName(), "%s+", " ")

    for _, name in ipairs(GK_ROLE_NAMES) do
        if role == name then
            return true
        end
    end

    return false
end

local function sendVirtualKey(keyCode)
    if Destroyed or not VirtualInputManager then return end

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)
end

local function findFreeBall()
    local direct = workspace:FindFirstChild(BALL_NAME)

    if direct and direct:IsA("BasePart") then
        return direct
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if Destroyed then return nil end

        if obj:IsA("BasePart")
            and string.lower(obj.Name) == string.lower(BALL_NAME) then
            return obj
        end
    end

    return nil
end

local function resolveOwnGoalPart()
    local isHome =
        LocalPlayer.Team
        and string.lower(LocalPlayer.Team.Name) == "home"

    local goalName =
        isHome and "PlayerOneGoalArea"
        or "PlayerTwoGoalArea"

    local goal = workspace:FindFirstChild(goalName)

    if not goal then
        goalName =
            isHome and "PlayerOneGoal"
            or "PlayerTwoGoal"

        local map = workspace:FindFirstChild("Map")
        local goalModel = map and map:FindFirstChild(goalName)

        if goalModel then
            goal =
                goalModel:FindFirstChild("ScoreHitbox")
                or goalModel:FindFirstChild("Score")
        end
    end

    if goal then
        if goal:IsA("BasePart") then
            return goal
        end

        if goal:IsA("Model") then
            return goal.PrimaryPart
                or goal:FindFirstChildWhichIsA("BasePart", true)
        end
    end

    return nil
end

local function resolveOpponentGoalHitbox()
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end

    local isHome =
        LocalPlayer.Team
        and string.lower(LocalPlayer.Team.Name) == "home"

    local goalName =
        isHome and "PlayerTwoGoal"
        or "PlayerOneGoal"

    local goalModel = map:FindFirstChild(goalName)
    if not goalModel then return nil end

    local score =
        goalModel:FindFirstChild("ScoreHitbox")
        or goalModel:FindFirstChild("Score")

    if score and score:IsA("BasePart") then
        return score
    end

    local hitbox = goalModel:FindFirstChild("ScoreHitbox", true)

    if hitbox and hitbox:IsA("BasePart") then
        return hitbox
    end

    return goalModel:FindFirstChildWhichIsA("BasePart", true)
end

local function findBallTarget()
    for _, plr in ipairs(Players:GetPlayers()) do
        if Destroyed then return nil, nil end

        if plr ~= LocalPlayer and plr.Character then
            local ball =
                plr.Character:FindFirstChild(BALL_NAME, true)

            local hrp =
                plr.Character:FindFirstChild("HumanoidRootPart")

            if ball and hrp then
                return hrp, plr
            end
        end
    end

    local freeBall = findFreeBall()

    if freeBall then
        return freeBall, nil
    end

    return nil, nil
end

--========================================================--
-- CORE ACTIONS
--========================================================--

local function executeGoalShot()
    if Destroyed or State.IsExecutingGoal then return end

    State.IsExecutingGoal = true

    local goalHitbox = resolveOpponentGoalHitbox()

    if not goalHitbox then
        State.IsExecutingGoal = false
        return
    end

    local _, _, rootPart = getCharacter()
    local savedCFrame = rootPart and rootPart.CFrame

    if rootPart then
        rootPart.CFrame =
            CFrame.new(
                goalHitbox.Position + TP_GOAL_OFFSET,
                goalHitbox.Position
            )

        task.wait(0.02)

        if Destroyed then
            State.IsExecutingGoal = false
            return
        end
    end

    local shootDir =
        rootPart
        and (goalHitbox.Position - rootPart.Position).Unit
        or Vector3.new(0, 0, -1)

    fireShootRemote(shootDir, SHOOT_FORCE, false)

    task.wait(0.02)

    if Destroyed then
        State.IsExecutingGoal = false
        return
    end

    local targetBall = findFreeBall()

    if targetBall then
        pcall(function()
            targetBall.CFrame = goalHitbox.CFrame
            targetBall.AssemblyLinearVelocity = Vector3.zero
        end)
    end

    if rootPart and savedCFrame and rootPart.Parent then
        pcall(function()
            rootPart.CFrame = savedCFrame
        end)
    end

    State.IsExecutingGoal = false
end

local function spamStealStep()
    if Destroyed then return end

    local _, _, rootPart = getCharacter()
    if not rootPart then return end

    local targetPart = findBallTarget()
    if not targetPart then return end
    if not targetPart.Parent then return end

    if localIsGoalkeeper() then
        local ownGoal = resolveOwnGoalPart()

        if ownGoal then
            rootPart.CFrame =
                CFrame.new(ownGoal.Position + GK_TP_OFFSET)

            sendVirtualKey(Enum.KeyCode.Q)
        end
    end

    if Destroyed or not targetPart.Parent then return end

    rootPart.CFrame =
        CFrame.new(
            targetPart.Position
            + Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)
        )

    sendVirtualKey(Enum.KeyCode.E)
end

--========================================================--
-- GUI
--========================================================--

local oldGui = PlayerGui:FindFirstChild("AutoGoalSpamGui")
if oldGui then
    pcall(function()
        oldGui:Destroy()
    end)
end

screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoGoalSpamGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(220, 100)
mainFrame.Position = UDim2.new(0.5, -110, 0.4, -50)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 60, 60)
stroke.Transparency = 0.2
stroke.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -20, 0, 30)
titleLabel.Position = UDim2.fromOffset(10, 5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "⚡ SPAM AUTO GOAL"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = mainFrame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 45)
toggleBtn.Position = UDim2.fromOffset(10, 42)
toggleBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "AUTO GOAL: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.Parent = mainFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = toggleBtn

--========================================================--
-- DRAGGING
--========================================================--

local dragging = false
local dragStart
local startPos
local dragEndConnection

addConnection(titleLabel.InputBegan:Connect(function(input)
    if Destroyed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position

        addConnection(input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end))
    end
end))

addConnection(UserInputService.InputChanged:Connect(function(input)
    if Destroyed or not dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then

        local delta = input.Position - dragStart

        mainFrame.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end
end))

addConnection(toggleBtn.MouseButton1Click:Connect(function()
    if Destroyed then return end

    State.AutoGoalEnabled = not State.AutoGoalEnabled

    if State.AutoGoalEnabled then
        toggleBtn.Text = "AUTO GOAL: ON"
        toggleBtn.BackgroundColor3 =
            Color3.fromRGB(220, 50, 50)
    else
        toggleBtn.Text = "AUTO GOAL: OFF"
        toggleBtn.BackgroundColor3 =
            Color3.fromRGB(38, 38, 48)
    end
end))

--========================================================--
-- MAIN LOOP
-- One Heartbeat connection only.
-- Throttled so it does not execute expensive searches every
-- rendered frame.
--========================================================--

local STEP_INTERVAL = 0.05
local accumulator = 0

addConnection(RunService.Heartbeat:Connect(function(deltaTime)
    if Destroyed or not State.AutoGoalEnabled then
        return
    end

    accumulator += deltaTime

    if accumulator < STEP_INTERVAL then
        return
    end

    accumulator = 0

    if localHasBall() then
        executeGoalShot()
    else
        spamStealStep()
    end
end))
