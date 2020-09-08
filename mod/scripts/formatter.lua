-- take in event data and spit out the string to add to the log
-- second return is the event ID to increment

local reverse_defines = require("__flib__.reverse-defines")
local table = require("__flib__.table")

local constants = require("scripts.constants")
local variables = require("variables")

local function rich_text(key, value, inner)
  if key == "color" then
    value = constants.colors[value]
  elseif key == "font" then
    value = constants.fonts[value]
  end
  return "["..key.."="..value.."]"..inner.."[/"..key.."]"
end

return function(e)
  -- copy and modify the event table
  local event_data = table.shallow_copy(e)
  event_data.name = nil
  event_data.tick = nil
  event_data.__eventname = nil
  event_data.__debug = nil

  -- get event name
  local name = reverse_defines.events[e.name] or e.input_name or e.__eventname or "custom mod event "..e.name

  -- retrieve and add to count
  local count = (global.event_log.counts[name] or 0) + 1
  global.event_log.counts[name] = count

  -- build string
  local str = {
    rich_text("font", "tick", rich_text("color", "tick", e.tick..". ")),
    rich_text("color", "event_name", name.." "),
    rich_text("font", "tick", rich_text("color", "tick", count.."  ")),
    "{ "
  }

  local first = true
  for key, value in pairs(event_data) do
    local output = key.."="..variables.describe(value)
    str[#str+1] = first and output or ", "..output
    if first then first = false end
  end
  str[#str+1] = " }"

  -- output
  return table.concat(str), event_data
end