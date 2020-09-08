local function disable_autosave()
  -- disable autosave so it won't try to save timers, this is a desync but i don't care.
  script.on_nth_tick(2,function(e)
    script.on_nth_tick(2,nil)
    game.autosave_enabled = false
  end)
end

local sharedevents = {}

script.on_init(function()
  disable_autosave()
  if sharedevents.on_init then return sharedevents.on_init() end
end)

script.on_load(function()
  disable_autosave()
  if sharedevents.on_load then return sharedevents.on_load() end
end)

script.on_event(defines.events.on_tick, function()
  if sharedevents.on_tick then return sharedevents.on_tick() end
end)

local function callAll(funcname,...)
  local results = {}
  local call = remote.call
  for remotename,_ in pairs(remote.interfaces) do
    local modname = remotename:match("^__profiler_(.+)$")
    if modname then
      results[modname] = call(remotename,funcname,...)
    end
  end
  return results
end

remote.add_interface("profiler",{
  dump = function() return callAll("dump") end,
  slow = function() return callAll("slow") end,
  save = function(name)
    callAll("slow")
    game.autosave_enabled = true
    game.auto_save(name or "profiler")
    disable_autosave()
  end,
})

return sharedevents