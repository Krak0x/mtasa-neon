local testElements = {}
local playerReturnStates = {}
local showroomSpinners = {}

local function remember(element, dimension)
    if not element then
        return nil
    end
    testElements[#testElements + 1] = element
    setElementInterior(element, MirrorFloorTest.interior)
    setElementDimension(element, dimension or MirrorFloorTest.dimension)
    local elementType = getElementType(element)
    if elementType == "object" or elementType == "vehicle" then
        setElementFrozen(element, true)
    end
    if elementType == "object" then
        setObjectBreakable(element, false)
    end
    return element
end

local function createPanel(dimension, x, y, z, rx, ry, rz, sx, sy, sz, collisions)
    local object = remember(createObject(MirrorFloorTest.panelModel, x, y, z, rx or 0, ry or 0, rz or 0), dimension)
    if not object then
        return nil
    end
    setObjectScale(object, sx or 1, sy or sx or 1, sz or sx or 1)
    setElementDoubleSided(object, true)
    if collisions == false then
        setElementCollisionsEnabled(object, false)
    end
    return object
end

local function buildPlatform()
    local test = MirrorFloorTest.custom
    for offsetY = -1, 1 do
        for offsetX = -1, 1 do
            remember(createObject(MirrorFloorTest.panelModel, test.x + offsetX * 10, test.y + offsetY * 10, test.floorZ - 1))
        end
    end

    local vehicle = remember(createVehicle(411, test.x + 6, test.y + 4, test.floorZ + 1, 0, 0, 145))
    if vehicle then
        setVehicleColor(vehicle, 255, 45, 60, 255, 45, 60)
    end

    local marker = remember(createMarker(test.x - 6, test.y + 5, test.floorZ + 0.1, "cylinder", 1.3, 60, 180, 255, 160))
    local pickup = remember(createPickup(test.x + 2, test.y - 6, test.floorZ + 0.5, 3, 1240))
    return marker and pickup
end

local function createShowroomVehicle(model, x, y, z, rotation, primary, secondary)
    local vehicle = remember(createVehicle(model, x, y, z, 0, 0, rotation), MirrorFloorTest.showroomDimension)
    if vehicle then
        setVehicleColor(vehicle, primary[1], primary[2], primary[3], secondary[1], secondary[2], secondary[3])
    end
    return vehicle
end

local function buildShowroom()
    local test = MirrorFloorTest.custom
    local dimension = MirrorFloorTest.showroomDimension

    -- Floor and four opaque walls keep the native black mirror-buffer clear
    -- from dominating the shot while leaving the reflected ceiling open.
    for offsetY = -1, 1 do
        for offsetX = -1, 1 do
            createPanel(dimension, test.x + offsetX * 10, test.y + offsetY * 10, test.floorZ - 1)
        end
    end
    for offset = -1, 1 do
        -- Stop the walls just below the mirror plane. Normal world geometry is
        -- rendered after GTA's full-screen mirror buffer, so a wall crossing
        -- the plane would incorrectly cover the reflected image above it.
        createPanel(dimension, test.x - 15, test.y + offset * 10, test.floorZ + 0.9, 0, 90, 0, 0.18, 1, 1)
        createPanel(dimension, test.x + 15, test.y + offset * 10, test.floorZ + 0.9, 0, 90, 0, 0.18, 1, 1)
        createPanel(dimension, test.x + offset * 10, test.y - 15, test.floorZ + 0.9, 90, 0, 0, 1, 0.18, 1)
        createPanel(dimension, test.x + offset * 10, test.y + 15, test.floorZ + 0.9, 90, 0, 0, 1, 0.18, 1)
    end

    -- A physical frame marks the otherwise invisible native reflection plane.
    local frame = MirrorFloorTest.showroom.frameHalfSize
    createPanel(dimension, test.x, test.y - frame, test.mirrorV + 0.02, 0, 0, 0, 2.3, 0.08, 0.08, false)
    createPanel(dimension, test.x, test.y + frame, test.mirrorV + 0.02, 0, 0, 0, 2.3, 0.08, 0.08, false)
    createPanel(dimension, test.x - frame, test.y, test.mirrorV + 0.02, 0, 0, 0, 0.08, 2.3, 0.08, false)
    createPanel(dimension, test.x + frame, test.y, test.mirrorV + 0.02, 0, 0, 0, 0.08, 2.3, 0.08, false)

    -- Symmetrical subjects make the reflected perspective immediately clear.
    createShowroomVehicle(411, test.x - 8, test.y - 5, test.floorZ + 1, 25, { 255, 35, 55 }, { 255, 35, 55 })
    createShowroomVehicle(415, test.x + 8, test.y - 5, test.floorZ + 1, 335, { 25, 175, 255 }, { 25, 175, 255 })
    createShowroomVehicle(522, test.x, test.y + 5, test.floorZ + 1, 180, { 230, 35, 255 }, { 255, 170, 20 })

    local pickups = {
        { -9, 5, 1240 },
        { 9, 5, 1242 },
        { -5, 9, 1247 },
        { 5, 9, 1274 },
    }
    for _, pickup in ipairs(pickups) do
        remember(createPickup(test.x + pickup[1], test.y + pickup[2], test.floorZ + 0.8, 3, pickup[3]), dimension)
    end

    -- Three locally animated blades form a reflected kinetic sculpture.
    for index = 1, 3 do
        local spinner = createPanel(dimension, test.x, test.y, test.floorZ + 1.15, index == 2 and 90 or 0, index == 3 and 90 or 0, (index - 1) * 60, 0.22, 0.22, 0.22, false)
        if spinner then
            showroomSpinners[#showroomSpinners + 1] = spinner
        end
    end
end

local function rememberPlayer(player)
    if playerReturnStates[player] then
        return
    end
    local x, y, z = getElementPosition(player)
    playerReturnStates[player] = {
        x = x,
        y = y,
        z = z,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
        frozen = isElementFrozen(player),
        mode = "custom",
    }
end

local function preparePlayer(player)
    if getPedOccupiedVehicle(player) then
        outputChatBox("[Mirror Floor] Leave your vehicle first.", player, 255, 120, 100)
        return false
    end
    rememberPlayer(player)
    setElementFrozen(player, false)
    return true
end

local function enterCustomFloor(player)
    if not preparePlayer(player) then
        return
    end
    local test = MirrorFloorTest.custom
    playerReturnStates[player].mode = "custom"
    setElementInterior(player, MirrorFloorTest.interior)
    setElementDimension(player, MirrorFloorTest.dimension)
    setElementPosition(player, test.x, test.y, test.floorZ + 1)
    setPedRotation(player, 180)
    triggerClientEvent(player, "mirrorFloorTestEntered", resourceRoot, "custom")
    outputChatBox(("[Mirror Floor] Custom floor: one zone, normal=(0,0,1), plane Z=%.2f."):format(test.mirrorV), player, 90, 220, 255)
end

local function enterShowroom(player)
    if not preparePlayer(player) then
        return
    end
    local showroom = MirrorFloorTest.showroom
    playerReturnStates[player].mode = "showroom"
    setElementInterior(player, MirrorFloorTest.interior)
    setElementDimension(player, MirrorFloorTest.showroomDimension)
    setElementPosition(player, showroom.spawnX, showroom.spawnY, showroom.spawnZ)
    setPedRotation(player, showroom.rotation)
    triggerClientEvent(player, "mirrorFloorTestEntered", resourceRoot, "showroom", showroomSpinners)
    outputChatBox(("[Mirror Floor] Showroom active: framed mirror plane at Z=%.2f."):format(MirrorFloorTest.custom.mirrorV), player, 255, 90, 220)
end

local function enterVanillaBarber(player)
    if not preparePlayer(player) then
        return
    end
    local test = MirrorFloorTest.vanillaBarber
    playerReturnStates[player].mode = "vanilla"
    setElementInterior(player, test.interior)
    setElementDimension(player, test.dimension)
    setElementPosition(player, test.x, test.y, test.z)
    setPedRotation(player, test.rotation)
    triggerClientEvent(player, "mirrorFloorTestEntered", resourceRoot, "vanilla")
    outputChatBox("[Mirror Floor] Stock GTA barbershop mirror control. Use /mirrorfloorinfo.", player, 255, 205, 90)
end

local function leaveTest(player, quiet)
    local state = playerReturnStates[player]
    if not state then
        if not quiet then
            outputChatBox("[Mirror Floor] You are not in the test.", player, 255, 160, 90)
        end
        return
    end
    setElementInterior(player, state.interior)
    setElementDimension(player, state.dimension)
    setElementPosition(player, state.x, state.y, state.z)
    setElementFrozen(player, state.frozen)
    playerReturnStates[player] = nil
    triggerClientEvent(player, "mirrorFloorTestLeft", resourceRoot)
    if not quiet then
        outputChatBox("[Mirror Floor] Returned to your previous position.", player, 90, 220, 255)
    end
end

addCommandHandler("mirrorfloor", enterCustomFloor)
addCommandHandler("mirrorfloor2", enterShowroom)
addCommandHandler("mirrorvanilla", enterVanillaBarber)
addCommandHandler("mirrorfloorleave", function(player) leaveTest(player, false) end)

addEventHandler("onPlayerQuit", root, function()
    playerReturnStates[source] = nil
end)

addEventHandler("onPlayerSpawn", root, function()
    local state = playerReturnStates[source]
    if state then
        local enterFunction = state.mode == "vanilla" and enterVanillaBarber or state.mode == "showroom" and enterShowroom or enterCustomFloor
        setTimer(enterFunction, 250, 1, source)
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    buildPlatform()
    buildShowroom()
    outputServerLog(("[cull-mirror-floor-test] Ready: %d elements, /mirrorfloor, /mirrorfloor2 and /mirrorvanilla."):format(#testElements))
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(playerReturnStates) do
        if isElement(player) then
            leaveTest(player, true)
        end
    end
end)
