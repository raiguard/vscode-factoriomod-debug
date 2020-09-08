local global_data = {}

function global_data.init()
  if __DebugAdapter then
    global.event_log = {
      counts = {},
      items = {},
      next_index = 0
    }
  end
  global.flags = {
    create_guis = true
  }
  global.gui = {}
end

return global_data