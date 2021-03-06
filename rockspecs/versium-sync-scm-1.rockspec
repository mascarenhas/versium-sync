package = "Versium-Sync"
version = "scm-1"
source = {
   url = "git://github.com/mascarenhas/versium-sync.git"
}
description = {
   summary = "Syncing Support for Versium",
   detailed = [[
     Implements an SCM-like protocol for Versium syncing.
   ]],
   homepage = "http://...", -- We don't have one yet
   license = "MIT/X11"
}
dependencies = {
   "lua >= 5.1", "versium"
}
build = {
   type = "none",
   install = {
     lua = {
       ["versium.sync.client"] = "src/versium/sync/client.lua",
       ["versium.sync.server"] = "src/versium/sync/server.lua",
       ["versium.sync.serialize"] = "src/versium/sync/serialize.lua"
     },
     bin = { "src/client/client.lua" },
   },
   copy_directories = { "src" }
}
