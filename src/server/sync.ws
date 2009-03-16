#!/usr/bin/env wsapi.cgi

require "wsapi.request"
require "wsapi.response"
require "versium.filedir"
require "serialize"

local repo

local blacklist = { ["@SyncServer_Metadata"] = true }

local function R(str)
  local sent
  return function ()
	    if not sent then
	      sent = true
	      return str
	    end
	 end
end

local function sync_changes(wsapi_env, timestamp)
  local sync_meta_node = repo:get_node("@SyncServer_Metadata", timestamp)
  if not sync_meta_node then
     return 500, {}, R"Sync Timestamp Not Found"
  else
    local sync_meta_info = loadstring(sync_meta_node)()
    local diff = {}
    for _, node_id in pairs(repo:get_node_ids()) do
      if sync_meta_info[node_id] then
	if repo:get_node_info(node_id).version ~= sync_meta_info[node_id] then
	   table.insert(diff, { "change", node_id, repo:get_node_info(node_id), 
				repo:get_node(node_id) })
	end
	sync_meta_info[node_id] = nil
      elseif not blacklist[node_id] then
	table.insert(diff, { "add", node_id, repo:get_node_info(node_id), 
			     repo:get_node(node_id) })
      end
    end
    for node_id, _ in pairs(sync_meta_info) do
      table.insert(diff, { "delete", node_id })
    end
    return 200, {}, R(serialize(diff))
  end
end

local function sync_all(wsapi_env)
  local diff = {}
  for _, node_id in ipairs(repo:get_node_ids()) do
    if not blacklist[node_id] then
      table.insert(diff, { "add", node_id, repo:get_node_info(node_id), 
			   repo:get_node(node_id) })
    end
  end
  return 200, {}, R(serialize(diff))
end

local function sync_update(wsapi_env)
  local postdata = wsapi_env.input:read(tonumber(wsapi_env.CONTENT_LENGTH))
  local diff = loadstring(postdata)() or {}
  for _, change in ipairs(diff) do
    if change[1] == "delete" then
      repo:save_version(change[2], "", "Sync System")
    else
      repo:save_version(change[2], change[4], change[3].author, change[3].comment,
			change[3].extra, change[3].timestamp)
    end
  end
  local sync_info = {}
  for _, node_id in ipairs(repo:get_node_ids()) do
     if not blacklist[node_id] then
       local version = repo:get_node_info(node_id).version
       sync_info[node_id] = version
     end
  end
  repo:save_version("@SyncServer_Metadata", serialize(sync_info), "Sync System")
  local timestamp = repo:get_node_info("@SyncServer_Metadata").version
  return 200, {}, R(tostring(timestamp))
end

local function run(wsapi_env)
  repo = versium.filedir.new{ wsapi_env.APP_PATH .. "/versium" }
  local path_info, method = wsapi_env.PATH_INFO, string.lower(wsapi_env.REQUEST_METHOD)
  if path_info:match("^/%d+$") and method == "get" then
    local timestamp = path_info:match("^/(%d+)$")
    return sync_changes(wsapi_env, timestamp)
  elseif path_info == "/" and method == "get" then
    return sync_all(wsapi_env) 
  elseif path_info == "/" and method == "post" then
    return sync_update(wsapi_env)
  else
    return 500, {}, R"Invalid Request"
  end
end

return run
