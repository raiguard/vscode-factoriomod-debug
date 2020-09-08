local global_data = {}

function global_data.init()
  if __DebugAdapter then
    global.event_log = {}
  end
  global.flags = {
    create_guis = true
  }
  global.gui = {}
end

return global_data