#!/usr/bin/env lua

require "luarocks.require"
require "versium.filedir"
require "versium.sync"
require "serialize"
local http = require "socket.http"

local blacklist = versium.sync.blacklist{ "@SyncClient_Metadata" }

local server = "http://localhost:8080/sync/server.ws"

local repo = versium.filedir.new{ "./versium" }

local meta_info = repo:get_node_info("@SyncClient_Metadata")

if not meta_info then
  versium.sync.client_checkout(repo, server, blacklist)
else
  local server_changed, conflicts = versium.sync.client_update(repo, server, blacklist)
  versium.sync.client_commit(repo, server, blacklist, server_changed, conflicts)
end
