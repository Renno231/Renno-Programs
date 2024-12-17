-- Test script for 3D Node Map with integrated pathfinding
local function run_tests()
    local map = require "nodemap"
    print("Creating nodes...")
    -- Main locations
    local town_square = map.createNode(0, 0, 0, "Town Square")
    local blacksmith = map.createNode(50, 0, 20, "Blacksmith")
    local inn = map.createNode(-30, 10, 0, "Inn")
    local market = map.createNode(20, 0, 40, "Market")

    -- Highland locations
    local temple = map.createNode(0, 100, -50, "Temple")
    local observatory = map.createNode(30, 120, -40, "Observatory")
    local mountain_pass = map.createNode(-20, 80, -60, "Mountain Pass")

    -- Lowland locations
    local docks = map.createNode(60, -20, 80, "Docks")
    local fishery = map.createNode(80, -15, 90, "Fishery")
    local warehouse = map.createNode(50, -10, 70, "Warehouse")

    -- Cave system
    local cave_entrance = map.createNode(-40, -30, 30, "Cave Entrance")
    local crystal_cavern = map.createNode(-60, -50, 40, "Crystal Cavern")
    local underground_lake = map.createNode(-50, -70, 50, "Underground Lake")

    print("\nCreating connections...")

    -- Town connections
    map.link(town_square, blacksmith)
    map.link(town_square, inn)
    map.link(town_square, market)
    map.link(market, blacksmith)

    -- Highland path connections
    map.link(town_square, temple)
    map.link(temple, observatory)
    map.link(temple, mountain_pass)
    map.link(mountain_pass, observatory)

    -- Lowland connections
    map.link(market, docks)
    map.link(docks, fishery)
    map.link(docks, warehouse)
    map.link(warehouse, market)
    map.link(fishery, warehouse)

    -- Cave system connections
    map.link(town_square, cave_entrance)
    map.link(cave_entrance, crystal_cavern)
    map.link(crystal_cavern, underground_lake)
    map.link(underground_lake, cave_entrance)  -- Creating a loop

    -- Print the map
    print("\nMap visualization:")
    print(map.visualize())

    -- Helper function to calculate distance between nodes
    local function getDistance(nodeA, nodeB)
        return map.distance(nodeA.x, nodeA.y, nodeA.z, nodeB.x, nodeB.y, nodeB.z)
    end

    -- Test paths with distance calculations
    local function testPath(start, goal)
        print(string.format("\nFinding path from %s to %s:", start, goal))
        local path = map.findPath(start, goal)
        
        if not path then
            print("No path found!")
            return
        end
        
        print("Path found:")
        local totalDistance = 0
        
        for i = 1, #path do
            local node = path[i]
            print(string.format("  %d. %s (%d, %d, %d)", 
                i, node.name, node.x, node.y, node.z))
            
            if i > 1 then
                local prevNode = path[i-1]
                local segmentDist = getDistance(prevNode, node)
                totalDistance = totalDistance + segmentDist
                print(string.format("     Distance from previous: %.1f units", segmentDist))
            end
        end
        
        print(string.format("\n  Total path distance: %.1f units", totalDistance))
        return path, totalDistance
    end

    -- Test various paths
    print("\nTesting pathfinding with distances...")

    testPath("Town Square", "Observatory")  -- Should find a path up through the temple
    testPath("Docks", "Crystal Cavern")     -- Should find a path through town and cave entrance
    testPath("Temple", "Fishery")           -- Should find a path down through market to docks
    testPath("Underground Lake", "Observatory")  -- Should find a long path through multiple areas

    -- Compare cached vs non-cached performance
    print("\nTesting path caching...")
    print("Finding path from Town Square to Observatory again (should be instant):")
    local start_time = os.clock()
    local path, dist = testPath("Town Square", "Observatory")
    print(string.format("Path found in %.6f seconds", os.clock() - start_time))

    print("\nClearing cache and finding path again:")
    map.clearPathCache()
    start_time = os.clock()
    path, dist = testPath("Town Square", "Observatory")
    print(string.format("Path found in %.6f seconds", os.clock() - start_time))

    -- Print connection distances for verification
    print("\nAll direct connections with distances:")
    local added = {}
    for _, node in ipairs(map.getNodes()) do
        local neighbors = map.getNeighbors(node)
        for _, neighbor in ipairs(neighbors) do
            local key = node.name < neighbor.name and 
                    node.name .. "-" .. neighbor.name or 
                    neighbor.name .. "-" .. node.name
            
            if not added[key] then
                local dist = getDistance(node, neighbor)
                print(string.format("%-20s <-> %-20s : %.1f units", 
                    node.name, neighbor.name, dist))
                added[key] = true
            end
        end
    end
end
-- Run the tests
local succ, err = xpcall(run_tests, debug.traceback)
if not succ then print(err) end