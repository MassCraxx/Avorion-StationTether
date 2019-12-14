-- Station Tether by MassCraxx 
-- v1.1
package.path = package.path .. ";data/scripts/systems/?.lua"
package.path = package.path .. ";data/scripts/lib/?.lua"
require ("basesystem")
require ("utility")
require ("randomext")

-- optimization so that energy requirement doesn't have to be read every frame
FixedEnergyRequirement = true

local debug = false
local makeTetheredInvincible = false
local slowShipsDown = false
local maxTetherSpeed = 30 --> 300m/s

Unique = true

---------------------
-- Client handling --
---------------------
local tetheredEntities = {}
local problemID
local tetheredID

local isRendering

if onClient() then
-- is not called when making permanent in slot, init therefore happens on actual tether
function onInstalled(seed, rarity, permanent)
    -- handle error while installing
    local active, msg = canTether(permanent, Entity())
    if not debug and not active then 
        if not problemID then
            problemID = Entity().id
            addShipProblem("Station Tether Problem", problemID, msg, "data/textures/icons/hazard-sign.png", ColorRGB(1, 0, 0))
        end
    end
end

function onUninstalled(seed, rarity, permanent)
    -- is not called when making permanent in slot, therefore let server call it
end

-- called onUninstalled from server
function releaseTether(active)
    if active then
        if isRendering then
            Player():unregisterCallback("onPreRenderHud", "onPreRenderHud")
            Player():unregisterCallback("onShipChanged", "onShipChanged")
            isRendering = false
        end
        
    else
        if problemID then
            removeShipProblem("Station Tether Problem", problemID)
            problemID = nil
        end
    end
end
callable(nil,"releaseTether")

-- handle tether status icon on ship change
function onShipChanged(playerIndex, craftId) 
    -- remove old status icon, not sure if necessary
    if tetheredID then
        removeShipProblem("Station Tether", tetheredID)
        tetheredID = nil
    end
    
    -- if new craft already tethered, add status icon
    if tetheredEntities[craftId.value] then
        tetheredID = craftId
        addShipProblem("Station Tether", tetheredID, "Tethered by station "..Entity().name, "data/textures/icons/alliance.png", ColorRGB(0, 1, 1))
    end
end

function onEntityTethered(entityID)
    if not isRendering then
        -- initialize callbacks for tether rendering handling
        -- done here since onInstalled may not be called if turning upgrade permanent in slot (and calling it onInstall on server doesnt work)
        Player():registerCallback("onPreRenderHud", "onPreRenderHud")
        Player():registerCallback("onShipChanged", "onShipChanged")

        isRendering = true
    end

    local entity = Sector():getEntity(entityID)
    if valid(entity) then
        --Create table entry and laser if there is none yet
        if tetheredEntities[entityID.value] == nil then
            local newLaser = Sector():createLaser(entity.translationf, Entity().translationf, ColorRGB(0,0,1), 1.0)
            newLaser.collision = false
            newLaser.animationSpeed = 1
            newLaser.innerColor = ColorRGB(0,1,0)
            --newLaser.width = entity.radius/20

            tetheredEntities[entityID.value] = {id = entityID, entity = entity, laser = newLaser}
        end
    else
        print("Tethered entity not found!")
    end
    
    -- if tethered entity is own craft, add status icon
    if entityID == Player().craft.id and tetheredID == nil then
        tetheredID = entityID
        addShipProblem("Station Tether", tetheredID, "Tethered by station "..Entity().name..". Ship ", "data/textures/icons/alliance.png", ColorRGB(0, 1, 1))
    end
end
callable(nil,"onEntityTethered")

function onEntityUntethered(entityID)
    local entry = tetheredEntities[entityID.value];
    if entry then
        Sector():removeLaser(entry.laser)
        tetheredEntities[entityID.value] = nil
    else
        -- Entry was already removed by cleanup onPreRenderHud whenever entity goes invalid, sever callback comes late 
        --print("Could not remove laser - none found for untethered entity!")
    end

    -- if untethered is own ship, remove status icon
    if entityID == tetheredID then
        removeShipProblem("Station Tether", entityID)
        tetheredID = nil
    end
end
callable(nil,"onEntityUntethered")

function onPreRenderHud()
    for i, value in pairs(tetheredEntities) do
        local entity = value.entity

        if not valid(entity) then
            -- entity invalid, untether
            onEntityUntethered(value.id)
        else
            -- glow
            local size = entity.radius + 10
            --local size = 20
            Sector():createGlow(entity.translationf, size, ColorRGB(0,0,1))

            -- update laser position
            local laser = value.laser
            if laser then
                laser.from = entity.translationf
                laser.to = Entity().translationf
            end
        end
    end
