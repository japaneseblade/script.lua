if not LPH_OBFUSCATED then
    LPH_NO_VIRTUALIZE = function(...) return ... end
end

--// Services
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
        TriggerState = false,
        LastTriggerTime = 0,
    },
    Visuals = {}
}

--// Game Detection
local CurrentGame = nil
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

local function GetDeeHoodUpdater()
    if CurrentGame and CurrentGame.Name == "Dee Hood" then
        for _, plr in ipairs(Players:GetPlayers()) do
            local bp = plr:FindFirstChild("Backpack")
            if bp then
                local attr = bp:GetAttribute("muv") or bp:GetAttribute("MUV")
                if attr then
                    CurrentGame.Updater = attr
                    return attr
                end
            end
        end
    end
    return CurrentGame and CurrentGame.Updater
end

local function GetRemote()
    return ReplicatedStorage:FindFirstChild("MainEvent") or ReplicatedStorage:FindFirstChild("MainRemotes")
end

--// Helpers
local function GetRoot(char) 
    return char and char:FindFirstChild("HumanoidRootPart") 
end

local function GetBestPart(target, config)
    if not target or not target.Character then return nil end
    local char = target.Character
    
    if config.Point == "Head" then
        return char:FindFirstChild("Head")
    elseif config.Point == "Nearest Point" or config.Type == "Advanced" then
        local root = GetRoot(char)
        local head = char:FindFirstChild("Head")
        if not root or not head then return root end
        
        local cameraPos = Camera.CFrame.Position
        local rootDist = (root.Position - cameraPos).Magnitude
        local headDist = (head.Position - cameraPos).Magnitude
        
        return headDist < rootDist * config.Scale and head or root
    end
    return GetRoot(char)
end

local function ShouldTarget(plr)
    if not plr or not plr.Character then return false end
    local char = plr.Character
    local hum = char:FindFirstChild("Humanoid")
    local root = GetRoot(char)
    if not (hum and root) or hum.Health <= 0 then return false end

    local c = shared.Saved.Conditions
    if c.Knocked and (char:FindFirstChild("BodyEffects") and char.BodyEffects:FindFirstChild("K.O") and char.BodyEffects["K.O"].Value) then return false end
    if c.SelfKnocked and (Self.Character and Self.Character:FindFirstChild("BodyEffects") and Self.Character.BodyEffects:FindFirstChild("K.O") and Self.Character.BodyEffects["K.O"].Value) then return false end
    if c.Grabbed and char:FindFirstChild("GRABBING_CONSTRAINT") then return false end
    if c.Forcefield and char:FindFirstChild("ForceField") then return false end

    if c.Visible or c.Test then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {Self.Character}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local res = Workspace:Raycast(Camera.CFrame.Position, (root.Position - Camera.CFrame.Position).Unit * 2000, params)
        if res and not res.Instance:IsDescendantOf(char) then return false end
    end
    return true
end

local function GetFOVBox(target, isSilent)
    if not target or not target.Character then return nil end
    local root = GetRoot(target.Character)
    if not root then return nil end

    local screen, onScreen = Camera:WorldToViewportPoint(root.Position)
    if not onScreen or screen.Z <= 0 then return nil end

    local cfg = (isSilent and shared.Saved.SilentAim or shared.Saved.TriggerBot).FOV.FOV['Weapon Configuration']
    local tool = Self.Character and Self.Character:FindFirstChildOfClass("Tool")
    local cat = (tool and tool.Name:find("Shotgun")) and "Shotguns" or (tool and tool.Name:find("Pistol") and "Pistols") or "Others"

    local f = cfg[cat] or cfg.Others
    local scale = (root.Size.Y * Camera.ViewportSize.Y) / (screen.Z * 2) * 78 / Camera.FieldOfView

    return {
        X = screen.X - f.WidthLeftSide * scale,
        Y = screen.Y - f.HeightUpper * scale,
        Width = (f.WidthLeftSide + f.WidthRightSide) * scale,
        Height = (f.HeightUpper + f.HeightLower) * scale,
        Visible = onScreen
    }
