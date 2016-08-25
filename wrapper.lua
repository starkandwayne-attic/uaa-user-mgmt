#!/usr/bin/lua

local yaml = require "yaml"

local env = {}
local command = ""
local remove = false
local groupsonly = false

local getRelCurDir = function()
	local idx = nil
	local tmpIdx = arg[0]:find("/")
	while tmpIdx do
		idx = tmpIdx
		tmpIdx = arg[0]:sub(idx + 1):find("/")
	end
	return idx and arg[0]:sub(0, idx - 1) or arg[0]
end

local SCRIPT_DIR = getRelCurDir()
local ENV_DIR = SCRIPT_DIR .. "/environments"
local GLOBAL_DIR = ENV_DIR .. "/global"

--logging functions
local log = {}

log.warn = function(mess)
  io.stderr:write("\27[33mWARNING: "..mess.."\27[0m\n")
end

log.err = function(mess)
  io.stderr:write("\27[31mERROR: "..mess.."\27[0m\n")
  log._errFlag = 1
end

log.info = function(mess)
  io.stderr:write("\27[36mINFO: "..mess.."\27[0m\n")
end

log.triggerErr = function()
  if log._errFlag then os.exit(1) end
end

local mustExec = function(command)
  if newExecute then
    local handle = io.popen(command)
    local output = handle:read("*a")
    local ok = handle:close()
    if not ok then
      log.err("`"..command.."` returned with error:\n\t"..output)
      log.triggerErr()
    end
  else
    code = os.execute(command)
    if tonumber(code) > 0 then
      log.err("`"..command.."` returned with error:\n")
      log.triggerErr()
    end
  end
end


local usage = function()
	io.stderr:write("\27[35mUSAGE:\n  "..
	arg[0].." [remove] (cf|bosh) <env>\n  "..
	"<env> is, for example, \"site1/prod\"\27[0m\n")
	os.exit(0)
end

local sanityCheck = function()
	if command == "" then
		log.err("No command given (cf or bosh)")
	end
	if #env == 0 then
		log.err("No environment specified")
	end
	if #env > 1 then
		log.err("Too many additional args: "..table.concat(env, ", "))
	end

	if log._errFlag then usage() end
	log.triggerErr()
end

--Parse the user commands
local dispatch = {
	cf = function() command = "cf" end,
	bosh = function() command = "bosh" end,
	remove = function() remove = true end,
	groupsonly = function() groupsonly = true end,
	help = usage,
	usage = usage,
	["-h"] = usage,
	__index = function(t, k) return function() table.insert(env, k) end end
}
setmetatable(dispatch, dispatch)

for i, v in ipairs(arg) do
	if i ~= 0 then dispatch[v]() end
end

--make sure the user gave us something that makes sense
sanityCheck()

--gen passwords
local spruceCommand = "spruce merge "..GLOBAL_DIR.."/users.yml "..GLOBAL_DIR.."/pass_params.yml"
mustExec(spruceCommand.." | "..SCRIPT_DIR.."/adduaausers.lua password > "..ENV_DIR.."/.tmp")
local tmphandle = io.open(ENV_DIR.."/.tmp")
assert(tmphandle)
usershandle = io.open(GLOBAL_DIR.."/users.yml", "w+")
assert(usershandle)
local yamltree = yaml.load(tmphandle:read("*all"))
yamltree["config"] = nil
usershandle:write(yaml.dump(yamltree))
tmphandle:close()
usershandle:close()

--all the files we need to spruce together
local globalFiles = {
	"admins.yml",
	"groups.yml",
	"users.yml",
	"pass_params.yml",
	"uaa.yml",
}
local envFiles = {
	"admins.yml",
	"groups.yml",
	command.."_uaa.yml"
}

-- prepend the correct paths
for i, v in ipairs(globalFiles) do
	globalFiles[i] = GLOBAL_DIR.."/"..v
end

for i, v in ipairs(envFiles) do
	envFiles[i] = ENV_DIR.."/"..env[1].."/"..v
end


local spruceCommand = "spruce merge " .. table.concat(globalFiles, " ") .. " " ..  table.concat(envFiles, " ")

if remove then command = "remove" end
if groupsonly then command = "groupsonly" end

mustExec(spruceCommand.." | "..SCRIPT_DIR.."/adduaausers.lua "..command.." --raw")
