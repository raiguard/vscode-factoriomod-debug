local sharedevents
if __Profiler then
  sharedevents = require("__debugadapter__/profile-control.lua")
else
  sharedevents = require("__debugadapter__/debug-control.lua")
end
--[[
  debugger requires primary handler for some events, use these instead to be
  called when internal events finish:

  sharedevents = {
    on_init = function?,
    on_load = function?,
    on_tick = function?,
  }
]]

for event, handler in pairs(require("scripts.listeners")) do
  sharedevents[event] = handler
end
