
package.path = "../src/?.lua;" .. package.path

require "luarocks.require"
require "versium.sync.client"
require "versium.filedir"
require "versium.virtual"

local blacklist = versium.sync.client.blacklist{ "@SyncClient_Metadata" }

local function empty(t)
  for k, v in pairs(t) do
    return false
  end
  return true
end

local function make_server_repo()
  os.execute("rm -rf ../src/server/versium")
  os.execute("mkdir ../src/server/versium")
  repo = versium.filedir.new{ "../src/server/versium" }
  repo:save_version("Index", "This is the index page", "mascarenhas")
  repo:save_version("Index", "A new version of the index page", "mascarenhas")
  repo:save_version("Another", "This is another page", "carregal")
  repo:save_version("Another", "Second version of another page", "carregal")
  repo:save_version("Another", "Third version of another page", "carregal")
  repo:save_version("Foo", "yet another page", "medeiros")
  repo:save_version("Foo", "yet another page changed", "medeiros")
  repo:save_version("Bar", "final page", "medeiros")
  return repo
end

local function empty_repo()
  return versium.virtual.open()
end

local pipe

local function start_server()
  os.execute("rm ../src/server/stop")
  pipe = io.popen("lua testserver.lua")
  assert(pipe)
  os.execute("sleep 1")
end

local function stop_server()
  os.execute("touch ../src/server/stop")
  os.execute("sleep 5")
end

function test_checkout()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local r = c:update()
  assert(empty(r))
  for _, id in ipairs(crepo:get_node_ids()) do
    if not blacklist(id) then
      assert(srepo:get_node(id) == crepo:get_node(id))
    end
  end
  stop_server()
end

for n, f in pairs(_G) do
  if type(n) == "string" and n:match("^test_") then
    pcall(f)
    stop_server()
  end
end

os.exit()
