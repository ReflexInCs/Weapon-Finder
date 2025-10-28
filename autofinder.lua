--[[
    Weapon Finder - Murder Mystery 2 Inventory Scanner (Database Edition)
    
    Usage:
    getgenv().WeaponFinderConfig = {
        TargetWeaponID = "NikKnife",  -- Exact weapon ID to search for
        AutoServerHop = true,          -- Enable auto server hopping
        ScanInterval = 5,              -- Seconds between scans
        Debug = false                  -- Show debug messages
    }
    
    Then execute this script!
]]

-- Configuration with defaults
getgenv().WeaponFinderConfig = getgenv().WeaponFinderConfig or {}
local config = {
    TargetWeaponID = getgenv().WeaponFinderConfig.TargetWeaponID or "NikKnife",
    AutoServerHop = getgenv().WeaponFinderConfig.AutoServerHop ~= false,
    ScanInterval = getgenv().WeaponFinderConfig.ScanInterval or 5,
    Debug = getgenv().WeaponFinderConfig.Debug or false
}

-- Database URL (hardcoded)
local DATABASE_URL = "https://raw.githubusercontent.com/ReflexInCs/weapon-db/main/MM2_Complete_Weapons_Database.csv"

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- State
local isSearching = true
local foundPlayer = nil
local foundWeapon = nil
local weaponDatabase = {}

-- Utility: Debug print
local function debugPrint(...)
    if config.Debug then
        print("[WeaponFinder Debug]", ...)
    end
end

-- Parse CSV line (handles quoted values)
local function parseCSVLine(line)
    local fields = {}
    local fieldStart = 1
    local inQuotes = false
    
    for i = 1, #line do
        local char = line:sub(i, i)
        
        if char == '"' then
            inQuotes = not inQuotes
        elseif char == ',' and not inQuotes then
            local field = line:sub(fieldStart, i - 1)
            field = field:gsub('^"', ''):gsub('"$', ''):gsub('""', '"')
            table.insert(fields, field)
            fieldStart = i + 1
        end
    end
    
    -- Add last field
    local field = line:sub(fieldStart)
    field = field:gsub('^"', ''):gsub('"$', ''):gsub('""', '"')
    table.insert(fields, field)
    
    return fields
end

-- Load weapon database from URL
local function loadWeaponDatabase()
    print("[WeaponFinder] Loading weapon database...")
    
    local success, result = pcall(function()
        return game:HttpGet(DATABASE_URL)
    end)
    
    if not success or not result then
        warn("[WeaponFinder] Failed to load database from URL:", DATABASE_URL)
        return false
    end
    
    local lines = {}
    for line in result:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines < 2 then
        warn("[WeaponFinder] Database is empty or invalid")
        return false
    end
    
    -- Parse header (Type,Name,ID,Rarity,Year,Event,AssetID)
    local headers = parseCSVLine(lines[1])
    debugPrint("CSV Headers:", table.concat(headers, " | "))
    
    -- Parse data rows
    local count = 0
    for i = 2, #lines do
        local fields = parseCSVLine(lines[i])
        if #fields >= 3 then
            local weaponType = fields[1] or "Unknown"
            local weaponName = fields[2] or "Unknown"
            local weaponID = fields[3] or ""
            local rarity = fields[4] or "Unknown"
            local year = fields[5] or "N/A"
            local event = fields[6] or "N/A"
            local assetID = fields[7] or "N/A"
            
            if weaponID and weaponID ~= "" then
                weaponDatabase[weaponID] = {
                    id = weaponID,
                    name = weaponName,
                    type = weaponType,
                    rarity = rarity,
                    year = year,
                    event = event,
                    assetID = assetID
                }
                count = count + 1
                
                debugPrint("Loaded:", weaponID, "=>", weaponName, "(" .. rarity .. ")")
            end
        end
    end
    
    print(("[WeaponFinder] ✓ Loaded %d weapons from database"):format(count))
    return true
end

-- Get weapon info from database by exact ID
local function getWeaponInfo(weaponID)
    -- Try exact match first
    if weaponDatabase[weaponID] then
        return weaponDatabase[weaponID]
    end
    
    -- Return basic info if not in database
    return {
        id = weaponID,
        name = weaponID,
        type = "Unknown",
        rarity = "Unknown",
        year = "N/A",
        event = "N/A",
        assetID = "N/A"
    }
end

