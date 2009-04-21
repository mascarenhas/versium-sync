
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

local function set2pairs(t)
  local l = {}
  for k, v in pairs(t) do
    l[#l + 1] = { k, v }
  end
  return l
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
  os.execute("sleep 10")
end

function test_checkout()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  stop_server()
end

function test_update_empty()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  local ts = crepo:get_node_info("@SyncClient_Metadata").version
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  assert(ts ==  crepo:get_node_info("@SyncClient_Metadata").version)
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  assert(ts ==  crepo:get_node_info("@SyncClient_Metadata").version)
  stop_server()
end

function test_update_changes()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  srepo:save_version("Bar", "new version of bar", "mascarenhas")
  srepo:save_version("Page", "a new page", "carregal")
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 2)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  local ts = crepo:get_node_info("@SyncClient_Metadata").version
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  assert(ts ==  crepo:get_node_info("@SyncClient_Metadata").version)
  stop_server()
end

function test_update_conflict()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  srepo:save_version("Bar", "new version of bar", "mascarenhas")
  srepo:save_version("Page", "a new page", "carregal")
  crepo:save_version("Bar", "conflict on bar", "carregal")
  local confs, changes = c:update()
  assert(#confs == 1)
  assert(crepo:get_node("Bar") == "conflict on bar")
  for _, conf in ipairs(confs) do
    assert(conf.text == srepo:get_node(conf.id, conf.info.version))
    crepo:save_version(conf.id, conf.text, conf.info.author)
  end
  changes = set2pairs(changes)
  assert(#changes == 1)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  stop_server()
end

function test_commit()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  local new_nodes = {
    { "Bar", "new version of bar", "mascarenhas" },
    { "Page", "a new page", "carregal" }
  }
  for _, node in ipairs(new_nodes) do
    crepo:save_version(unpack(node))
  end
  local confs = c:commit()
  assert(#confs == 0)
  for _, node in ipairs(new_nodes) do
    assert(srepo:get_node(node[1]) == node[2])
    assert(srepo:get_node_info(node[1]).author == node[3])
  end
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  stop_server()
end

function test_commit_conflict()
  local srepo = make_server_repo()
  local crepo = empty_repo()
  start_server()
  local c = versium.sync.client.new(crepo, "http://localhost:8080/server.ws", blacklist)
  local confs, changes = c:update()
  assert(empty(confs))
  changes = set2pairs(changes)
  assert(#changes == 4)
  for _, node in ipairs(changes) do
    assert(srepo:get_node(node[1]) == crepo:get_node(node[1], node[2]))
  end
  local new_nodes = {
    { "Bar", "new version of bar", "mascarenhas" },
    { "Page", "a new page", "carregal" },
    { "Foo", "new version of foo", "mascarenhas" }
  }
  for _, node in ipairs(new_nodes) do
    crepo:save_version(unpack(node))
  end
  srepo:save_version(unpack(new_nodes[1]))
  srepo:save_version(unpack(new_nodes[2]))
  local confs = c:commit()
  assert(#confs == 2)
  for i = 3, #new_nodes do
    local node = new_nodes[1]
    assert(srepo:get_node(node[1]) == node[2])
    assert(srepo:get_node_info(node[1]).author == node[3])
  end
  local confs, changes = c:update()
  assert(empty(confs))
  assert(not empty(changes))
  local confs = c:commit()
  assert(#confs == 0)
  local confs, changes = c:update()
  assert(empty(confs))
  assert(empty(changes))
  stop_server()
end

for n, f in pairs(_G) do
  if type(n) == "string" and n:match("^test_") then
    pcall(f)
    stop_server()
  end
end

os.exit()
