#!/usr/bin/env wsapi.cgi

require "wsapi.request"
require "wsapi.response"
require "versium.filedir"
require "versium.sync.server"
require "versium.sync.serialize"

local REPO_PATH  -- set this to change location of repository

local function R(str)
  local sent
  return function ()
	   if not sent then
	     sent = true
	     return str
	   end
	 end
end

local function run(wsapi_env)
  local repo = versium.filedir.new{ REPO_PATH or wsapi_env.APP_PATH .. "/versium" }
  local path_info, method = wsapi_env.PATH_INFO, string.lower(wsapi_env.REQUEST_METHOD)
  local blacklist = versium.sync.server.blacklist{ "@SyncServer_Metadata" }
  local res_header = { ["Content-Type"] = "application/versium-sync" }
  local server = versium.sync.server.new(repo, blacklist)
  if path_info:match("^/%d+$") and method == "get" then
    local timestamp = path_info:match("^/(%d+)$")
    return 200, res_header, R(serialize(server:update(timestamp)) 
			    .. "\n")
  elseif path_info == "/" and method == "get" then
    return 200, res_header, R(serialize(server:checkout()) .. "\n") 
  elseif path_info:match("^/%d+$") and method == "post" then
    local timestamp = path_info:match("^/(%d+)$")
    local postdata = wsapi_env.input:read(tonumber(wsapi_env.CONTENT_LENGTH))
    local changes = loadstring(postdata)() or {}
    return 200, res_header, R(serialize(server:commit(timestamp, changes))
			    .. "\n")
  else
    return 500, { ["Content-Type"] = "text/plain" }, R"Versium Sync Server: Invalid Request"
  end
end

return run
