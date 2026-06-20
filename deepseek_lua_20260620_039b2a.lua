local repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local RS = game:GetService("RunService")
local P = game:GetService("Players")
local LP = P.LocalPlayer
local V = CFrame.new(9000, 9000, 9000)
local T = {}
local spamTick = false

-- Initialize api table
local api = {}

-- Tool cache
local ToolCache = {
    instance = nil,
    offset = nil,
    handle = nil,
    ammo = 0,
    ignores_spawn = false,
    gun = false,
    shotgun = false,
    max_ammo = 0,
    automatic = false,
    client = false
}

-- Data cache for players
local DataCache = {}

-- Status cache for players
local StatusCache = {}

-- Character cache for players
local CharacterCache = {}

-- Team/Crew cache
local CrewCache = {}

-- Target caches for different aim types
local TargetCaches = {
    ragebot = {
        part = nil,
        player = nil
    },
    aimbot = {
        part = nil,
        player = nil
    },
    silent = {
        part = nil,
        player = nil
    }
}

-- Ragebot state management
local RagebotState = {
    Forced = false,
    ForcedValue = false,
    OriginalValue = false,
    Status = "inactive",
    Data = nil,
    StrafeCallbacks = {},
    Unsafe = false,
    FakeOverride = false,
    FakeCFrame = nil,
    FakeRefresh = false,
    CurrentFakePosition = nil,
    FakeEnabled = false,
    IsDesyncing = false,
    DesyncPriority = nil,
    ClientCFrame = nil,
    LastKnownClientCFrame = nil,
    DesyncCFrame = nil,
    UseCustomDesync = false,
    ServerCFrame = nil,
    DesyncCallbacks = {
        [1] = {},
        [2] = {}
    },
    CurrentDesyncCFrame = nil,
    ProcessingDesync = false
}

local Window = Library:CreateWindow({
	Title = "aim.cc Private",
	Center = true,
	AutoShow = true,
	Resizable = true,
	ShowCustomCursor = true,
	NotifySide = "Left",
	TabPadding = 8,
	MenuFadeTime = 0.2
})

local Tabs = {
	Main = Window:AddTab("Main"),
	Misc = Window:AddTab("Misc"),
	["settings"] = Window:AddTab("settings"),
}

-- API functions
function api:is_ragebot()
    if RagebotState.Forced then
        return RagebotState.ForcedValue
    end
    return Toggles.RagebotEnabled and Toggles.RagebotEnabled.Value or false
end

function api:set_ragebot(enabled)
    if not Toggles.RagebotEnabled then return false end
    
    if enabled then
        RagebotState.Forced = true
        RagebotState.ForcedValue = true
        RagebotState.OriginalValue = Toggles.RagebotEnabled.Value
        Toggles.RagebotEnabled:SetValue(true)
    else
        RagebotState.Forced = false
        if not RagebotState.OriginalValue then
            Toggles.RagebotEnabled:SetValue(false)
        end
    end
    return true
end

function api:get_ragebot_status()
    if not api:is_ragebot() then
        return "inactive", nil
    end
    if RagebotState.Status then
        return RagebotState.Status, RagebotState.Data
    end
    return "no target", nil
end

function api:set_ragebot_status(status, data)
    RagebotState.Status = status
    RagebotState.Data = data
    updateStatusDisplay()
end

function api:ragebot_strafe_override(callback)
    if type(callback) ~= "function" then
        error("Callback must be a function", 2)
    end
    table.insert(RagebotState.StrafeCallbacks, callback)
    return nil
end

function api:add_desync_callback(priority, callback)
    if type(callback) ~= "function" then
        error("Callback must be a function", 2)
    end
    if priority ~= 1 and priority ~= 2 then
        error("Priority must be 1 or 2", 2)
    end
    
    table.insert(RagebotState.DesyncCallbacks[priority], callback)
    return nil
end

