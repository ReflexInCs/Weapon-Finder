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
    Category = getgenv().WeaponFinderConfig.Category or nil, -- e.g., "Godly", "Ancient", "Legendary", "Rare", "Uncommon", "Common"
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

-- Utility: Extract weapon info (name, type, year, category)
local function parseWeaponName(rawName, categoryPath)
    if not rawName then return nil end
    local name = tostring(rawName)
    
    local weaponType = "Unknown"
    local year = nil
    local cleanName = name
    local category = nil
    
    -- Extract category from path if provided (e.g., "Godly", "Ancient")
    if categoryPath then
        category = categoryPath
    end
    
    -- Check for weapon type (_K = Knife, _G = Gun)
    if name:match("_K_") or name:match("_K$") then
        weaponType = "Knife"
    elseif name:match("_G_") or name:match("_G$") then
        weaponType = "Gun"
    end
    
    -- Extract year if present (e.g., _K_2020, _G_2018)
    local yearMatch = name:match("_[KG]_(%d%d%d%d)")
    if yearMatch then
        year = yearMatch
    end
    
    -- Clean the name (remove _K, _G, years, etc.)
    cleanName = name:gsub("_[KG]_%d%d%d%d", "")  -- Remove _K_2020, _G_2018
    cleanName = cleanName:gsub("_[KG]_Year", "") -- Remove _K_Year, _G_Year
    cleanName = cleanName:gsub("_[KG]$", "")     -- Remove trailing _K or _G
    cleanName = cleanName:gsub("_", " ")         -- Replace underscores with spaces
    cleanName = cleanName:gsub("%s+", " ")       -- Clean multiple spaces
    cleanName = cleanName:match("^%s*(.-)%s*$")  -- Trim
    
    return {
        original = name,
        clean = cleanName,
        type = weaponType,
        year = year,
        category = category
    }
end

-- Utility: Compare weapon names (must contain full word)
local function weaponMatches(weapon1, weapon2)
    local parsed1 = parseWeaponName(weapon1)
    local parsed2 = parseWeaponName(weapon2)
    
    if not parsed1 or not parsed2 then return false end
    
    local clean1 = parsed1.clean:lower()
    local clean2 = parsed2.clean:lower()
    
    -- Exact match (ignoring spaces)
    if clean1:gsub("%s+", "") == clean2:gsub("%s+", "") then
        return true
    end
    
    -- Word boundary matching - the search term must be a complete word
    -- Pattern explanation: %f[%w] = word boundary at start, %f[%W] = word boundary at end
    local searchTerm = clean2:gsub("%s+", "") -- Remove spaces from search term
    local targetWords = clean1:gsub("%s+", "") -- Remove spaces from target
    
    -- Check if search term is contained as a complete sequence
    if targetWords:find(searchTerm, 1, true) then
        -- Verify it's not a partial match by checking boundaries
        local pattern = searchTerm:gsub("([^%w])", "%%%1") -- Escape special chars
        if clean1:lower():match("%f[%w]" .. pattern .. "%f[%W]") or 
           clean1:lower():match("^" .. pattern .. "%f[%W]") or
           clean1:lower():match("%f[%w]" .. pattern .. "$") or
           clean1:lower():match("^" .. pattern .. "$") then
            return true
        end
    end
    
    return false
end

