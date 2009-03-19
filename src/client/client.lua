#!/usr/bin/env lua

require "luarocks.require"
require "versium.filedir"
require "versium.sync"
require "serialize"
local http = require "socket.http"

local blacklist = versium.sync.blacklist{ "@SyncClient_Metadata" }

local repo = versium.filedir.new{ "./versium" }

versium.sync.client_update(repo, "http://localhost:8080/sync/server.ws", blacklist)