function api:set_fake(override, cframe, refresh)
    RagebotState.FakeOverride = override
    RagebotState.FakeCFrame = cframe
    RagebotState.FakeRefresh = refresh or false
    
    if not override then
        if Toggles.FakePositionEnabled and Toggles.FakePositionEnabled.Value then
            RagebotState.FakeEnabled = true
            if refresh then
                RagebotState.CurrentFakePosition = nil
            end
        end
        return nil
    end
    
    if override and cframe then
        RagebotState.FakeEnabled = true
        RagebotState.CurrentFakePosition = cframe
        if refresh then
            RagebotState.CurrentFakePosition = nil
        end
    elseif override then
        RagebotState.FakeEnabled = true
        RagebotState.CurrentFakePosition = nil
    end
    
    updateStatusDisplay()
    return nil
end

function api:can_desync()
    if RagebotState.IsDesyncing then
        return false
    end
    if RagebotState.Status == "buying" or 
       RagebotState.Status == "hiding" or 
       RagebotState.Status == "killing" then
        return false
    end
    if RagebotState.Unsafe then
        return true
    end
    if RagebotState.FakeEnabled and Toggles.FakePositionEnabled.Value then
        return true
    end
    return true
end

function api:get_client_cframe()
    if not RagebotState.IsDesyncing then
        return nil
    end
    if RagebotState.UseCustomDesync and RagebotState.DesyncCFrame then
        return RagebotState.DesyncCFrame
    end
    if RagebotState.ClientCFrame then
        return RagebotState.ClientCFrame
    end
    if RagebotState.LastKnownClientCFrame then
        return RagebotState.LastKnownClientCFrame
    end
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        return LP.Character.HumanoidRootPart.CFrame
    end
    return nil
end

function api:get_desync_cframe()
    if not RagebotState.IsDesyncing then
        return nil
    end
    if RagebotState.CurrentDesyncCFrame then
        return RagebotState.CurrentDesyncCFrame
    end
    if RagebotState.ServerCFrame then
        return RagebotState.ServerCFrame
    end
    if RagebotState.UseCustomDesync and RagebotState.DesyncCFrame then
        return RagebotState.DesyncCFrame
    end
    return api:get_client_cframe()
end

function api:set_desync_cframe(point)
    if not point or type(point) ~= "CFrame" then
        error("Expected CFrame argument", 2)
        return nil
    end
    RagebotState.DesyncCFrame = point
    RagebotState.UseCustomDesync = true
    updateStatusDisplay()
    return nil
end

function api:clear_desync_cframe()
    RagebotState.DesyncCFrame = nil
    RagebotState.UseCustomDesync = false
    updateStatusDisplay()
    return nil
end

function api:update_server_cframe(cframe)
    RagebotState.ServerCFrame = cframe
    updateStatusDisplay()
    return nil
end

function api:update_client_cframe(cframe)
    RagebotState.ClientCFrame = cframe
    if cframe then
        RagebotState.LastKnownClientCFrame = cframe
    end
    updateStatusDisplay()
    return nil
end

function api:start_desync(priority)
    RagebotState.IsDesyncing = true
    RagebotState.DesyncPriority = priority or "normal"
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        RagebotState.ClientCFrame = LP.Character.HumanoidRootPart.CFrame
        RagebotState.LastKnownClientCFrame = RagebotState.ClientCFrame
        RagebotState.ServerCFrame = RagebotState.ClientCFrame
    end
    updateStatusDisplay()
end

function api:end_desync()
    RagebotState.IsDesyncing = false
    RagebotState.DesyncPriority = nil
    RagebotState.ClientCFrame = nil
    RagebotState.ServerCFrame = nil
    RagebotState.CurrentDesyncCFrame = nil
    updateStatusDisplay()
end

function api:get_tool()
    if LP.Character then
        local tool = LP.Character:FindFirstChildOfClass("Tool")
        if tool then
            return tool
        end
    end
    return nil
end

