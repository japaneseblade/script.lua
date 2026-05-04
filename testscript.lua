
if not LPH_OBFUSCATED then
    LPH_NO_VIRTUALIZE = function(...) return ... end
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Self = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = Self:GetMouse()

local Mango = {
    Locals = {
        SilentAimTarget = nil,
        AimAssistTarget = nil,
        LockedTarget = nil,
        TriggerState = false,
        HitPosition = nil,
        LastShot = 0,
    }
}

--// Game Detection (Dee Hood + others kept)
local CurrentGame 
local Games = {
    [1008451066] = {Name = 'Da Hood', Updater = 'UpdateMousePosI2'},
    [139845055199772] = {Name = 'Dee Hood', Updater = nil},
    [8796903567] = {Name = 'Der Hood', Updater = "D3RHooDMSOUEPoS233^+"},
    [9131407049] = {Name = 'Zee Hood', Updater = "DEAHOODMOUSEPOSx3^3"},
    [8261267092] = {Name = 'Zea Hood', Updater = "DEAHOODMOUSEPOSx3^3"},
}

if Games[game.GameId] then
    CurrentGame = Games[game.GameId]
end

--// Helpers
local function ValidateClient(plr)
    if not plr or not plr.Character then return nil end
    local hum = plr.Character:FindFirstChild("Humanoid")
    local root = hum and hum.RootPart
    return plr.Character, hum, root
end

local function IsKnocked(char)
    return char and char:FindFirstChild("BodyEffects") and char.BodyEffects:FindFirstChild("K.O") and char.BodyEffects["K.O"].Value
end

local function IsGrabbed(char)
    return char and char:FindFirstChild("GRABBING_CONSTRAINT") ~= nil
end

local function IsVisible(part)
    if not part then return false end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {Self.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local result = Workspace:Raycast(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position).Unit * 2000, params)
    return not result or result.Instance:IsDescendantOf(part.Parent)
end

local function ShouldTarget(target)
    if not target or not target.Character then return false end
    local char, hum, root = ValidateClient(target)
    if not (char and hum and root) or hum.Health <= 0 then return false end

    local c = shared.Saved.Conditions
    if c.Knocked and IsKnocked(char) then return false end
    if c.SelfKnocked and IsKnocked(Self.Character) then return false end
    if c.Grabbed and IsGrabbed(char) then return false end
    if c.Forcefield and char:FindFirstChild("ForceField") then return false end
    if (c.Visible or c.Test) and not IsVisible(root) then return false end

    return true
end

local function GetClosestPlayerToCursor()
    local closest, dist = nil, math.huge
    local mpos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == Self or not plr.Character then continue end
        if not ShouldTarget(plr) then continue end

        local _, _, root = ValidateClient(plr)
        if not root then continue end

        local screen, onScreen = Camera:WorldToViewportPoint(root.Position)
        if not onScreen then continue end

        local mag = (Vector2.new(screen.X, screen.Y) - mpos).Magnitude
        if mag < dist then
            dist = mag
            closest = plr
        end
    end
    return closest
end

local function GetHitPosition(target)
    if not target or not target.Character then return nil end
    local root = target.Character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end

--// SAFE Spread Modifier (Xeno Fixed)
local spreadMult = 1.0

local function UpdateSpread()
    spreadMult = 1.0
    if not shared.Saved.Enhancements['Spread Modifier'].Enabled then return end

    local tool = Self.Character and Self.Character:FindFirstChildOfClass("Tool")
    if tool and shared.Saved.Enhancements['Spread Modifier'].Weapon[tool.Name] then
        spreadMult = shared.Saved.Enhancements['Spread Modifier'].Weapon[tool.Name]
        if shared.Saved.Enhancements['Spread Modifier'].Randomizer.Enabled then
            spreadMult = spreadMult * (0.65 + math.random() * 0.7)
        end
    end
end

RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(UpdateSpread))

