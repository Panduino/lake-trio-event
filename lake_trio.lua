return function(mod, engine)
  if mod.generation ~= 3 or type(engine) ~= "table" then return false end

  local Dex = require("src.core.game3.dex")
  local Objects = require("src.core.game3.objects")

  -- National Dex Gen 3 appends Gen IV after the engine's 64 reserved species
  -- slots. This is the same proven mapping used by the Kanto encounter module.
  local HO_OH, LUGIA, ARTICUNO = 250, 249, 144
  local UXIE, MESPRIT, AZELF = 480 + 64, 481 + 64, 482 + 64

  local EVENTS = {
    uxie = {
      species=UXIE, map="FR_SEAFOAM_ISLANDS_B4F",
      x=13, y=2, elevation=4, localId=123,
    },
    azelf = {
      species=AZELF, map="FR_VICTORY_ROAD_3F",
      x=12, y=8, elevation=3, localId=124,
    },
    mesprit = {
      species=MESPRIT, map="FR_HOENN_ROUTE120",
      x=20, y=23, elevation=1, localId=125,
    },
  }

  local actors = {}
  local busy = false

  local function session()
    return engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
  end

  local function state(s)
    s.modData = s.modData or {}
    s.modData.lake_trio_events = s.modData.lake_trio_events or {}
    return s.modData.lake_trio_events
  end

  local function seen(s, species)
    return s and s.dex and Dex.isSeen(s.dex, species) == true
  end

  local function caught(s, species)
    return s and s.dex and Dex.isCaught(s.dex, species) == true
  end

  local function birdsSeen(s)
    -- A caught Pokemon is also seen in the real dex, so isSeen implements
    -- the requested "seen OR caught" prerequisite without a parallel flag.
    return seen(s, HO_OH) and seen(s, LUGIA) and caught(s, ARTICUNO)
  end

  local function unlocked(name, s)
    if not birdsSeen(s) then return false end
    if name == "mesprit" then
      return caught(s, UXIE) and caught(s, AZELF)
    end
    return true
  end

  local function clearActor(name)
    local e = EVENTS[name]
    if Objects._byId and Objects._byId[e.localId] then
      Objects._byId[e.localId] = nil
      for i = #(Objects._order or {}), 1, -1 do
        if Objects._order[i] == e.localId then table.remove(Objects._order, i) end
      end
    end
    actors[name] = nil
  end

  local function clearAll()
    for name in pairs(EVENTS) do clearActor(name) end
  end

  -- Lake Trio are normal field EventObjects using Untamed Advanced's own
  -- serialized overworld sprite IDs, exactly like the Darkrai/Cresselia mod.
  if not Objects._lakeTrioIdleAnim then
    Objects._lakeTrioIdleAnim = true
    local rawUpdate = Objects.update
    Objects.update = function(game, ...)
      local result = rawUpdate(game, ...)
      for _, e in pairs(EVENTS) do
        local actor = Objects._byId and Objects._byId[e.localId]
        if actor and actor._lakeTrioSheet and actor._lakeTrioRow then
          actor._lakeTrioTick = ((actor._lakeTrioTick or 0) + 1) % 32
          local frame = actor._lakeTrioTick >= 20 and actor._lakeTrioTick < 28 and 1 or 0
          local gid = string.format("uadv:%d:%d:0:%d:0",
            actor._lakeTrioSheet, frame, actor._lakeTrioRow)
          actor.graphicsId, actor.sprite = gid, gid
        end
      end
      return result
    end
  end

  local function show(name)
    local e = EVENTS[name]
    local s = session()
    local st = s and state(s)
    local shouldShow = s and s.map == e.map and unlocked(name, s)
      and not caught(s, e.species) and not busy
      and st[name .. "AttemptedThisVisit"] ~= true

    if not shouldShow then clearActor(name); return end
    if actors[name] and Objects._byId and Objects._byId[e.localId] == actors[name] then return end
    clearActor(name)
    if not Objects._byId or not Objects._order then return end

    local personality = engine.random32 and engine.random32() or 0
    local atlasSpecies = engine.expansionSpecies(e.species, personality)
    if not atlasSpecies then return end
    local female = engine.femaleFor and engine.femaleFor(e.species, personality) or false
    local sheet, row = engine.Gfx.sheetFor(atlasSpecies, female, false)
    if not sheet then return end
    local gid = string.format("uadv:%d:0:0:%d:0", sheet, row)
    local elevation = e.elevation or (engine.elevationAt and engine.elevationAt(e.x, e.y)) or 3

    local actor = {
      active=true, localId=e.localId, originLocalId=e.localId,
      originMapId=s.map, cellX=e.x, cellY=e.y, px=e.x*16, py=e.y*16,
      homeX=e.x, homeY=e.y, targetX=e.x, targetY=e.y,
      facing="down", sprite=gid, graphicsId=gid,
      elevation=elevation, currentElevation=elevation,
      movementType=0x09, movement="STAY", range="DOWN",
      radius={x=0,y=0}, rangeX=0, rangeY=0,
      visible=true, hidden=false, invisible=false, frozen=true,
      passable=false, moving=false, progress=0, stepFrames=16,
      scriptBusy=false,
      _lakeTrioSheet=sheet, _lakeTrioRow=row, _lakeTrioTick=8,
      def={localId=e.localId,x=e.x,y=e.y,graphicsId=gid,
        movementType=0x09,facing="down"},
    }
    Objects._byId[e.localId] = actor
    Objects._order[#Objects._order + 1] = e.localId
    actors[name] = actor
  end

  local function trigger(name)
    local e, actor = EVENTS[name], actors[name]
    if not actor or not actor.active or busy then return false end
    local s = session()
    if not s or s.map ~= e.map then return false end

    local P = engine.Player
    local distance = math.abs(P.cellX - actor.cellX) + math.abs(P.cellY - actor.cellY)
    if distance ~= 1 then return false end

    busy = true
    engine.Field.locked = true
    if P.cellX < actor.cellX then P.facing = "right"
    elseif P.cellX > actor.cellX then P.facing = "left"
    elseif P.cellY < actor.cellY then P.facing = "down"
    else P.facing = "up" end

    clearActor(name)
    mod.world:startWildBattle(e.species, 50, function()
      engine.Field.locked = false
      busy = false
      if not caught(s, e.species) then
        state(s)[name .. "AttemptedThisVisit"] = true
        clearActor(name)
      end
    end)
    return true
  end

  local function refresh()
    for name in pairs(EVENTS) do show(name) end
  end

  mod.events:on("map.entered", function()
    local s = session()
    if s then
      local st = state(s)
      for name, e in pairs(EVENTS) do
        if s.map == e.map then st[name .. "AttemptedThisVisit"] = false end
      end
    end
    clearAll()
    refresh()
  end)

  mod.events:on("world.stepped", function()
    refresh()
    if busy then return end
    for name in pairs(EVENTS) do
      if trigger(name) then break end
    end
  end)

  mod.log:info("Lake Trio events installed")
  return true
end