function api:get_tool_cache()
    local tool = api:get_tool()
    
    if not tool then
        ToolCache.instance = nil
        ToolCache.offset = nil
        ToolCache.handle = nil
        ToolCache.ammo = 0
        ToolCache.ignores_spawn = false
        ToolCache.gun = false
        ToolCache.shotgun = false
        ToolCache.max_ammo = 0
        ToolCache.automatic = false
        ToolCache.client = false
        return ToolCache
    end
    
    ToolCache.instance = tool
    
    local handle = tool:FindFirstChild("Handle")
    ToolCache.handle = handle
    
    local offset = nil
    if handle then
        if handle:FindFirstChild("Offset") then
            offset = handle.Offset.Value
        elseif tool:FindFirstChild("Offset") then
            offset = tool.Offset.Value
        else
            offset = CFrame.new(0, 0, -2)
        end
    end
    ToolCache.offset = offset or CFrame.new(0, 0, -2)
    
    local isGun = false
    local isShotgun = false
    local isAutomatic = false
    local ignoresSpawn = false
    local isClient = true
    
    if tool:FindFirstChild("IsGun") then
        isGun = tool.IsGun.Value
    elseif tool.Name:match("Gun") or tool.Name:match("Rifle") or tool.Name:match("Pistol") or tool.Name:match("Shotgun") then
        isGun = true
    end
    
    if tool:FindFirstChild("IsShotgun") then
        isShotgun = tool.IsShotgun.Value
    elseif tool.Name:match("Shotgun") then
        isShotgun = true
    end
    
    if tool:FindFirstChild("Automatic") then
        isAutomatic = tool.Automatic.Value
    elseif tool:FindFirstChild("IsAutomatic") then
        isAutomatic = tool.IsAutomatic.Value
    end
    
    if tool:FindFirstChild("IgnoresSpawn") then
        ignoresSpawn = tool.IgnoresSpawn.Value
    elseif tool:FindFirstChild("IgnoreSpawn") then
        ignoresSpawn = tool.IgnoreSpawn.Value
    end
    
    if tool:FindFirstChild("Client") then
        isClient = tool.Client.Value
    end
    
    ToolCache.gun = isGun
    ToolCache.shotgun = isShotgun
    ToolCache.automatic = isAutomatic
    ToolCache.ignores_spawn = ignoresSpawn
    ToolCache.client = isClient
    
    local ammo = 0
    local maxAmmo = 0
    
    if tool:FindFirstChild("Ammo") then
        ammo = tool.Ammo.Value
    elseif tool:FindFirstChild("CurrentAmmo") then
        ammo = tool.CurrentAmmo.Value
    elseif tool:FindFirstChild("Bullets") then
        ammo = tool.Bullets.Value
    end
    
    if tool:FindFirstChild("MaxAmmo") then
        maxAmmo = tool.MaxAmmo.Value
    elseif tool:FindFirstChild("MaxBullets") then
        maxAmmo = tool.MaxBullets.Value
    elseif tool:FindFirstChild("ClipSize") then
        maxAmmo = tool.ClipSize.Value
    end
    
    ToolCache.ammo = ammo
    ToolCache.max_ammo = maxAmmo
    
    return ToolCache
end

function api:get_data_cache(player)
    if not player or not player.Character then
        return nil
    end
    
    if not DataCache[player.UserId] then
        DataCache[player.UserId] = {
            Crew = "",
            Wanted = 0,
            Currency = 0,
            MuscleInformation = 0,
            Level = 0,
            XP = 0,
            Health = 100,
            Armor = 0,
            Kills = 0,
            Deaths = 0
        }
    end
    
    local char = player.Character
    local cache = DataCache[player.UserId]
    
    if char:FindFirstChild("Crew") then
        cache.Crew = char.Crew.Value or ""
    elseif char:FindFirstChild("Team") then
        cache.Crew = char.Team.Value or ""
    elseif char:FindFirstChild("Gang") then
        cache.Crew = char.Gang.Value or ""
    end
    
    if char:FindFirstChild("Wanted") then
        cache.Wanted = char.Wanted.Value or 0
    elseif char:FindFirstChild("WantedLevel") then
        cache.Wanted = char.WantedLevel.Value or 0
    elseif char:FindFirstChild("Bounty") then
        cache.Wanted = char.Bounty.Value or 0
    end
    
    if char:FindFirstChild("Currency") then
        cache.Currency = char.Currency.Value or 0
    elseif char:FindFirstChild("Money") then
        cache.Currency = char.Money.Value or 0
    elseif char:FindFirstChild("Cash") then
        cache.Currency = char.Cash.Value or 0
    end
    
    if char:FindFirstChild("Muscle") then
        cache.MuscleInformation = char.Muscle.Value or 0
    elseif char:FindFirstChild("Size") then
        cache.MuscleInformation = char.Size.Value or 0
    elseif char:FindFirstChild("BodySize") then
        cache.MuscleInformation = char.BodySize.Value or 0
    end
    
    if char:FindFirstChild("Level") then
        cache.Level = char.Level.Value or 0
    end
    
    if char:FindFirstChild("XP") then
        cache.XP = char.XP.Value or 0
    end
    
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        cache.Health = humanoid.Health or 100
    end
    
    if char:FindFirstChild("Armor") then
        cache.Armor = char.Armor.Value or 0
    end
    
    if char:FindFirstChild("Kills") then
        cache.Kills = char.Kills.Value or 0
    end
    
    if char:FindFirstChild("Deaths") then
        cache.Deaths = char.Deaths.Value or 0
    end
    
    return cache