-- GUI: Create notification
local function createNotification(playerName, weaponInfo)
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
    
    -- Create frame (taller to fit more info)
    local frame = Instance.new("Frame")
    frame.Name = "NotificationFrame"
    frame.Size = UDim2.new(0, 420, 0, 240)
    frame.Position = UDim2.new(0.5, -210, 0.5, -120)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    -- Corner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame
    
    -- Shadow/Stroke (color based on weapon type)
    local stroke = Instance.new("UIStroke")
    if weaponInfo.type == "Knife" then
        stroke.Color = Color3.fromRGB(255, 100, 100) -- Red for knives
    elseif weaponInfo.type == "Gun" then
        stroke.Color = Color3.fromRGB(100, 150, 255) -- Blue for guns
    else
        stroke.Color = Color3.fromRGB(0, 255, 0) -- Green for unknown
    end
    stroke.Thickness = 3
    stroke.Parent = frame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 40)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "🎯 WEAPON FOUND!"
    title.TextColor3 = stroke.Color
    title.TextSize = 24
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    -- Player info
    local playerLabel = Instance.new("TextLabel")
    playerLabel.Name = "PlayerLabel"
    playerLabel.Size = UDim2.new(1, -20, 0, 30)
    playerLabel.Position = UDim2.new(0, 10, 0, 55)
    playerLabel.BackgroundTransparency = 1
    playerLabel.Text = "👤 Player: " .. playerName
    playerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    playerLabel.TextSize = 16
    playerLabel.Font = Enum.Font.Gotham
    playerLabel.TextXAlignment = Enum.TextXAlignment.Left
    playerLabel.Parent = frame
    
    -- Weapon name
    local weaponLabel = Instance.new("TextLabel")
    weaponLabel.Name = "WeaponLabel"
    weaponLabel.Size = UDim2.new(1, -20, 0, 30)
    weaponLabel.Position = UDim2.new(0, 10, 0, 90)
    weaponLabel.BackgroundTransparency = 1
    weaponLabel.Text = "🔪 Weapon: " .. weaponInfo.clean
    weaponLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    weaponLabel.TextSize = 18
    weaponLabel.Font = Enum.Font.GothamBold
    weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
    weaponLabel.Parent = frame
    
    -- Weapon type
    local typeLabel = Instance.new("TextLabel")
    typeLabel.Name = "TypeLabel"
    typeLabel.Size = UDim2.new(1, -20, 0, 25)
    typeLabel.Position = UDim2.new(0, 10, 0, 125)
    typeLabel.BackgroundTransparency = 1
    
    local typeIcon = weaponInfo.type == "Knife" and "🔪" or (weaponInfo.type == "Gun" and "🔫" or "❓")
    typeLabel.Text = typeIcon .. " Type: " .. weaponInfo.type
    typeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    typeLabel.TextSize = 15
    typeLabel.Font = Enum.Font.Gotham
    typeLabel.TextXAlignment = Enum.TextXAlignment.Left
    typeLabel.Parent = frame
    
    -- Year info (if available)
    local yOffset = weaponInfo.year and 150 or 125
    if weaponInfo.year then
        local yearLabel = Instance.new("TextLabel")
        yearLabel.Name = "YearLabel"
        yearLabel.Size = UDim2.new(1, -20, 0, 25)
        yearLabel.Position = UDim2.new(0, 10, 0, 150)
        yearLabel.BackgroundTransparency = 1
        yearLabel.Text = "📅 Year: " .. weaponInfo.year
        yearLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        yearLabel.TextSize = 15
        yearLabel.Font = Enum.Font.Gotham
        yearLabel.TextXAlignment = Enum.TextXAlignment.Left
        yearLabel.Parent = frame
    end
    
    -- Category info (if available)
    if weaponInfo.category then
        local categoryLabel = Instance.new("TextLabel")
        categoryLabel.Name = "CategoryLabel"
        categoryLabel.Size = UDim2.new(1, -20, 0, 25)
        categoryLabel.Position = UDim2.new(0, 10, 0, yOffset)
        categoryLabel.BackgroundTransparency = 1
        
        local categoryIcon = "⭐"
        if weaponInfo.category:lower() == "godly" then categoryIcon = "✨"
        elseif weaponInfo.category:lower() == "ancient" then categoryIcon = "🏺"
        elseif weaponInfo.category:lower() == "legendary" then categoryIcon = "👑"
        elseif weaponInfo.category:lower() == "rare" then categoryIcon = "💎"
        end
        
        categoryLabel.Text = categoryIcon .. " Rarity: " .. weaponInfo.category
        categoryLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold color
        categoryLabel.TextSize = 15
        categoryLabel.Font = Enum.Font.GothamBold
        categoryLabel.TextXAlignment = Enum.TextXAlignment.Left
        categoryLabel.Parent = frame
        
        -- Adjust frame height if category exists
        frame.Size = UDim2.new(0, 420, 0, 265)
        frame.Position = UDim2.new(0.5, -210, 0.5, -132.5)
    end
    
    -- OK Button
    local button = Instance.new("TextButton")
    button.Name = "OKButton"
    button.Size = UDim2.new(0, 140, 0, 45)
    button.Position = UDim2.new(0.5, -70, 1, -55)
    button.BackgroundColor3 = stroke.Color
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
    local originalColor = stroke.Color
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.new(
            math.min(originalColor.R + 0.2, 1),
            math.min(originalColor.G + 0.2, 1),
            math.min(originalColor.B + 0.2, 1)
        )
    end)
    
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = originalColor
    end)
end

