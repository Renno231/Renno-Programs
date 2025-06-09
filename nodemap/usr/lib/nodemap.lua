-- Node Map Management System with integrated A* pathfinding
local nodemap = {}
local currentMapName = "Untitled"
local serial = require"serialization"
local filesystem = require"filesystem"
local mapDirectory = "/usr/nodemap/"
-- Internal storage
local nodes = {}  -- Stores all nodes
local connections = {} -- Stores node connections by name
local nodesByName = {} -- Look up nodes by name
local INF = 1/0
local cachedPaths = nil

-- Helper function to get node by name or object
local function resolveNode(node)
    if type(node) == "string" then
        return nodesByName[node]
    end
    return node
end

-- Helper function to get node name
local function getNodeName(node)
    if type(node) == "string" then
        return node
    end
    return node.name
end

-- Distance calculation functions
local function dist(x1, y1, z1, x2, y2, z2)
    return math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2) + math.pow(z2 - z1, 2))
end

local function dist_between(nodeA, nodeB)
    return dist(nodeA.x, nodeA.y, nodeA.z, nodeB.x, nodeB.y, nodeB.z)
end

-- A* pathfinding helper functions
local function lowest_f_score(set, f_score)
    local lowest, bestNode = INF, nil
    for _, node in ipairs(set) do
        local score = f_score[node]
        if score < lowest then
            lowest, bestNode = score, node
        end
    end
    return bestNode
end

local function not_in(set, theNode)
    for _, node in ipairs(set) do
        if node == theNode then return false end
    end
    return true
end