end

-- slow down too fast ships every update if set
function getUpdateInterval()
    if slowShipsDown then
        return 0.5
    else
        --return nil
    end
end

local stoppingFactor = 1
function update()
    -- if tether should slow ships down, check if player is tethered
    if slowShipsDown and tetheredEntities[Player().craft.id.value] then
        -- if player is faster than the limit, slow down every tick
        if not isInSpeedLimit(Player().craft, 100) then
            -- speed ^ (1 - 0.05x)
            stoppingFactor = stoppingFactor - 0.05
            Velocity(Player().craft.id).velocity =  Velocity(Player().craft.id).velocity * stoppingFactor
            print("Slowing down ship at "..speed.."m/s")
        else
            -- else reset stopping factor
            if stoppingFactor < 1 then
                stoppingFactor = 1
            end
        end
    end
end
end

---------------------
-- Server handling --
---------------------
local level
local range = -1
local isPermanent

local tetheredShips = {}
local active = false

if onServer() then
function onInstalled(seed, rarity, permanent)
    isPermanent = permanent
    level, range = getBonuses(seed, rarity, permanent)
    initTether()
end

function initTether()
    -- check if allowed to use
    local canTether, status = canTether(isPermanent, Entity())
    if canTether then
        active = true;

        Sector():registerCallback("onPlayerEntered", "onPlayerEntered")

        -- needed to make entity vulnerable again
        if makeTetheredInvincible then
            Sector():registerCallback("onPlayerLeft", "onPlayerLeft")
        end
    end
    print(status)
end

function onUninstalled(seed, rarity, permanent)
    releaseTether("Tether uninstalled. Was active "..tostring(active))
end

function releaseTether(msg)
    print(msg)
    broadcastInvokeClientFunction("releaseTether", active)

    if active then
        active = false

        for entityID, entity in pairs(tetheredShips) do
            untetherEntity(Uuid(entityID))
        end
        if makeTetheredInvincible then
            Sector():unregisterCallback("onPlayerLeft", "onPlayerLeft")
        end
    end
    tetheredShips = {}
end

function tetherEntity(entity)
    if not valid(entity) then
        print("Attempt to tether invalid entity")
        return
    end

    local name = entity.typename.." "..(entity.name or "")
    tetheredShips[entity.id.value] = {id = entity.id, name = name, entity = entity}
    entity.invincible = makeTetheredInvincible
    if entity.invincible then
        print("Made "..name.." invincible.")
    else
        print("Tethered ".. name)
    end

    broadcastInvokeClientFunction("onEntityTethered", entity.id)
end

function untetherEntity(entityID)
    local entity = tetheredShips[entityID.value].entity
    if makeTetheredInvincible and valid(entity) then
        entity.invincible = false
        print("Made "..tetheredShips[entityID.value].name.." vincible.")
    else
        print("Untethered "..tetheredShips[entityID.value].name)
    end
    tetheredShips[entityID.value] = nil
    broadcastInvokeClientFunction("onEntityUntethered", entityID)
end

-- make sure new clients render existing tethers
function onPlayerEntered(playerIndex)
    for entityIDValue, value in pairs(tetheredShips) do
        invokeClientFunction(Player(playerIndex), "onEntityTethered", value.id)
    end
end

-- make sure player wont stay invincible
function onPlayerLeft(playerIndex)
    local player = Player(playerIndex)
    if player then
        local craft = player.craft

        if tetheredShips[craft.id.value] then
            if craft.invincible then
                craft.invincible = false
            end
            print("Tethered player left sector. Untethering "..craft.name)
            untetherEntity(craft.id)
        end
    else
        print("Error: Nil Player left!")
    end
end

-- in makeTetheredInvincible mode, checks for new/left entities are not time critical
-- otherwise, the tick rate decides how often server checks for hp loss and restores it.
function getUpdateInterval()
    if makeTetheredInvincible then
        return 1
    else
        return 0.25
    end
end