end

function api:get_status_cache(player)
    if not player or not player.Character then
        return nil
    end
    
    if not StatusCache[player.UserId] then
        StatusCache[player.UserId] = {
            MousePos = Vector3.new(0, 0, 0),
            FireArmor = 0,
            Armor = 0,
            Dead = false,
            Defense = 0,
            Anonymous = false,
            Reload = false,
            K_O = false,
            SDeath = false,
            Grabbed = false,
            Crouching = false,
            Sprinting = false,
            Swimming = false,
            Flying = false,
            Ragdoll = false,
            Stunned = false,
            InVehicle = false
        }
    end
    
    local char = player.Character
    local cache = StatusCache[player.UserId]
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    
    if char:FindFirstChild("MousePos") then
        cache.MousePos = char.MousePos.Value or Vector3.new(0, 0, 0)
    elseif char:FindFirstChild("CursorPosition") then
        cache.MousePos = char.CursorPosition.Value or Vector3.new(0, 0, 0)
    end
    
    if char:FindFirstChild("FireArmor") then
        cache.FireArmor = char.FireArmor.Value or 0
    elseif char:FindFirstChild("FireResistance") then
        cache.FireArmor = char.FireResistance.Value or 0
    end
    
    if char:FindFirstChild("Armor") then
        cache.Armor = char.Armor.Value or 0
    elseif char:FindFirstChild("BodyArmor") then
        cache.Armor = char.BodyArmor.Value or 0
    end
    
    if char:FindFirstChild("Defense") then
        cache.Defense = char.Defense.Value or 0
    end
    
    if char:FindFirstChild("Anonymous") then
        cache.Anonymous = char.Anonymous.Value or false
    elseif char:FindFirstChild("Masked") then
        cache.Anonymous = char.Masked.Value or false
    elseif char:FindFirstChild("WearingMask") then
        cache.Anonymous = char.WearingMask.Value or false
    end
    
    if char:FindFirstChild("Reload") then
        cache.Reload = char.Reload.Value or false
    elseif char:FindFirstChild("IsReloading") then
        cache.Reload = char.IsReloading.Value or false
    end
    
    if char:FindFirstChild("KO") then
        cache.K_O = char.KO.Value or false
    elseif char:FindFirstChild("Knocked") then
        cache.K_O = char.Knocked.Value or false
    elseif char:FindFirstChild("IsKO") then
        cache.K_O = char.IsKO.Value or false
    end
    
    if char:FindFirstChild("SDeath") then
        cache.SDeath = char.SDeath.Value or false
    elseif char:FindFirstChild("Stomped") then
        cache.SDeath = char.Stomped.Value or false
    end
    
    if char:FindFirstChild("Grabbed") then
        cache.Grabbed = char.Grabbed.Value or false
    elseif char:FindFirstChild("Carried") then
        cache.Grabbed = char.Carried.Value or false
    end
    
    cache.Dead = false
    if humanoid then
        cache.Dead = humanoid.Health <= 0
        cache.Defense = humanoid.MaxHealth or cache.Defense
        
        cache.Crouching = humanoid:GetState() == Enum.HumanoidStateType.Seated and char:FindFirstChild("LowerTorso") and char.LowerTorso.Position.Y < char.HumanoidRootPart.Position.Y - 2
        cache.Sprinting = humanoid:GetState() == Enum.HumanoidStateType.Sprinting
        cache.Swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
        cache.Flying = humanoid:GetState() == Enum.HumanoidStateType.Flying
        cache.Ragdoll = humanoid:GetState() == Enum.HumanoidStateType.Physics
        cache.Stunned = humanoid:GetState() == Enum.HumanoidStateType.Stunned
    end
    
    cache.InVehicle = false
    if char:FindFirstChild("Seat") then
        cache.InVehicle = true
    end
    
    return cache
