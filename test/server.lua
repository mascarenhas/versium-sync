
package.path = "../src/?.lua;" .. package.path

require "luarocks.require"
require "versium.sync.server"
require "versium.virtual"

local blacklist = versium.sync.server.blacklist{ "@SyncServer_Metadata" }

local function empty(t)
  for k, v in pairs(t) do
    return false
  end
  return true
end

local function make_repo()
  repo = versium.virtual.open()
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

function test_checkout()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  assert(#r.nodes == 4)
  for _, node in ipairs(r.nodes) do
    assert(node[1] == "add")
    assert(repo:get_node(node[2], node[3].version) == node[4])
  end
  assert(tonumber(r.timestamp) == 2)
end

function test_update_checkout()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:update(string.format("%06d", 1))
  assert(#r.nodes == 4)
  for _, node in ipairs(r.nodes) do
    assert(node[1] == "add")
    assert(repo:get_node(node[2], node[3].version) == node[4])
  end
  assert(tonumber(r.timestamp) == 2)
end

function test_update_empty()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  r = s:update(r.timestamp)
  assert(#r.nodes == 0)
  assert(tonumber(r.timestamp) == 2)
end

function test_update_changes()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  repo:save_version("Bar", "new version of bar", "mascarenhas")
  repo:save_version("Page", "a new page", "carregal")
  r = s:update(r.timestamp)
  assert(#r.nodes == 2)
  for _, node in ipairs(r.nodes) do
    assert(repo:get_node(node[2], node[3].version) == node[4])
    if node[1] == "add" then
      assert(node[2] == "Page")
      assert(node[4] == "a new page")
    elseif node[1] == "change" then
      assert(node[2] == "Bar")
      assert(node[4] == "new version of bar")
    else
      error("invalid action")
    end
  end
  assert(tonumber(r.timestamp) == 3)
end

function test_checkout_interleaved()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r1, r2 = s:checkout(), s:checkout()
  assert(r1 ~= r2)
  local r = r1
  assert(#r.nodes == 4)
  for _, node in ipairs(r.nodes) do
    assert(node[1] == "add")
    assert(repo:get_node(node[2], node[3].version) == node[4])
  end
  assert(tonumber(r.timestamp) == 2)
  local r = r2
  assert(#r.nodes == 4)
  for _, node in ipairs(r.nodes) do
    assert(node[1] == "add")
    assert(repo:get_node(node[2], node[3].version) == node[4])
  end
  assert(tonumber(r.timestamp) == 3)
end

function test_update_interleaved()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r1, r2 = s:checkout(), s:checkout()
  repo:save_version("Bar", "new version of bar", "mascarenhas")
  repo:save_version("Page", "a new page", "carregal")
  local r1 = s:update(r1.timestamp)
  local r = r1
  assert(#r.nodes == 2)
  for _, node in ipairs(r.nodes) do
    assert(repo:get_node(node[2], node[3].version) == node[4])
    if node[1] == "add" then
      assert(node[2] == "Page")
      assert(node[4] == "a new page")
    elseif node[1] == "change" then
      assert(node[2] == "Bar")
      assert(node[4] == "new version of bar")
    else
      error("invalid action")
    end
  end
  assert(tonumber(r.timestamp) == 4)
  local r2 = s:update(r2.timestamp)
  local r = r2
  assert(#r.nodes == 2)
  for _, node in ipairs(r.nodes) do
    assert(repo:get_node(node[2], node[3].version) == node[4])
    if node[1] == "add" then
      assert(node[2] == "Page")
      assert(node[4] == "a new page")
    elseif node[1] == "change" then
      assert(node[2] == "Bar")
      assert(node[4] == "new version of bar")
    else
      error("invalid action")
    end
  end
  assert(tonumber(r.timestamp) == 5)
  local r1 = s:update(r1.timestamp)
  assert(#r1.nodes == 0)
  assert(tonumber(r1.timestamp) == 4)
  local r2 = s:update(r2.timestamp)
  assert(#r2.nodes == 0)
  assert(tonumber(r2.timestamp) == 5)
end

function test_commit_noconflict()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  assert(#r.nodes == 4)
  local changes = { 
    { "change", "Foo", { author = "mascarenhas" }, "a new foo from client", 
      repo:get_node_info("Foo").version }, 
    { "change", "Bar", { author = "mascarenhas" }, "a new bar from client", 
      repo:get_node_info("Bar").version },
    { "add", "Baz", { author = "mascarenhas" }, "a new baz from client" } 
  }
  local ci = s:commit(r.timestamp, changes)
  assert(tonumber(ci.timestamp) == tonumber(r.timestamp) + 1)
  assert(empty(ci.conflicts))
  for i, id in ipairs{ "Foo", "Bar", "Baz" } do
    assert(ci.delta[id])
    assert(repo:get_node_info(id).version == ci.delta[id])
    assert(repo:get_node(id) == changes[i][4])
    assert(repo:get_node_info(id).author == changes[i][3].author)
  end
  r = s:update(ci.timestamp)
  assert(#r.nodes == 0)
  assert(r.timestamp == ci.timestamp)
end

function test_commit_conflict_exist()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  assert(#r.nodes == 4)
  local changes = { 
    { "change", "Foo", { author = "mascarenhas" }, "a new foo from client", 
      repo:get_node_info("Foo").version }, 
    { "change", "Bar", { author = "mascarenhas" }, "a new bar from client", 
      repo:get_node_info("Bar").version },
    { "add", "Baz", { author = "mascarenhas" }, "a new baz from client" } 
  }
  repo:save_version("Bar", "a new bar from server", "carregal")
  local ci = s:commit(r.timestamp, changes)
  assert(tonumber(ci.timestamp) == tonumber(r.timestamp) + 1)
  assert(ci.conflicts["Bar"])
  for i, id in pairs{ [1] = "Foo", [3] = "Baz" } do
    assert(ci.delta[id])
    assert(repo:get_node_info(id).version == ci.delta[id])
    assert(repo:get_node(id) == changes[i][4])
    assert(repo:get_node_info(id).author == changes[i][3].author)
  end
  assert(repo:get_node("Bar") == "a new bar from server")
  r = s:update(ci.timestamp)
  assert(#r.nodes == 1)
  assert(tonumber(r.timestamp) == tonumber(ci.timestamp) + 1)
end

function test_commit_conflict_new()
  local repo = make_repo()
  local s = versium.sync.server.new(repo, blacklist)
  local r = s:checkout()
  assert(#r.nodes == 4)
  local changes = { 
    { "change", "Foo", { author = "mascarenhas" }, "a new foo from client", 
      repo:get_node_info("Foo").version }, 
    { "change", "Bar", { author = "mascarenhas" }, "a new bar from client", 
      repo:get_node_info("Bar").version },
    { "add", "Baz", { author = "mascarenhas" }, "a new baz from client" } 
  }
  repo:save_version("Baz", "a new baz from server", "carregal")
  local ci = s:commit(r.timestamp, changes)
  assert(tonumber(ci.timestamp) == tonumber(r.timestamp) + 1)
  assert(ci.conflicts["Baz"])
  for i, id in pairs{ [1] = "Foo", [2] = "Bar" } do
    assert(ci.delta[id])
    assert(repo:get_node_info(id).version == ci.delta[id])
    assert(repo:get_node(id) == changes[i][4])
    assert(repo:get_node_info(id).author == changes[i][3].author)
  end
  assert(repo:get_node("Baz") == "a new baz from server")
  r = s:update(ci.timestamp)
  assert(#r.nodes == 1)
  assert(tonumber(r.timestamp) == tonumber(ci.timestamp) + 1)
end

for n, f in pairs(_G) do
  if type(n) == "string" and n:match("^test_") then
    f()
  end
end