end

local function GetHitPosition(target, isCamlock)
    if not target or not target.Character then return nil end
    local part = GetBestPart(target, isCamlock and shared.Saved.Camlock or shared.Saved.SilentAim)
    if not part then return nil end

    local cfg = isCamlock and shared.Saved.Camlock.Prediction or shared.Saved.SilentAim.Prediction
    if not cfg.Enabled then return part.Position end

    local hum = target.Character:FindFirstChild("Humanoid")
    local velocity = part.AssemblyLinearVelocity
    local isAir = hum and (hum:GetState() == Enum.HumanoidStateType.Freefall or hum:GetState() == Enum.HumanoidStateType.Jumping)

    local pred = isAir and cfg.Air or cfg.Ground
    return part.Position + (velocity * pred)
end

--// Silent Aim
local function SilentAimLogic()
    if not shared.Saved.SilentAim.Enabled then return end

    local target = Mango.Locals.SilentAimTarget
    if not target or not ShouldTarget(target) then return end

    local hitPos = GetHitPosition(target, false)
    if not hitPos then return end

    if shared.Saved.Enhancements["Client Redirection"].Enabled and CurrentGame then
        local remote = GetRemote()
        local updater = CurrentGame.Updater or GetDeeHoodUpdater()
        if remote and updater then
            remote:FireServer(updater, hitPos)
        end
    end
end

--// Camlock
local function AimAssist()
    if not shared.Saved.Camlock.Enabled then return end
    local target = Mango.Locals.AimAssistTarget
    if not target or not ShouldTarget(target) then return end

    local hitPos = GetHitPosition(target, true)
    if not hitPos then return end

    local targetCF = CFrame.new(Camera.CFrame.Position, hitPos)
    local smooth = 1

    if shared.Saved.Camlock.Smoothing.Enabled then
        local hum = target.Character:FindFirstChild("Humanoid")
        local isAir = hum and (hum:GetState() == Enum.HumanoidStateType.Freefall or hum:GetState() == Enum.HumanoidStateType.Jumping)
        smooth = isAir and shared.Saved.Camlock.Smoothing.Air or shared.Saved.Camlock.Smoothing.Ground
    end

    Camera.CFrame = Camera.CFrame:Lerp(targetCF, smooth)
end

--// TriggerBot
local function TriggerBot()
    if not (shared.Saved.TriggerBot.Enabled and Mango.Locals.TriggerState) then return end

    local target = Mango.Locals.SilentAimTarget or Mango.Locals.AimAssistTarget
    if not target then target = GetClosestPlayerToCursor() end
    if not target or not ShouldTarget(target) then return end

    local box = GetFOVBox(target, false)
    if not box then return end

    local mpos = UserInputService:GetMouseLocation()
    local inside = mpos.X >= box.X and mpos.X <= box.X + box.Width and
                   mpos.Y >= box.Y and mpos.Y <= box.Y + box.Height

    if inside then
        local tool = Self.Character and Self.Character:FindFirstChildOfClass("Tool")
        if tool then
            local now = tick()
            local delay = shared.Saved.TriggerBot.Delay.Enabled and (shared.Saved.TriggerBot.Delay.Weapon[tool.Name] or 0.05) or 0
            if now - Mango.Locals.LastTriggerTime >= delay then
                Mango.Locals.LastTriggerTime = now
                tool:Activate()
            end
        end
    end
end

local function GetClosestPlayerToCursor()
    local closest, dist = nil, math.huge
    local mpos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == Self or not plr.Character then continue end
        if not ShouldTarget(plr) then continue end

        local box = GetFOVBox(plr, true)
        if shared.Saved.SilentAim.FOV.Visible and box then
            if not (mpos.X >= box.X and mpos.X <= box.X + box.Width and
                    mpos.Y >= box.Y and mpos.Y <= box.Y + box.Height) then
                continue
            end
        end

        local root = GetRoot(plr.Character)
        local screen = Camera:WorldToViewportPoint(root.Position)
        if screen.Z <= 0 then continue end

        local mag = (Vector2.new(screen.X, screen.Y) - mpos).Magnitude
        if mag < dist then
            dist = mag
            closest = plr
        end
    end
    return closest