end

function api:get_character_cache(player)
    if not player or not player.Character then
        return nil
    end
    
    if not CharacterCache[player.UserId] then
        CharacterCache[player.UserId] = {
            Character = nil,
            Humanoid = nil,
            HumanoidRootPart = nil,
            Head = nil,
            Torso = nil,
            UpperTorso = nil,
            LowerTorso = nil,
            LeftArm = nil,
            RightArm = nil,
            LeftLeg = nil,
            RightLeg = nil,
            LeftHand = nil,
            RightHand = nil,
            LeftFoot = nil,
            RightFoot = nil,
            Neck = nil,
            RootPart = nil,
            Chest = nil,
            Spine = nil,
            Pelvis = nil,
            Hat = nil,
            Glasses = nil,
            Tool = nil,
            Handle = nil,
            Helmet = nil,
            Vest = nil,
            Seat = nil,
            BodyParts = {}
        }
    end
    
    local char = player.Character
    local cache = CharacterCache[player.UserId]
    
    cache.Character = char
    cache.Humanoid = char:FindFirstChildOfClass("Humanoid")
    cache.HumanoidRootPart = char:FindFirstChild("HumanoidRootPart")
    cache.RootPart = cache.HumanoidRootPart
    
    cache.Torso = char:FindFirstChild("Torso")
    cache.UpperTorso = char:FindFirstChild("UpperTorso")
    cache.LowerTorso = char:FindFirstChild("LowerTorso")
    cache.Chest = char:FindFirstChild("Chest")
    cache.Spine = char:FindFirstChild("Spine")
    cache.Pelvis = char:FindFirstChild("Pelvis")
    
    cache.Head = char:FindFirstChild("Head")
    cache.Neck = char:FindFirstChild("Neck")
    
    cache.LeftArm = char:FindFirstChild("LeftArm")
    cache.RightArm = char:FindFirstChild("RightArm")
    cache.LeftHand = char:FindFirstChild("LeftHand")
    cache.RightHand = char:FindFirstChild("RightHand")
    
    cache.LeftLeg = char:FindFirstChild("LeftLeg")
    cache.RightLeg = char:FindFirstChild("RightLeg")
    cache.LeftFoot = char:FindFirstChild("LeftFoot")
    cache.RightFoot = char:FindFirstChild("RightFoot")
    
    cache.Hat = char:FindFirstChild("Hat")
    cache.Glasses = char:FindFirstChild("Glasses")
    
    local tool = char:FindFirstChildOfClass("Tool")
    cache.Tool = tool
    if tool then
        cache.Handle = tool:FindFirstChild("Handle")
    end
    
    cache.Helmet = char:FindFirstChild("Helmet")
    cache.Vest = char:FindFirstChild("Vest")
    cache.Seat = char:FindFirstChild("Seat")
    
    local bodyParts = {}
    local partNames = {"Head", "Torso", "UpperTorso", "LowerTorso", "Chest", "Spine", "Pelvis", 
                       "LeftArm", "RightArm", "LeftHand", "RightHand", 
                       "LeftLeg", "RightLeg", "LeftFoot", "RightFoot",
                       "Neck", "HumanoidRootPart", "RootPart"}
    
    for _, name in ipairs(partNames) do
        local part = char:FindFirstChild(name)
        if part then
            bodyParts[name] = part
        end
    end
    
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("BasePart") and not bodyParts[child.Name] then
            bodyParts[child.Name] = child
        end
    end
    
    cache.BodyParts = bodyParts
    
    return cache