-- GUI: Create notification with database info
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
    
    -- Create frame
    local frame = Instance.new("Frame")
    frame.Name = "NotificationFrame"
    frame.Size = UDim2.new(0, 480, 0, 340)
    frame.Position = UDim2.new(0.5, -240, 0.5, -170)
    frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    -- Corner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 15)
    corner.Parent = frame
    
    -- Stroke color based on rarity
    local strokeColor
    local rarityLower = weaponInfo.rarity:lower()
    if rarityLower == "ancient" then
        strokeColor = Color3.fromRGB(255, 50, 50) -- Red
    elseif rarityLower == "godly" then
        strokeColor = Color3.fromRGB(255, 215, 0) -- Gold
    elseif rarityLower == "legendary" then
        strokeColor = Color3.fromRGB(255, 100, 255) -- Purple
    elseif rarityLower == "rare" then
        strokeColor = Color3.fromRGB(100, 150, 255) -- Blue
    elseif rarityLower == "uncommon" then
        strokeColor = Color3.fromRGB(100, 255, 100) -- Green
    elseif rarityLower == "unique" then
        strokeColor = Color3.fromRGB(255, 150, 50) -- Orange
    else
        strokeColor = Color3.fromRGB(200, 200, 200) -- Gray
    end
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = strokeColor
    stroke.Thickness = 3
    stroke.Parent = frame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -20, 0, 45)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "🎯 WEAPON FOUND!"
    title.TextColor3 = strokeColor
    title.TextSize = 26
    title.Font = Enum.Font.GothamBold
    title.Parent = frame
    
    -- Create scrolling frame for info
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "InfoScroll"
    scrollFrame.Size = UDim2.new(1, -20, 1, -120)
    scrollFrame.Position = UDim2.new(0, 10, 0, 60)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = frame
    
    -- Info labels
    local yPos = 0
    local function addLabel(icon, label, value, isHighlight)
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -10, 0, 28)
        textLabel.Position = UDim2.new(0, 5, 0, yPos)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = icon .. " " .. label .. ": " .. value
        textLabel.TextColor3 = isHighlight and Color3.fromRGB(255, 255, 100) or Color3.fromRGB(220, 220, 220)
        textLabel.TextSize = isHighlight and 17 or 15
        textLabel.Font = isHighlight and Enum.Font.GothamBold or Enum.Font.Gotham
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.TextWrapped = true
        textLabel.Parent = scrollFrame
        yPos = yPos + 28
    end
    
    addLabel("👤", "Player", playerName, false)
    addLabel("🔪", "Weapon Name", weaponInfo.name, true)
    addLabel("🆔", "Weapon ID", weaponInfo.id, true)
    addLabel("⚔️", "Type", weaponInfo.type, false)
    addLabel("💎", "Rarity", weaponInfo.rarity, true)
    addLabel("📅", "Year", weaponInfo.year, false)
    addLabel("🎉", "Event", weaponInfo.event, false)
    addLabel("🔢", "Asset ID", weaponInfo.assetID, false)
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, yPos)
    
    -- OK Button
    local button = Instance.new("TextButton")
    button.Name = "OKButton"
    button.Size = UDim2.new(0, 160, 0, 50)
    button.Position = UDim2.new(0.5, -80, 1, -60)
    button.BackgroundColor3 = strokeColor
    button.Text = "CLOSE"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 22
    button.Font = Enum.Font.GothamBold
    button.Parent = frame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = button
    
    -- Button click
    button.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)
    
    -- Hover effect
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.new(
            math.min(strokeColor.R + 0.2, 1),
            math.min(strokeColor.G + 0.2, 1),
            math.min(strokeColor.B + 0.2, 1)
        )
    end)
    
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = strokeColor
    end)
end

