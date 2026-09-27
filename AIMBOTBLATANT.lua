-- ============================================
-- AIMBOT BLATANT HARD v5.4 | MODO DIOS
-- SilentAim | WallCheck | FOV | TeamCheck | Predicción Estable
-- Solo jugadores reales (excluye NPC/bots)
-- ============================================
local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local Holding = false
local LockedTarget = nil
local LockedCharacter = nil

-- ============================================
-- CONFIGURACIÓN
-- ============================================
local AimbotSettings = {
    Enabled          = true,
    Hitpart          = "Head",
    MaxDistance      = 5000,
    TeamCheck        = false,   -- OFF porque todos tienen Team nil
    TargetPriority   = "Distance",

    UseFOV           = true,
    FOV              = 400,

    -- Predicción
    PredictionFactor = 0.2,
    UseAdaptivePrediction = false,
    PredictionBuffer = 1.0,
    PredictionMin    = 0.05,
    PredictionMax    = 0.25,
    VelocityHistorySize = 5,
    SmoothingAlpha   = 0.8,
    AutoResetOnTargetChange = true,

    WallCheck        = true,
    MaxAnglePerFrame = 360,

    AutoShoot        = false,
    TriggerBot       = false,
    TriggerRadius    = 25,
    NoCooldown       = true,

    SilentAim        = false,
    SilentAimMethod  = "Mouse",
}

-- ============================================
-- ESTADO POR CHARACTER
-- ============================================
local velocityHistory = {}
local smoothedPositions = {}

local function resetCharacterState(character)
    if character then
        velocityHistory[character] = nil
        smoothedPositions[character] = nil
    end
end

local function resetAllState()
    velocityHistory = {}
    smoothedPositions = {}
end

local function pushVelocity(character, part)
    local hist = velocityHistory[character]
    if not hist then
        hist = {}
        velocityHistory[character] = hist
    end
    table.insert(hist, part.AssemblyLinearVelocity)
    if #hist > AimbotSettings.VelocityHistorySize then
        table.remove(hist, 1)
    end
    return hist
end

