local loadedModels = {}
local createdBuildings = {}
local createdObjects = {}
local buildingsByName = {}

local function releaseSlice()
    for _, building in ipairs(createdBuildings) do
        if isElement(building) then
            destroyElement(building)
        end
    end
    createdBuildings = {}
    buildingsByName = {}

    for _, object in ipairs(createdObjects) do
        if isElement(object) then
            destroyElement(object)
        end
    end
    createdObjects = {}

    for _, model in ipairs(PERRY_SLICE_MODELS) do
        if model.id then
            engineFreeModel(model.id)
            model.id = nil
        end
        model.txdElement = nil
        model.colElement = nil
        model.dffElement = nil
    end
    loadedModels = {}
end

local function loadModel(model)
    model.id = engineRequestModel("object")
    if not model.id then
        return false, "engineRequestModel failed for " .. model.name
    end

    model.txdElement = engineLoadTXD("assets/" .. model.txd .. ".txd")
    model.colElement = engineLoadCOL("assets/" .. model.name .. ".col")
    model.dffElement = engineLoadDFF("assets/" .. model.name .. ".dff")
    if not model.txdElement or not model.colElement or not model.dffElement then
        return false, "TXD/COL/DFF load failed for " .. model.name
    end

    if not engineImportTXD(model.txdElement, model.id) then
        return false, "engineImportTXD failed for " .. model.name
    end
    if not engineReplaceCOL(model.colElement, model.id) then
        return false, "engineReplaceCOL failed for " .. model.name
    end
    if not engineReplaceModel(model.dffElement, model.id, model.alpha) then
        return false, "engineReplaceModel failed for " .. model.name
    end

    engineSetModelLODDistance(model.id, model.lodDistance)
    loadedModels[model.name] = model
    return true
end

local function failLoad(reason)
    outputChatBox("[Perry slice] ECHEC: " .. reason, 255, 80, 80)
    outputDebugString("[Perry slice] " .. reason, 1)
    triggerServerEvent("perrySliceClientReady", resourceRoot, false, reason)
    releaseSlice()
end

local function loadSlice()
    for _, model in ipairs(PERRY_SLICE_MODELS) do
        local ok, reason = loadModel(model)
        if not ok then
            failLoad(reason)
            return
        end
    end

    for _, placement in ipairs(PERRY_SLICE_PLACEMENTS) do
        local model = loadedModels[placement.model]
        local building = createBuilding(1337, placement.x, placement.y, placement.z, placement.rx, placement.ry, placement.rz)
        if not model or not building or not setElementModel(building, model.id) then
            failLoad("building creation failed for " .. placement.model)
            return
        end

        if placement.model:lower():find("^lod") then
            setElementCollisionsEnabled(building, false)
        end
        table.insert(createdBuildings, building)
        buildingsByName[placement.model] = building
    end

    for _, placement in ipairs(PERRY_SLICE_NATIVE_OBJECTS) do
        local modelID = engineGetModelIDFromName(placement.model)
        local object = modelID and createObject(modelID, placement.x, placement.y, placement.z, placement.rx, placement.ry, placement.rz)
        if not object then
            failLoad("stock object creation failed for " .. placement.model)
            return
        end
        table.insert(createdObjects, object)
    end

    for _, placement in ipairs(PERRY_SLICE_PLACEMENTS) do
        if placement.lodParent then
            local high = buildingsByName[placement.model]
            local low = buildingsByName[placement.lodParent]
            if high and low then
                setLowLODElement(high, low)
            end
        end
    end

    engineRestreamWorld()
    local details = ("custom=%d stock=%d models=%d full=%s"):format(
        #createdBuildings,
        #createdObjects,
        #PERRY_SLICE_MODELS,
        tostring(PERRY_SLICE_FULL)
    )
    outputChatBox("[Perry] Ile complete chargee a x=9000. /perrytest pour visiter.", 80, 255, 160)
    outputDebugString("[Perry slice] ready " .. details)
    triggerServerEvent("perrySliceClientReady", resourceRoot, true, details)
end

addEventHandler("onClientResourceStart", resourceRoot, loadSlice)
addEventHandler("onClientResourceStop", resourceRoot, releaseSlice)
