return function(mod)
  if mod.generation ~= 3 then return end

  local untamed
  local ok, found = pcall(function() return mod:find("untamed_advanced") end)
  if ok then untamed = found end
  if not untamed then
    mod.log:error("Lake Trio requires Untamed Advanced")
    return
  end

  local function install()
    local engine = untamed.exports and untamed.exports.engine
    if not engine then
      mod.log:warn("Untamed Advanced engine is not ready yet")
      return false
    end

    local source = assert(mod:read("lake_trio.lua"))
    local installer = assert(load(source, "@" .. mod.path .. "/lake_trio.lua"))()
    return installer(mod, engine)
  end

  mod.events:on("game.ready", install, -40)
end