-- Server Hop Function (Fixed)
local function serverHop()
    if not config.AutoServerHop then return end
    
    print("[WeaponFinder] Initiating server hop...")
    
    local success, errorMsg = pcall(function()
        -- Method 1: Try public servers API
        local serversUrl = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
            game.PlaceId
        )
        
        local response = game:HttpGetAsync(serversUrl)
        local servers = HttpService:JSONDecode(response)
        
        if servers and servers.data then
            local currentJobId = game.JobId
            local validServers = {}
            
            -- Collect valid servers
            for _, server in ipairs(servers.data) do
                if server.id ~= currentJobId and server.playing < server.maxPlayers - 1 then
                    table.insert(validServers, server)
                end
            end
            
            if #validServers > 0 then
                -- Pick a random server
                local randomServer = validServers[math.random(1, #validServers)]
                print("[WeaponFinder] Found server with " .. randomServer.playing .. "/" .. randomServer.maxPlayers .. " players")
                print("[WeaponFinder] Teleporting...")
                
                TeleportService:TeleportToPlaceInstance(
                    game.PlaceId,
                    randomServer.id,
                    Players.LocalPlayer
                )
                return true
            end
        end
    end)
    
    if not success then
        warn("[WeaponFinder] Server hop method 1 failed:", errorMsg)
        
        -- Method 2: Simple rejoin
        print("[WeaponFinder] Attempting simple rejoin...")
        local rejoinSuccess = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Players.LocalPlayer)
            wait(1)
            -- Force rejoin by teleporting to place
            TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
        end)
        
        if not rejoinSuccess then
            warn("[WeaponFinder] All server hop methods failed. Retrying in 10 seconds...")
            wait(10)
            -- Final fallback
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end
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
    local function scanWeapons(data, currentCategory)
        if type(data) ~= "table" then return false end
        
        for key, value in pairs(data) do
            if type(value) == "table" then
                -- Check if this key is a category name (Godly, Ancient, etc.)
                local potentialCategory = tostring(key)
                local knownCategories = {"Godly", "Ancient", "Legendary", "Rare", "Uncommon", "Common", "Unique", "Vintage"}
                local isCategory = false
                
                for _, cat in ipairs(knownCategories) do
                    if potentialCategory:lower() == cat:lower() then
                        isCategory = true
                        currentCategory = cat
                        break
                    end
                end
                
                -- Check if this is a weapon entry
                local weaponName = value.Name or value.ItemName or (not isCategory and key or nil)
                
                if weaponName then
                    local weaponInfo = parseWeaponName(tostring(weaponName), currentCategory)
                    
                    if weaponInfo then
                        debugPrint("Checking weapon:", weaponInfo.clean, "(" .. weaponInfo.type .. ")", 
                                  weaponInfo.category and ("Rarity: " .. weaponInfo.category) or "", 
                                  "against target:", config.TargetWeapon)
                        
                        -- Check if weapon name matches
                        local nameMatch = weaponMatches(weaponInfo.original, config.TargetWeapon)
                        
                        -- Check if category matches (if specified)
                        local categoryMatch = true
                        if config.Category then
                            categoryMatch = weaponInfo.category and 
                                          weaponInfo.category:lower() == config.Category:lower()
                        end
                        
                        if nameMatch and categoryMatch then
                            return true, weaponInfo
                        end
                    end
                end
                
                -- Recurse into nested tables
                local found, info = scanWeapons(value, currentCategory)
                if found then return true, info end
            elseif type(key) == "string" then
                local weaponInfo = parseWeaponName(key, currentCategory)
                if weaponInfo then
                    local nameMatch = weaponMatches(weaponInfo.original, config.TargetWeapon)
                    local categoryMatch = true
                    if config.Category then
                        categoryMatch = weaponInfo.category and 
                                      weaponInfo.category:lower() == config.Category:lower()
                    end
                    
                    if nameMatch and categoryMatch then
                        return true, weaponInfo
                    end
                end
            end
        end
        
        return false
    end
    
    return scanWeapons(weaponsData, nil)
end

-- Main scan loop
local function startScan()
    print("[WeaponFinder] Starting search for:", config.TargetWeapon)
    if config.Category then
        print("[WeaponFinder] Category filter:", config.Category)
    end
    print("[WeaponFinder] Search mode: Full word matching")
    print("[WeaponFinder] Auto server hop:", config.AutoServerHop)
    
    while isSearching do
        local players = Players:GetPlayers()
        print(("[WeaponFinder] Scanning %d players..."):format(#players))
        
        for _, plr in ipairs(players) do
            if not isSearching then break end
            
            local found, weaponInfo = scanPlayer(plr)
            
            if found then
                isSearching = false
                foundPlayer = plr.Name
                foundWeapon = weaponInfo
                
                local detailsText = string.format(
                    "%s | Type: %s%s%s",
                    weaponInfo.clean,
                    weaponInfo.type,
                    weaponInfo.year and (" | Year: " .. weaponInfo.year) or "",
                    weaponInfo.category and (" | Rarity: " .. weaponInfo.category) or ""
                )
                
                print(("[WeaponFinder] ✓ FOUND! Player: %s | %s"):format(foundPlayer, detailsText))
                createNotification(foundPlayer, weaponInfo)
                return
            end
            
            wait(0.1) -- Small delay between players
        end
        
        if isSearching then
            print("[WeaponFinder] Weapon not found in this server.")
            
            if config.AutoServerHop then
                print("[WeaponFinder] Server hopping in 3 seconds...")
                wait(3)
                serverHop()
                return -- Stop after initiating hop
            else
                print("[WeaponFinder] Waiting " .. config.ScanInterval .. " seconds before next scan...")
                wait(config.ScanInterval)
            end
        end
    end
end

-- Start the scan
startScan()
