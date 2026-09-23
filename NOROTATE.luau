local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local RenderConnection

local function IsShiftLock()
    return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function SetupCharacter(Character)
    if RenderConnection then
        RenderConnection:Disconnect()
        RenderConnection = nil
    end

    local Humanoid = Character:WaitForChild("Humanoid")
    local RootPart = Character:WaitForChild("HumanoidRootPart")

    RenderConnection = RunService.RenderStepped:Connect(function()
        if not Character.Parent then
            return
        end

        -- Không Shift Lock -> giao lại quyền cho Roblox mặc định
        if not IsShiftLock() then
            if not Humanoid.AutoRotate then
                Humanoid.AutoRotate = true
            end
            return
        end

        local Camera = workspace.CurrentCamera
        if not Camera then
            return
        end

        -- Kích hoạt Shift Lock -> Tắt AutoRotate để xoay CFrame tức thì
        Humanoid.AutoRotate = false

        local Look = Camera.CFrame.LookVector
        local Direction = Vector3.new(Look.X, 0, Look.Z)

        if Direction.Magnitude > 0.001 then
            RootPart.CFrame = CFrame.lookAt(
                RootPart.Position,
                RootPart.Position + Direction.Unit
            )
        end
    end)
end

Player.CharacterAdded:Connect(function(Character)
    task.wait(0.2)
    SetupCharacter(Character)
end)

if Player.Character then
    SetupCharacter(Player.Character)
end