end

function api:is_crew(player, target)
    if not player or not target then
        return false
    end
    
    if player == target then
        return true
    end
    
    local cacheKey = player.UserId .. "_" .. target.UserId
    if CrewCache[cacheKey] ~= nil then
        return CrewCache[cacheKey]
    end
    
    local isCrew = false
    
    local playerData = api:get_data_cache(player)
    local targetData = api:get_data_cache(target)
    
    if playerData and targetData then
        if playerData.Crew and targetData.Crew and playerData.Crew ~= "" and targetData.Crew ~= "" then
            if playerData.Crew == targetData.Crew then
                isCrew = true
            end
        end
    end
    
    if not isCrew then
        local playerChar = player.Character
        local targetChar = target.Character
        
        if playerChar and targetChar then
            local playerTeam = playerChar:FindFirstChild("Team")
            local targetTeam = targetChar:FindFirstChild("Team")
            if playerTeam and targetTeam and playerTeam.Value == targetTeam.Value then
                isCrew = true
            end
            
            if not isCrew then
                local playerTeamAttr = playerChar:GetAttribute("Team")
                local targetTeamAttr = targetChar:GetAttribute("Team")
                if playerTeamAttr and targetTeamAttr and playerTeamAttr == targetTeamAttr then
                    isCrew = true
                end
            end
            
            if not isCrew then
                local playerColor = playerChar:GetAttribute("Color")
                local targetColor = targetChar:GetAttribute("Color")
                if playerColor and targetColor and playerColor == targetColor then
                    isCrew = true
                end
            end
        end
    end
    
    if not isCrew then
        local playerTeam = player.Team
        local targetTeam = target.Team
        if playerTeam and targetTeam and playerTeam == targetTeam then
            isCrew = true
        end
    end
    
    CrewCache[cacheKey] = isCrew
    
    return isCrew
end

function api:get_target_cache(type)
    if type ~= "ragebot" and type ~= "aimbot" and type ~= "silent" then
        error("Invalid type. Must be 'ragebot', 'aimbot', or 'silent'", 2)
        return nil
    end
    return TargetCaches[type]
end

function api:get_target(type)
    if type ~= "ragebot" and type ~= "aimbot" and type ~= "silent" then
        error("Invalid type. Must be 'ragebot', 'aimbot', or 'silent'", 2)
        return nil
    end
    
    local cache = TargetCaches[type]
    if cache and cache.player then
        return cache.player
    end
    return nil
end

-- Update target caches
local function updateTargetCaches()
    local function findTarget()
        local closest, dist = nil, math.huge
        local closestPlayer = nil
        
        for _, v in pairs(P:GetPlayers()) do
            if v ~= LP and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                if api:is_crew(LP, v) then
                    continue
                end
                
                local hrp = v.Character.HumanoidRootPart
                local magnitude = (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.HumanoidRootPart.Position - hrp.Position).Magnitude or math.huge
                if magnitude < dist then
                    dist = magnitude
                    closest = hrp
                    closestPlayer = v
                end
            end
        end
        
        return closest, closestPlayer
    end
    
    local ragebotPart, ragebotPlayer = findTarget()
    TargetCaches.ragebot.part = ragebotPart
    TargetCaches.ragebot.player = ragebotPlayer
    
    TargetCaches.aimbot.part = ragebotPart
    TargetCaches.aimbot.player = ragebotPlayer
    
    TargetCaches.silent.part = ragebotPart
    TargetCaches.silent.player = ragebotPlayer
end

-- Update tool cache periodically
local function updateToolCache()
    local tool = api:get_tool()
    
    if not tool then
        ToolCache.instance = nil
        ToolCache.offset = nil
        ToolCache.handle = nil
        ToolCache.ammo = 0
        ToolCache.ignores_spawn = false
        ToolCache.gun = false
        ToolCache.shotgun = false
        ToolCache.max_ammo = 0
        ToolCache.automatic = false
        ToolCache.client = false
        return
    end
    
    if tool:FindFirstChild("Ammo") then
        ToolCache.ammo = tool.Ammo.Value
    elseif tool:FindFirstChild("CurrentAmmo") then
        ToolCache.ammo = tool.CurrentAmmo.Value
    elseif tool:FindFirstChild("Bullets") then
        ToolCache.ammo = tool.Bullets.Value
    end
    
    local handle = tool:FindFirstChild("Handle")
    if handle then
        ToolCache.handle = handle
    end