end

--// Visuals
local function UpdateVisuals()
    if not shared.Saved.SilentAim.FOV.Visible then 
        if Mango.Visuals.SilentFOV then Mango.Visuals.SilentFOV.Visible = false end
        return 
    end

    local target = Mango.Locals.SilentAimTarget
    if not target then 
        if Mango.Visuals.SilentFOV then Mango.Visuals.SilentFOV.Visible = false end
        return 
    end

    local box = GetFOVBox(target, true)
    if not box then return end

    if not Mango.Visuals.SilentFOV then
        Mango.Visuals.SilentFOV = Drawing.new("Square")
        Mango.Visuals.SilentFOV.Thickness = 1.8
        Mango.Visuals.SilentFOV.Filled = false
        Mango.Visuals.SilentFOV.Color = Color3.fromRGB(0, 255, 120)
        Mango.Visuals.SilentFOV.Transparency = 1
    end

    Mango.Visuals.SilentFOV.Position = Vector2.new(box.X, box.Y)
    Mango.Visuals.SilentFOV.Size = Vector2.new(box.Width, box.Height)
    Mango.Visuals.SilentFOV.Visible = true
end

--// Spread Modifier
local spreadMult = 1.0
local function UpdateSpread()
    spreadMult = 1.0
    if not shared.Saved.Enhancements['Spread Modifier'].Enabled then return end

    local tool = Self.Character and Self.Character:FindFirstChildOfClass("Tool")
    if tool and shared.Saved.Enhancements['Spread Modifier'].Weapon[tool.Name] then
        spreadMult = shared.Saved.Enhancements['Spread Modifier'].Weapon[tool.Name]
        if shared.Saved.Enhancements['Spread Modifier'].Randomizer.Enabled then
            spreadMult = spreadMult * (1 - shared.Saved.Enhancements['Spread Modifier'].Randomizer.Value + math.random() * shared.Saved.Enhancements['Spread Modifier'].Randomizer.Value * 2)
        end
    end
end
RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(UpdateSpread))

--// Main Loop
RunService.PreRender:Connect(LPH_NO_VIRTUALIZE(function()
    SilentAimLogic()
    AimAssist()
    TriggerBot()
    UpdateVisuals()
end))

--// Speed
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

--// Keybinds
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local key = input.KeyCode.Name ~= "Unknown" and input.KeyCode.Name or input.UserInputType.Name

    if key == shared.Saved.SilentAim.Toggle then
        if shared.Saved.SilentAim.Mode == "Target" then
            Mango.Locals.SilentAimTarget = Mango.Locals.SilentAimTarget and nil or GetClosestPlayerToCursor()
        else
            Mango.Locals.SilentAimTarget = GetClosestPlayerToCursor()
        end

        if shared.Saved.Camlock.Sticky then
            Mango.Locals.AimAssistTarget = Mango.Locals.AimAssistTarget and nil or GetClosestPlayerToCursor()
        else
            Mango.Locals.AimAssistTarget = GetClosestPlayerToCursor()
        end
    end

    if key == shared.Saved.SilentAim.Untoggle then
        Mango.Locals.SilentAimTarget = nil
        Mango.Locals.AimAssistTarget = nil
    end

    if key == shared.Saved.TriggerBot.Toggle then
        if shared.Saved.TriggerBot.Type == 'Hold' then
            Mango.Locals.TriggerState = true
        else
            Mango.Locals.TriggerState = not Mango.Locals.TriggerState
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if shared.Saved.TriggerBot.Type == 'Hold' and (input.KeyCode.Name == shared.Saved.TriggerBot.Toggle or input.UserInputType.Name == shared.Saved.TriggerBot.Toggle) then
        Mango.Locals.TriggerState = false
    end
end)