--// TriggerBot
local function TriggerBot()
    if not shared.Saved.TriggerBot.Enabled or not Mango.Locals.TriggerState then return end

    local target = Mango.Locals.SilentAimTarget or GetClosestPlayerToCursor()
    if not ShouldTarget(target) then return end

    local root = target.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local screen = Camera:WorldToViewportPoint(root.Position)
    local mousePos = UserInputService:GetMouseLocation()

    if (Vector2.new(screen.X, screen.Y) - mousePos).Magnitude < 80 then
        local tool = Self.Character and Self.Character:FindFirstChildOfClass("Tool")
        if tool then tool:Activate() end
    end
end

--// Camlock
local function AimAssist()
    if not shared.Saved.Camlock.Enabled then return end

    local target = Mango.Locals.AimAssistTarget
    if not target or not ShouldTarget(target) then return end

    local hitPos = GetHitPosition(target)
    if not hitPos then return end

    local targetCF = CFrame.new(Camera.CFrame.Position, hitPos)
    local smooth = shared.Saved.Camlock.Smoothing.Enabled and 
        (target.Character.Humanoid:GetState() == Enum.HumanoidStateType.Freefall and shared.Saved.Camlock.Smoothing.Air or shared.Saved.Camlock.Smoothing.Ground) or 1

    Camera.CFrame = Camera.CFrame:Lerp(targetCF, smooth)
end

--// Silent Aim
local function SilentAimLogic()
    if not shared.Saved.SilentAim.Enabled then return end

    if shared.Saved.SilentAim.Mode == "Auto" then
        Mango.Locals.SilentAimTarget = GetClosestPlayerToCursor()
    end

    local target = Mango.Locals.SilentAimTarget
    if not target or not ShouldTarget(target) then return end

    Mango.Locals.HitPosition = GetHitPosition(target)

    if CurrentGame and CurrentGame.Updater and shared.Saved.Enhancements["Client Redirection"].Enabled and Mango.Locals.HitPosition then
        local remote = ReplicatedStorage:FindFirstChild("MainEvent") or ReplicatedStorage:FindFirstChild("MainRemotes")
        if remote then
            remote:FireServer(CurrentGame.Updater, Mango.Locals.HitPosition)
        end
    end
end

--// Speed Modifiers (Original)
RunService.RenderStepped:Connect(function()
    if not shared.Saved['Speed Modifiers'].Enabled then return end
    local hum = Self.Character and Self.Character:FindFirstChild("Humanoid")
    if not hum then return end

    local mul = shared.Saved['Speed Modifiers'].Normal.Multiplier
    local body = Workspace:FindFirstChild("Players") and Workspace.Players:FindFirstChild(Self.Name) and Workspace.Players[Self.Name]:FindFirstChild("BodyEffects")

    if body then
        if body:FindFirstChild("Reload") and body.Reload.Value then
            mul = shared.Saved['Speed Modifiers'].Reloading.Multiplier
        elseif body:FindFirstChild("GunFiring") and body.GunFiring.Value then
            mul = shared.Saved['Speed Modifiers'].Shooting.Multiplier
        end
    end

    hum.WalkSpeed = shared.Saved['Speed Modifiers']['Multiplier Mode'] == 'Multiply' 
        and hum.WalkSpeed * mul 
        or mul
end)

--// Main Loop
RunService.PreRender:Connect(LPH_NO_VIRTUALIZE(function()
    SilentAimLogic()
    AimAssist()
    TriggerBot()
end))

--// Keybinds
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end

    if input.UserInputType.Name == 'Q' then
        if Mango.Locals.SilentAimTarget then
            Mango.Locals.SilentAimTarget = nil
            Mango.Locals.LockedTarget = nil
        else
            Mango.Locals.SilentAimTarget = GetClosestPlayerToCursor()
            Mango.Locals.LockedTarget = Mango.Locals.SilentAimTarget
        end

        if shared.Saved.Camlock.Sticky then
            Mango.Locals.AimAssistTarget = Mango.Locals.AimAssistTarget and nil or GetClosestPlayerToCursor()
        else
            Mango.Locals.AimAssistTarget = GetClosestPlayerToCursor()
        end
    end

    if input.UserInputType.Name == shared.Saved.TriggerBot.Toggle or input.KeyCode.Name == shared.Saved.TriggerBot.Toggle then
        Mango.Locals.TriggerState = shared.Saved.TriggerBot.Type == 'Hold' or not Mango.Locals.TriggerState
    end
end)