-- Server Hop Function with retry logic
local function serverHop()
    if not config.AutoServerHop then return end
    
    local maxRetries = 5
    local retryCount = 0
    
    while retryCount < maxRetries do
        retryCount = retryCount + 1
        print(("[WeaponFinder] Server hop attempt %d/%d..."):format(retryCount, maxRetries))
        
        -- Method 1: Try public servers API
        local success = pcall(function()
            local serversUrl = string.format(
                "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
                game.PlaceId
            )
            
            local response = game:HttpGetAsync(serversUrl)
            local servers = HttpService:JSONDecode(response)
            
            if servers and servers.data then
                local currentJobId = game.JobId
                local validServers = {}
                
                for _, server in ipairs(servers.data) do
                    if server.id ~= currentJobId and server.playing < server.maxPlayers - 1 then
                        table.insert(validServers, server)
                    end
                end
                
                if #validServers > 0 then
                    local randomServer = validServers[math.random(1, #validServers)]
                    print("[WeaponFinder] Found server with " .. randomServer.playing .. "/" .. randomServer.maxPlayers .. " players")
                    print("[WeaponFinder] Teleporting...")
                    
                    TeleportService:TeleportToPlaceInstance(
                        game.PlaceId,
                        randomServer.id,
                        Players.LocalPlayer
                    )
                    
                    wait(5) -- Wait to see if teleport succeeds
                    return true
                end
            end
        end)
        
        if success then
            return true
        end
        
        warn(("[WeaponFinder] Server hop method 1 failed on attempt %d"):format(retryCount))
        
        -- Method 2: Simple teleport
        if retryCount >= 3 then
            print("[WeaponFinder] Trying simple teleport method...")
            local teleportSuccess = pcall(function()
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end)
            
            if teleportSuccess then
                wait(5)
                return true
            end
        end
        
        -- Wait before retry
        if retryCount < maxRetries then
            local waitTime = 3 * retryCount
            print(("[WeaponFinder] Waiting %d seconds before retry..."):format(waitTime))
            wait(waitTime)
        end
    end
    
    warn("[WeaponFinder] All server hop attempts failed after " .. maxRetries .. " tries")
    print("[WeaponFinder] Restarting scan in current server...")
    wait(10)
end

-- Scan player inventory for exact weapon ID
local function scanPlayer(plr)
    local getInventoryRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("GetFullInventory")
    
    local success, inventoryData = pcall(function()
        return getInventoryRemote:InvokeServer(plr.Name)
    end)
    
    if not success or not inventoryData then
        debugPrint("Failed to get inventory for", plr.Name)
        return false
    end
    
    local weaponsData = inventoryData.Weapons or inventoryData.weapons
    if not weaponsData then return false end
    
    -- Recursive scan function for exact ID match
    local function scanWeapons(data, depth)
        if type(data) ~= "table" then return false end
        depth = depth or 0
        
        for key, value in pairs(data) do
            -- Check if this key is the exact weapon ID
            local keyStr = tostring(key)
            debugPrint(string.rep("  ", depth) .. "Checking key:", keyStr)
            
            if keyStr == config.TargetWeaponID then
                debugPrint("✓ Found exact match (key):", keyStr)
                return true, keyStr
            end
            
            -- Check value fields
            if type(value) == "table" then
                local weaponName = value.Name or value.ItemName or value.name or value.itemname
                if weaponName then
                    local weaponNameStr = tostring(weaponName)
                    debugPrint(string.rep("  ", depth) .. "Checking value:", weaponNameStr)
                    
                    if weaponNameStr == config.TargetWeaponID then
                        debugPrint("✓ Found exact match (value):", weaponNameStr)
                        return true, weaponNameStr
                    end
                end
                
                -- Recurse
                local found, id = scanWeapons(value, depth + 1)
                if found then return true, id end
            elseif type(value) == "string" then
                debugPrint(string.rep("  ", depth) .. "Checking string value:", value)
                if value == config.TargetWeaponID then
                    debugPrint("✓ Found exact match (string):", value)
                    return true, value
                end
            end
        end
        
        return false
    end
    
    return scanWeapons(weaponsData)
end

-- Main scan loop
local function startScan()
    print("[WeaponFinder] ==============================================")
    print("[WeaponFinder] Starting search for weapon ID:", config.TargetWeaponID)
    print("[WeaponFinder] Auto server hop:", config.AutoServerHop)
    print("[WeaponFinder] ==============================================")
    
    while isSearching do
        local players = Players:GetPlayers()
        print(("[WeaponFinder] Scanning %d players..."):format(#players))
        
        for _, plr in ipairs(players) do
            if not isSearching then break end
            
            debugPrint("Scanning player:", plr.Name)
            local found, weaponID = scanPlayer(plr)
            
            if found then
                isSearching = false
                foundPlayer = plr.Name
                local weaponInfo = getWeaponInfo(weaponID)
                foundWeapon = weaponInfo
                
                print("[WeaponFinder] ==============================================")
                print("[WeaponFinder] ✓✓✓ WEAPON FOUND! ✓✓✓")
                print("[WeaponFinder] Player:", foundPlayer)
                print("[WeaponFinder] Weapon ID:", weaponInfo.id)
                print("[WeaponFinder] Weapon Name:", weaponInfo.name)
                print("[WeaponFinder] Type:", weaponInfo.type)
                print("[WeaponFinder] Rarity:", weaponInfo.rarity)
                print("[WeaponFinder] Year:", weaponInfo.year)
                print("[WeaponFinder] Event:", weaponInfo.event)
                print("[WeaponFinder] Asset ID:", weaponInfo.assetID)
                print("[WeaponFinder] ==============================================")
                
                createNotification(foundPlayer, weaponInfo)
                return
            end
            
            wait(0.15)
        end
        
        if isSearching then
            print("[WeaponFinder] Weapon not found in this server.")
            
            if config.AutoServerHop then
                print("[WeaponFinder] Server hopping in 3 seconds...")
                wait(3)
                serverHop()
                -- If serverHop fails completely, it will wait and we continue scanning
                isSearching = true
            else
                print("[WeaponFinder] Waiting " .. config.ScanInterval .. " seconds before next scan...")
                wait(config.ScanInterval)
            end
        end
    end
end

-- Initialize and start
print("[WeaponFinder] Initializing...")
local dbLoaded = loadWeaponDatabase()

if not dbLoaded then
    warn("[WeaponFinder] Database failed to load, but continuing with basic functionality...")
end

wait(1)
startScan()