function updateServer(timePassed)

    -- check if entity can still tether
    local canTether, msg = canTether(isPermanent, Entity())
    if active and not canTether then
        releaseTether(msg)
        return
    elseif not active and canTether then
        initTether()
    end

    if active then
        local sphere = Entity():getBoundingSphere()
        sphere.radius = sphere.radius + range
        
        local entities = {Sector():getEntitiesByLocation(sphere)}

        -- check who arrived
        local nearbyTetherableEntities = {}
        for _, entity in pairs(entities) do
            if canBeTethered(entity) then
                if tetheredShips[entity.id.value] == nil then
                    tetherEntity(entity)
                end

                -- if invincibility mode is active, set tethered entities to full hp
                if makeTetheredInvincible and entity.durability ~= entity.maxDurability then
                    entity.durability = entity.maxDurability
                elseif not makeTetheredInvincible then
                    -- if tethered entity hp has been lowered, set to last known hp
                    if tetheredShips[entity.id.value].durability and tetheredShips[entity.id.value].durability > entity.durability then
                        entity.durability = tetheredShips[entity.id.value].durability
                    elseif tetheredShips[entity.id.value].durability ~= entity.durability then
                        tetheredShips[entity.id.value].durability = entity.durability
                    end
                end

                nearbyTetherableEntities[entity.id.value] = true
            end
        end

        -- check who left
        for entityIDValue, value in pairs(tetheredShips) do
            if not nearbyTetherableEntities[entityIDValue] then
                untetherEntity(value.id)
            end
        end
    end
end
end

---------------------
-------  Util  ------
---------------------

function canTether(permanent, entity)
    local msg = "Tether is not active on "..entity.name.."!"
    if EnergySystem(entity.id).consumableEnergy == 0 then
        msg = msg.." Insufficient energy."
        return false, msg
    --elseif not entity.isStation then
        --msg = msg.." Only works on stations."
    --elseif not permanent then
       -- msg = msg.." Needs to be installed permanently."
    else
        return true, "Tether is active on "..entity.name
    end

    if debug then
        return true, "Tether is active in debug mode on "..entity.name
    end

    return false, msg

    --return debug or (isPermanent and Entity().isStation)
end

function canBeTethered(entity)
    -- only ships and drones
    if Entity().id ~= entity.id and entity.type == EntityType.Ship or entity.type == EntityType.Drone then
        -- alliance ships or player in same alliance
        if(entity.factionIndex == Entity().factionIndex) or 
        (entity.playerOwned and Player(entity.factionIndex).allianceIndex == Entity().factionIndex) then
            return isInSpeedLimit(entity, maxTetherSpeed)
        end
    end

    return false
end

function isInSpeedLimit(entity, maxSpeed)
    if not maxSpeed or maxSpeed < 0 then
        return true
    end
    
    local speed = length(Velocity(entity.id).velocity)
    return speed <= maxSpeed
end

-- Deprecated
function getErrorMsg(permanent, isStation)
    local msg = "Tether is not active!"
    if not isStation then
        msg = msg.." Only works on stations."
    elseif not permanent then
        msg = msg.." Needs to installed permanently."
    end
    return msg
end

---------------------
--  Item handling  --
---------------------
function getBonuses(seed, rarity, permanent)
    math.randomseed(seed)

    local highlightRange = math.random() * 50
    if rarity.value >= RarityType.Rare then
        highlightRange = 50 + math.random() * 50
    end

    if rarity.value >= RarityType.Exceptional then
        highlightRange = 100 + math.random() * 100
    end

    if rarity.value >= RarityType.Exotic then
        highlightRange = 200 + math.random() * 150
    end

    if rarity.value > RarityType.Exotic then
        highlightRange = 300 + math.random() * 200
    end

    return rarity.value, highlightRange, permanent
end

function getName(seed, rarity)
    local level, range = getBonuses(seed, rarity)
    local name = "Station Tether"
    if range > 450 then
        name = name.." of Doom"
    end
    return name
end

function getIcon(seed, rarity)
    return "data/textures/icons/alliance.png"
end

function getEnergy(seed, rarity, permanent)
    local level, range = getBonuses(seed, rarity)

    return (range^3) * 320 + 10^10
end

function getPrice(seed, rarity)
    local level, range = getBonuses(seed, rarity)
    range = math.min(range, 1000);

    local price = range * 50 + (rarity.value + 1) * 7500;

    return (price * 2.5 ^ rarity.value) * 2
end

function getTooltipLines(seed, rarity, permanent)
    local texts = {}

    local level, range = getBonuses(seed, rarity)

    if range and range > 0 then
        local rangeText = "Sector"%_t
        if range < math.huge then
            rangeText = string.format("%g", round((range / 100), 2))
        end

        table.insert(texts, {ltext = "Tether Range"%_t, rtext = rangeText, icon = "data/textures/icons/rss.png"})
    end

    if not permanent then
        return {}, texts
    else
        return texts, texts
    end
end

function getDescriptionLines(seed, rarity, permanent)
   return
   {
       {ltext = "When permanently installed on a station, tethers"%_t, rtext = "", icon = ""},
       {ltext = "nearby alliance ships to shield their hull damage."%_t, rtext = "", icon = ""}
   }
end