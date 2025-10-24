--[[
    Weapon Finder - Murder Mystery 2 Inventory Scanner
    
    Usage:
    getgenv().WeaponFinderConfig = {
        TargetWeapon = "Nik's Scythe",  -- Weapon to search for
        AutoServerHop = true,            -- Enable auto server hopping
        ScanInterval = 5,                -- Seconds between scans
        Debug = false                    -- Show debug messages
    }
    
    Then execute this script!
]]

-- Configuration with defaults
getgenv().WeaponFinderConfig = getgenv().WeaponFinderConfig or {}
local config = {
    TargetWeapon = getgenv().WeaponFinderConfig.TargetWeapon or "Nik's Scythe",
    AutoServerHop = getgenv().WeaponFinderConfig.AutoServerHop ~= false,
    ScanInterval = getgenv().WeaponFinderConfig.ScanInterval or 5,
    Debug = getgenv().WeaponFinderConfig.Debug or false
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- State
local isSearching = true
local foundPlayer = nil
local foundWeapon = nil

-- Utility: Debug print
local function debugPrint(...)
    if config.Debug then
        print("[WeaponFinder Debug]", ...)
    end
end

-- Utility: Clean weapon name (remove _K_Year, _G_Year, etc.)
local function cleanWeaponName(name)
    if not name then return "" end
    name = tostring(name)
    -- Remove _K_Year, _G_Year and any similar patterns
    name = name:gsub("_[KG]_Year", "")
    name = name:gsub("_K_Year", "")
    name = name:gsub("_G_Year", "")
    return name
end

-- Utility: Compare weapon names (case-insensitive, cleaned)
local function weaponMatches(weapon1, weapon2)
    local clean1 = cleanWeaponName(weapon1):lower():gsub("%s+", "")
    local clean2 = cleanWeaponName(weapon2):lower():gsub("%s+", "")
    return clean1 == clean2
end

-- GUI: Create notification
local function createNotification(playerName, weaponName)
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Remove existing notification
    local existing = playerGui:FindFirstChild("WeaponFinderNotification")
    if existing then existing:Destroy() end
    
    -- Create ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "WeaponFinderNotification"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    
    -- Create frame
    local frame = Instance.new("Frame")
    frame.Name = "NotificationFrame"
    frame.Size = UDim2.new(0, 400, 0, 200)
    frame.Position = UDim2.new(0.5, -200, 0.5, -100)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    -- Corner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame
    
    -- Shadow/Stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 255, 0)
    stroke.Thickness = 3
    stroke.Parent = frame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 40)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "🎯 WEAPON FOUND!"
    title.TextColor3 = Color3.fromRGB(0, 255, 0)
    title.TextSize = 24
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    -- Player info
    local playerLabel = Instance.new("TextLabel")
    playerLabel.Name = "PlayerLabel"
    playerLabel.Size = UDim2.new(1, -20, 0, 30)
    playerLabel.Position = UDim2.new(0, 10, 0, 60)
    playerLabel.BackgroundTransparency = 1
    playerLabel.Text = "Player: " .. playerName
    playerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    playerLabel.TextSize = 18
    playerLabel.Font = Enum.Font.Gotham
    playerLabel.TextXAlignment = Enum.TextXAlignment.Left
    playerLabel.Parent = frame
    
    -- Weapon info
    local weaponLabel = Instance.new("TextLabel")
    weaponLabel.Name = "WeaponLabel"
    weaponLabel.Size = UDim2.new(1, -20, 0, 30)
    weaponLabel.Position = UDim2.new(0, 10, 0, 95)
    weaponLabel.BackgroundTransparency = 1
    weaponLabel.Text = "Weapon: " .. weaponName
    weaponLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    weaponLabel.TextSize = 18
    weaponLabel.Font = Enum.Font.GothamBold
    weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
    weaponLabel.Parent = frame
    
    -- OK Button
    local button = Instance.new("TextButton")
    button.Name = "OKButton"
    button.Size = UDim2.new(0, 120, 0, 40)
    button.Position = UDim2.new(0.5, -60, 1, -50)
    button.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    button.Text = "OK"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 20
    button.Font = Enum.Font.GothamBold
    button.Parent = frame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button
    
    -- Button click
    button.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)
    
    -- Hover effect
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    end)
    
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    end)
end

-- Server Hop Function
local function serverHop()
    if not config.AutoServerHop then return end
    
    print("[WeaponFinder] Server hopping...")
    
    local success, result = pcall(function()
        local servers = HttpService:JSONDecode(game:HttpGet(
            "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        ))
        
        if servers and servers.data then
            local currentJobId = game.JobId
            
            for _, server in ipairs(servers.data) do
                if server.id ~= currentJobId and server.playing < server.maxPlayers then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, Players.LocalPlayer)
                    return
                end
            end
        end
    end)
    
    if not success then
        warn("[WeaponFinder] Server hop failed:", result)
        wait(5)
        TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
    end
end

-- Scan player inventory
local function scanPlayer(plr)
    local getInventoryRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("GetFullInventory")
    
    local success, inventoryData = pcall(function()
        return getInventoryRemote:InvokeServer(plr.Name)
    end)
    
    if not success or not inventoryData then
        debugPrint("Failed to get inventory for", plr.Name)
        return false
    end
    
    -- Look for Weapons data
    local weaponsData = inventoryData.Weapons or inventoryData.weapons
    if not weaponsData then return false end
    
    -- Recursive scan function
    local function scanWeapons(data)
        if type(data) ~= "table" then return false end
        
        for key, value in pairs(data) do
            if type(value) == "table" then
                -- Check if this is a weapon entry
                local weaponName = value.Name or value.ItemName or key
                weaponName = cleanWeaponName(tostring(weaponName))
                
                debugPrint("Checking weapon:", weaponName, "against target:", config.TargetWeapon)
                
                if weaponMatches(weaponName, config.TargetWeapon) then
                    return true, weaponName
                end
                
                -- Recurse into nested tables
                local found, name = scanWeapons(value)
                if found then return true, name end
            elseif type(key) == "string" then
                local weaponName = cleanWeaponName(key)
                if weaponMatches(weaponName, config.TargetWeapon) then
                    return true, weaponName
                end
            end
        end
        
        return false
    end
    
    return scanWeapons(weaponsData)
end

-- Main scan loop
local function startScan()
    print("[WeaponFinder] Starting search for:", config.TargetWeapon)
    print("[WeaponFinder] Auto server hop:", config.AutoServerHop)
    
    while isSearching do
        local players = Players:GetPlayers()
        print(("[WeaponFinder] Scanning %d players..."):format(#players))
        
        for _, plr in ipairs(players) do
            if not isSearching then break end
            
            local found, weaponName = scanPlayer(plr)
            
            if found then
                isSearching = false
                foundPlayer = plr.Name
                foundWeapon = weaponName
                
                print(("[WeaponFinder] ✓ FOUND! Player: %s | Weapon: %s"):format(foundPlayer, foundWeapon))
                createNotification(foundPlayer, foundWeapon)
                return
            end
            
            wait(0.1) -- Small delay between players
        end
        
        if isSearching then
            print("[WeaponFinder] Weapon not found in this server. Waiting before next action...")
            wait(config.ScanInterval)
            
            if isSearching and config.AutoServerHop then
                serverHop()
                return -- Stop after initiating hop
            end
        end
    end
end

-- Start the scan
startScan()