end

-- Update data cache for all players
local function updateDataCaches()
    for _, player in pairs(P:GetPlayers()) do
        if player.Character then
            api:get_data_cache(player)
        end
    end
end

-- Update status cache for all players
local function updateStatusCaches()
    for _, player in pairs(P:GetPlayers()) do
        if player.Character then
            api:get_status_cache(player)
        end
    end
end

-- Update character cache for all players
local function updateCharacterCaches()
    for _, player in pairs(P:GetPlayers()) do
        if player.Character then
            api:get_character_cache(player)
        end
    end
end

-- Process desync callbacks
local function processDesyncCallbacks()
    if not RagebotState.IsDesyncing then
        return nil
    end
    
    if RagebotState.ProcessingDesync then
        return nil
    end
    
    RagebotState.ProcessingDesync = true
    
    for _, callback in ipairs(RagebotState.DesyncCallbacks[1]) do
        local success, result = pcall(callback)
        if success then
            if result == nil then
                -- Continue
            elseif type(result) == "CFrame" then
                RagebotState.CurrentDesyncCFrame = result
                RagebotState.ProcessingDesync = false
                return result
            else
                warn("Invalid return type from desync callback: " .. type(result))
            end
        else
            warn("Error in desync callback: " .. tostring(success))
        end
    end
    
    for _, callback in ipairs(RagebotState.DesyncCallbacks[2]) do
        local success, result = pcall(callback)
        if success then
            if result == nil then
                -- Continue
            elseif type(result) == "CFrame" then
                RagebotState.CurrentDesyncCFrame = result
                RagebotState.ProcessingDesync = false
                return result
            else
                warn("Invalid return type from desync callback: " .. type(result))
            end
        else
            warn("Error in desync callback: " .. tostring(success))
        end
    end
    
    RagebotState.CurrentDesyncCFrame = nil
    RagebotState.ProcessingDesync = false
    return nil
end

-- Function to get current fake position
local function getFakePosition()
    if not RagebotState.FakeEnabled then
        return nil
    end
    if RagebotState.FakeCFrame then
        if RagebotState.FakeRefresh then
            local randomX = math.random(-10000, 10000)
            local randomZ = math.random(-10000, 10000)
            local randomY = math.random(0, 1000)
            RagebotState.CurrentFakePosition = CFrame.new(randomX, randomY, randomZ)
            RagebotState.FakeRefresh = false
        end
        return RagebotState.FakeCFrame
    end
    if not RagebotState.CurrentFakePosition then
        local randomX = math.random(-10000, 10000)
        local randomZ = math.random(-10000, 10000)
        local randomY = math.random(0, 1000)
        RagebotState.CurrentFakePosition = CFrame.new(randomX, randomY, randomZ)
    end
    return RagebotState.CurrentFakePosition
end

-- Rest of the UI code remains the same...
-- [All the UI code for boxes, labels, and updates goes here]
-- (I'll skip the full UI code for brevity since the main fix is initializing api)

-- Example usage
task.spawn(function()
    while task.wait() do
        local cache = api:get_character_cache(LP)
        if cache then
            local head = cache.Head
            local hrp = cache.HumanoidRootPart
            if head and hrp then
                print("Head position:", head.Position)
                print("HRP position:", hrp.Position)
            end
        end
    end
end)

task.spawn(function()
    while task.wait() do
        for _, v in pairs(P:GetPlayers()) do
            if v ~= LP then
                local isCrew = api:is_crew(LP, v)
                if isCrew then
                    print(v.Name, "is in your crew!")
                end
            end
        end
    end
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("AimPrivate")
SaveManager:SetFolder("AimPrivate/Main")
SaveManager:BuildConfigSection(Tabs["settings"])
ThemeManager:ApplyToTab(Tabs["settings"])
SaveManager:LoadAutoloadConfig()