local function getFilteredVelocity(character, part)
    local hist = pushVelocity(character, part)
    if #hist == 0 then return Vector3.zero end

    local speeds = table.create(#hist)
    for i, v in ipairs(hist) do
        speeds[i] = v.Magnitude
    end
    table.sort(speeds)
    local medianSpeed = speeds[math.ceil(#speeds / 2)] or 0

    local avgDir = Vector3.zero
    local startIdx = math.max(1, #hist - 1)
    local count = 0
    for i = startIdx, #hist do
        local v = hist[i]
        if v.Magnitude > 0.01 then
            avgDir = avgDir + v.Unit
            count = count + 1
        end
    end
    if count == 0 or avgDir.Magnitude < 0.001 then
        return Vector3.zero
    end
    return avgDir.Unit * medianSpeed
end

local function getAdaptivePrediction()
    if not AimbotSettings.UseAdaptivePrediction then
        return AimbotSettings.PredictionFactor
    end
    local ok, ping = pcall(function()
        return LocalPlayer:GetNetworkPing()
    end)
    if ok and ping and ping > 0 then
        local t = ping * AimbotSettings.PredictionBuffer
        return math.clamp(t, AimbotSettings.PredictionMin, AimbotSettings.PredictionMax)
    end
    return AimbotSettings.PredictionFactor
end

local function smoothPrediction(character, newPos)
    if AimbotSettings.SmoothingAlpha >= 1 then
        smoothedPositions[character] = newPos
        return newPos
    end
    local old = smoothedPositions[character]
    if old then
        local result = old:Lerp(newPos, AimbotSettings.SmoothingAlpha)
        smoothedPositions[character] = result
        return result
    end
    smoothedPositions[character] = newPos
    return newPos
end

local function PredictPosition(TargetPart, character)
    if not TargetPart then return nil end

    if not character or not AimbotSettings.UseAdaptivePrediction then
        local v = TargetPart.AssemblyLinearVelocity or Vector3.zero
        return TargetPart.Position + v * AimbotSettings.PredictionFactor
    end

    local filteredVel = getFilteredVelocity(character, TargetPart)
    local predicted = TargetPart.Position + filteredVel * getAdaptivePrediction()
    return smoothPrediction(character, predicted)
end

-- ============================================
-- HITPART
-- ============================================
local function GetHitpart(character)
    if not character then return nil end
    return character:FindFirstChild(AimbotSettings.Hitpart)
        or character:FindFirstChild("HumanoidRootPart")
end

-- ============================================
-- WALLCHECK
-- ============================================
local function HasLineOfSight(targetPart)
    if not AimbotSettings.WallCheck then return true end
    local char = LocalPlayer.Character
    if not char then return false end
    local origin = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not origin then return false end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char, targetPart.Parent}
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local dir = (targetPart.Position - origin.Position)
    local result = workspace:Raycast(origin.Position, dir, params)
    return result == nil
end

-- ============================================
-- SELECCIÓN DE OBJETIVO (SOLO JUGADORES REALES)
-- ============================================
local function GetBestTarget()
    local bestTarget = nil
    local bestScore = math.huge

    local LocalCharacter = LocalPlayer.Character
    if not LocalCharacter or not LocalCharacter:FindFirstChild("HumanoidRootPart") then return nil end
    local LocalRoot = LocalCharacter.HumanoidRootPart

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            -- TeamCheck corregido: solo filtra si ambos equipos existen y son iguales
            if AimbotSettings.TeamCheck
                and player.Team
                and LocalPlayer.Team
                and player.Team == LocalPlayer.Team then
                continue
            end

            local Character = player.Character
            if Character then
                local Humanoid = Character:FindFirstChildOfClass("Humanoid")
                local TargetPart = GetHitpart(Character)

                if Humanoid and TargetPart and Humanoid.Health > 0 then
                    local Distance = (LocalRoot.Position - TargetPart.Position).Magnitude
                    if Distance > AimbotSettings.MaxDistance then continue end

                    if AimbotSettings.UseFOV then
                        local ScreenPos, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
                        if not OnScreen then continue end
                        local MousePos = UserInputService:GetMouseLocation()
                        local FOVDist = (MousePos - Vector2.new(ScreenPos.X, ScreenPos.Y)).Magnitude
                        if FOVDist > AimbotSettings.FOV then continue end
                    end

                    if not HasLineOfSight(TargetPart) then continue end

                    local score
                    if AimbotSettings.TargetPriority == "Health" then
                        score = Humanoid.Health
                    elseif AimbotSettings.TargetPriority == "Angle" then
                        local dir = (TargetPart.Position - Camera.CFrame.Position).Unit
                        score = math.deg(math.acos(math.clamp(Camera.CFrame.LookVector:Dot(dir), -1, 1)))
                    else
                        score = Distance
                    end

                    if score < bestScore then
                        bestScore = score
                        bestTarget = player
                    end
                end
            end
        end
    end

    return bestTarget
end

-- ============================================
-- SILENT AIM DATA
-- ============================================
local SilentAimData = {target = nil, part = nil}

-- ============================================
-- INPUT (SIN FILTRO gameProcessed)
-- ============================================
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
    Holding = true
    LockedTarget = GetBestTarget()
    LockedCharacter = LockedTarget and LockedTarget.Character or nil
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
    Holding = false
    if LockedCharacter then resetCharacterState(LockedCharacter) end
    LockedTarget = nil
    LockedCharacter = nil
    SilentAimData.target = nil
    SilentAimData.part = nil
end)

LocalPlayer.CharacterAdded:Connect(function()
    Holding = false
    if LockedCharacter then resetCharacterState(LockedCharacter) end
    LockedTarget = nil
    LockedCharacter = nil
    SilentAimData.target = nil
    SilentAimData.part = nil
    resetAllState()
end)

-- ============================================
-- LIMPIEZA
-- ============================================
Players.PlayerRemoving:Connect(function(player)
    local char = player.Character
    if char then resetCharacterState(char) end
end)

-- ============================================
-- BUCLE PRINCIPAL
-- ============================================
RunService.RenderStepped:Connect(function()
    pcall(function()
        if not AimbotSettings.Enabled or not Holding then return end

        if LockedTarget then
            local char = LockedTarget.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local stillValid = char
                and char == LockedCharacter
                and hum
                and hum.Health > 0
            if not stillValid then
                if AimbotSettings.AutoResetOnTargetChange and LockedCharacter then
                    resetCharacterState(LockedCharacter)
                end
                LockedTarget = nil
                LockedCharacter = nil
            end
        end

        local Target = LockedTarget or GetBestTarget()
        if not Target or not Target.Character then
            LockedTarget = nil
            LockedCharacter = nil
            return
        end

        if LockedCharacter and LockedCharacter ~= Target.Character then
            if AimbotSettings.AutoResetOnTargetChange then
                resetCharacterState(LockedCharacter)
            end
        end
        LockedTarget = Target
        LockedCharacter = Target.Character

        local Hitpart = GetHitpart(LockedCharacter)
        if not Hitpart then return end

        local Humanoid = LockedCharacter:FindFirstChildOfClass("Humanoid")
        if not Humanoid or Humanoid.Health <= 0 then return end

        local TargetPosition = PredictPosition(Hitpart, LockedCharacter)
        if not TargetPosition then return end

        local CurrentCF = Camera.CFrame
        local NewCF = CFrame.new(CurrentCF.Position, TargetPosition)

        if AimbotSettings.MaxAnglePerFrame >= 360 then
            Camera.CFrame = NewCF
        else
            local CurrentDir = CurrentCF.LookVector
            local TargetDir = (TargetPosition - CurrentCF.Position).Unit
            local Angle = math.deg(math.acos(math.clamp(CurrentDir:Dot(TargetDir), -1, 1)))
            if Angle <= AimbotSettings.MaxAnglePerFrame then
                Camera.CFrame = NewCF
            end
        end

        if AimbotSettings.SilentAim then
            SilentAimData.target = LockedTarget
            SilentAimData.part = Hitpart
        end
    end)
end)

-- ============================================
-- AUTO SHOOT
-- ============================================
if AimbotSettings.AutoShoot then
    RunService.RenderStepped:Connect(function()
        pcall(function()
            if not Holding or not LockedTarget then return end
            local char = LocalPlayer.Character
            if not char then return end
            local tool = char:FindFirstChildOfClass("Tool")
            if tool then
                pcall(function() tool:Activate() end)
                if tool:FindFirstChild("Shoot") then
                    pcall(function() tool.Shoot:Invoke() end)
                end
            end
        end)
    end)
end

-- ============================================
-- TRIGGER BOT
-- ============================================
if AimbotSettings.TriggerBot then
    RunService.RenderStepped:Connect(function()
        pcall(function()
            local Target = GetBestTarget()
            if not Target or not Target.Character then return end
            local Hitpart = GetHitpart(Target.Character)
            if not Hitpart then return end

            local ScreenPos, OnScreen = Camera:WorldToViewportPoint(Hitpart.Position)
            if OnScreen then
                local mousePos = UserInputService:GetMouseLocation()
                local dist = (mousePos - Vector2.new(ScreenPos.X, ScreenPos.Y)).Magnitude
                if dist < AimbotSettings.TriggerRadius then
                    local char = LocalPlayer.Character
                    if char then
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then
                            pcall(function() tool:Activate() end)
                        end
                    end
                end
            end
        end)
    end)
end

print("[AIMBOT BLATANT v5.4 MODO DIOS] Cargado")
print("  Hitpart: " .. AimbotSettings.Hitpart)
print("  FOV: " .. (AimbotSettings.UseFOV and tostring(AimbotSettings.FOV) or "inf"))
print("  WallCheck: " .. tostring(AimbotSettings.WallCheck))
print("  TeamCheck: " .. tostring(AimbotSettings.TeamCheck))
print("  SilentAim: " .. tostring(AimbotSettings.SilentAim))
print("  Priority: " .. AimbotSettings.TargetPriority)
print("  Solo jugadores reales: SI")
print("  Predicción Adaptativa: " .. tostring(AimbotSettings.UseAdaptivePrediction))