local function remove_node_from_set(set, theNode)
    for i, node in ipairs(set) do
        if node == theNode then
            set[i] = set[#set]
            set[#set] = nil
            break
        end
    end
end

local function unwind_path(flat_path, map, current_node)
    if map[current_node] then
        table.insert(flat_path, 1, map[current_node])
        return unwind_path(flat_path, map, map[current_node])
    else
        return flat_path
    end
end

-- Get connected neighbors of a node
local function get_neighbors(node)
    local name = getNodeName(node)
    local neighbors = {}
    if connections[name] then
        for _, neighbor in pairs(connections[name]) do
            table.insert(neighbors, neighbor)
        end
    end
    return neighbors
end

-- A* pathfinding implementation
local function a_star(start, goal)
    local closedset = {}
    local openset = {start}
    local came_from = {}
    
    local g_score, f_score = {}, {}
    g_score[start] = 0
    f_score[start] = g_score[start] + dist_between(start, goal)
    
    while #openset > 0 do
        local current = lowest_f_score(openset, f_score)
        if current == goal then
            local path = unwind_path({}, came_from, goal)
            table.insert(path, goal)
            return path
        end
        
        remove_node_from_set(openset, current)
        table.insert(closedset, current)
        
        local neighbors = get_neighbors(current)
        for _, neighbor in ipairs(neighbors) do
            if not_in(closedset, neighbor) then
                local tentative_g_score = g_score[current] + dist_between(current, neighbor)
                
                if not_in(openset, neighbor) or tentative_g_score < g_score[neighbor] then
                    came_from[neighbor] = current
                    g_score[neighbor] = tentative_g_score
                    f_score[neighbor] = g_score[neighbor] + dist_between(neighbor, goal)
                    if not_in(openset, neighbor) then
                        table.insert(openset, neighbor)
                    end
                end
            end
        end
    end
    return nil -- no valid path
end

-- Public API functions
function nodemap.createNode(name, x, y, z)
    assert(name and type(name) == "string", "Node must have a name")
    assert(not nodesByName[name], "Node name must be unique")
    
    local node = {
        x = x or 0,
        y = y or 0,
        z = z or 0,
        name = name
    }
    
    table.insert(nodes, node)
    nodesByName[name] = node
    connections[name] = {}
    return node
end
-- might need to add returns to this and not use assert
function nodemap.link(nodeA, nodeB)
    local nameA = getNodeName(nodeA)
    local nameB = getNodeName(nodeB)
    
    assert(nodesByName[nameA] and nodesByName[nameB], "Both nodes must exist")
    assert(nameA ~= nameB, "Cannot link node to itself")
    
    connections[nameA][nameB] = nodesByName[nameB]
    connections[nameB][nameA] = nodesByName[nameA]
end

function nodemap.sever(nodeA, nodeB)
    local nameA = getNodeName(nodeA)
    local nameB = getNodeName(nodeB)
    
    if connections[nameA] then
        connections[nameA][nameB] = nil
    end
    if connections[nameB] then
        connections[nameB][nameA] = nil
    end
end

function nodemap.getNodes()
    return nodes
end

function nodemap.getNeighbors(node)
    local name = getNodeName(node)
    assert(nodesByName[name], "Node must exist")
    
    local neighbors = {}
    if connections[name] then
        for _, neighbor in pairs(connections[name]) do
            table.insert(neighbors, neighbor)
        end
    end
    return neighbors
end

function nodemap.removeNode(node)
    local name = getNodeName(node)
    if not nodesByName[name] then return end
    
    -- Remove all connections to this node
    for otherName, _ in pairs(connections[name]) do
        connections[otherName][name] = nil
    end
    
    -- Remove the node's connections and lookup entries
    connections[name] = nil
    nodesByName[name] = nil
    
    -- Remove from nodes table
    for i, node in ipairs(nodes) do
        if node.name == name then
            table.remove(nodes, i)
            break
        end
    end
end

-- Find path between two nodes
function nodemap.findPath(startNode, goalNode)
    local start = resolveNode(startNode)
    local goal = resolveNode(goalNode)
    
    if not (start and goal) then
        return false, (start == nil and ("%s not found"):format(startNode)) or (goalNode == nil and ("%s not found"):format(startNode)) or ("nodes %s and %s not found"):format(startNode, goalNode)
    end
    
    if not cachedPaths then cachedPaths = {} end
    if not cachedPaths[start] then
        cachedPaths[start] = {}
    elseif cachedPaths[start][goal] then
        return cachedPaths[start][goal]
    end
    
    local path = a_star(start, goal)
    if path and not cachedPaths[start][goal] then
        cachedPaths[start][goal] = path
    end
    
    return path
end

--- Removes redundant nodes from a path.
-- A node is considered redundant if it lies on a straight line between its predecessor
-- and successor in the path. The start and end nodes are never removed.
-- @param path An array of node objects, as returned by findPath.
-- @param exclusionList (optional) An array of node objects or node names to prevent from being removed.
-- @return A new path table with redundant nodes removed.
function nodemap.simplifyPath(path, exclusionList)
    -- If the path is too short to have any redundant nodes, return it as is.
    if not path or #path < 3 then
        return path
    end

    -- Create a lookup set for the exclusion list for faster checking.
    local exclusionSet = {}
    if exclusionList then
        for _, item in ipairs(exclusionList) do
            -- The getNodeName helper correctly handles both node objects and strings.
            local name = getNodeName(item)
            if name then
                exclusionSet[name] = true
            end
        end
    end

    local simplifiedPath = {}
    -- The first node of the path is always kept.
    table.insert(simplifiedPath, path[1])

    -- The 'anchor' is the last node that was confirmed to be part of the simplified path.
    -- All subsequent collinearity checks are performed from this anchor.
    local anchorNode = path[1]
    local epsilon = 1e-6 -- A small tolerance for floating-point comparisons.

    -- Iterate through the path, checking each intermediate node for redundancy.
    for i = 2, #path - 1 do
        local currentNode = path[i]
        local nextNode = path[i+1]
        
        -- A node is kept if it's on the exclusion list, or if it breaks the straight line
        -- from the current anchor point.
        local isExcluded = exclusionSet[currentNode.name]
        
        -- Check for collinearity: dist(anchor, next) should equal dist(anchor, current) + dist(current, next)
        local d_direct = dist_between(anchorNode, nextNode)
        local d_indirect = dist_between(anchorNode, currentNode) + dist_between(currentNode, nextNode)
        local isCollinear = math.abs(d_direct - d_indirect) < epsilon

        if isExcluded or not isCollinear then
            -- This node must be kept. Add it to our new path.
            table.insert(simplifiedPath, currentNode)
            -- This node now becomes the new anchor for future checks.
            anchorNode = currentNode
        end
        -- If the node is collinear and not excluded, we do nothing. It is skipped,
        -- and the anchor remains the same, effectively extending the line segment being tested.
    end

    -- The last node of the path is always kept.
    table.insert(simplifiedPath, path[#path])

    return simplifiedPath
end

function nodemap.clearPathCache()
    cachedPaths = nil
end

function nodemap.distance(x1, y1, z1, x2, y2, z2)
    return dist(x1, y1, z1, x2, y2, z2)
end

function nodemap.visualize()
    local lines = {}
    table.insert(lines, "Node Map Visualization:")
    
    -- Add nodes
    table.insert(lines, "\nNodes:")
    for _, node in ipairs(nodes) do
        table.insert(lines, string.format("  %s at (%d, %d, %d)", 
            node.name, node.x, node.y, node.z))
    end
    
    -- Add connections
    table.insert(lines, "\nConnections:")
    local added = {}  -- Track which connections we've already listed
    for nodeName, nodeConns in pairs(connections) do
        for neighborName, _ in pairs(nodeConns) do
            -- Create a unique key for this connection
            local key = nodeName < neighborName and 
                       nodeName .. "-" .. neighborName or 
                       neighborName .. "-" .. nodeName
            
            if not added[key] then
                table.insert(lines, string.format("  %s <-> %s", 
                    nodeName, neighborName))
                added[key] = true
            end
        end
    end
    
    return table.concat(lines, "\n")
end

function nodemap.findClosestNode(x, y, z, maxDistance)
    if #nodes == 0 then
        return nil, "No nodes in map"
    end
    
    local closest = nil
    local closestDist = math.huge
    
    for _, node in ipairs(nodes) do
        local distance = dist(x, y, z, node.x, node.y, node.z)
        if distance < closestDist then
            closestDist = distance
            closest = node
        end
    end
    
    -- If maxDistance is specified, check if the closest node is within range
    if maxDistance and closestDist > maxDistance then
        return nil, string.format("Closest node '%s' is too far (%.1f units, max %.1f)", 
            closest.name, closestDist, maxDistance)
    end
    
    return closest, closestDist
end

-- Optional: Helper function that also returns all nodes within a certain range
function nodemap.findNodesInRange(x, y, z, maxDistance)
    local nodesInRange = {}
    
    for _, node in ipairs(nodes) do
        local distance = dist(x, y, z, node.x, node.y, node.z)
        if distance <= maxDistance then
            table.insert(nodesInRange, {
                node = node,
                distance = distance
            })
        end
    end
    
    -- Sort by distance
    table.sort(nodesInRange, function(a, b)
        return a.distance < b.distance
    end)
    
    return nodesInRange
end

-- Serialization support
function nodemap.save(mapName)
    if not filesystem.exists(mapDirectory) then
        filesystem.makeDirectory(mapDirectory)
    end
    mapName = mapName or ("Untitled "..tostring(#filesystem.list(mapDirectory)()+1))
    local fileName = mapDirectory..(mapName)..".lua"
    local file, err = io.open(fileName, "w")
    if not file then return false, err end

    -- Create serializable version of connections (using names instead of references)
    local serializableConnections = {}
    for nodeName, nodeConns in pairs(connections) do
        serializableConnections[nodeName] = {}
        for connectedNodeName, _ in pairs(nodeConns) do
            serializableConnections[nodeName][connectedNodeName] = true
        end
    end

    local mapData = string.format("return %s, %s",
        serial.serialize(nodes),
        serial.serialize(serializableConnections)
    )
    file:write(mapData)
    file:close()
    currentMapName = mapName
    return true, "successfully saved map to ".. fileName
end

function nodemap.load(mapName)
    local fileName = mapDirectory..(mapName)..".lua"
    if not filesystem.exists(fileName) then
        return false, "Map file does not exist: " .. fileName
    end

    local file, err = io.open(fileName)
    if not file then 
        return false, "Could not open map file: " .. err 
    end

    local content = file:read(math.huge)
    file:close()

    -- Load the map data
    local fn, err = load("return " .. content)
    if not fn then
        return false, "Could not parse map data: " .. err
    end

    local success, loadedNodes, loadedConnections = pcall(fn)
    if not success then
        return false, "Could not load map data: " .. loadedNodes -- error message
    end

    -- Clear existing data
    nodes = loadedNodes
    
    -- Rebuild nodesByName lookup table
    nodesByName = {}
    for _, node in ipairs(nodes) do
        nodesByName[node.name] = node
    end
    
    -- Rebuild connections table with proper object references
    connections = {}
    for nodeName, nodeConns in pairs(loadedConnections) do
        connections[nodeName] = {}
        for connectedNodeName, _ in pairs(nodeConns) do
            connections[nodeName][connectedNodeName] = nodesByName[connectedNodeName]
        end
    end
    
    -- Clear path cache since we have a new map
    nodemap.clearPathCache()
    currentMapName = mapName
    return true, "Successfully loaded map from " .. fileName
end

function nodemap.listMaps()
    if not filesystem.exists(mapDirectory) then
        return {}
    end

    local maps = {}
    for file in filesystem.list(mapDirectory) do
        -- Remove .lua extension if it exists
        local mapName = file:match("(.+)%.lua$")
        if mapName then
            table.insert(maps, mapName)
        end
    end
    
    table.sort(maps) -- Sort alphabetically
    return maps
end

-- Helper function to check if a map exists
function nodemap.exists(mapName)
    local fileName = mapDirectory..(mapName)..".lua"
    return filesystem.exists(fileName)
end

function nodemap.getNodeCoordinates(node)
    if type(node) == "string" then
        local node = resolveNode(node)
        if node then
            return node.x, node.y, node.z
        end
    elseif type(node) == "table" then
        return node.x, node.y, node.z
    end
end

nodemap.getNodeByName = resolveNode

function nodemap.getMapName()
    return currentMapName
end

return nodemap