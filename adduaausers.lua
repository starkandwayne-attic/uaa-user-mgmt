#!/usr/bin/lua

--[[
AUTHOR: thomasmmitchell
A script that puts users into the UAA database, and can be used to add a bunch
of admins to Cloud Foundry.
not necessarily complete. Updated as needed. Code is a mess - god help thee
who enter.
]]--

local yaml = require "yaml"

local config = nil
--keys should match those in config
local pass_params = {
  min_length = 8,
  max_length = 16,
  digits = 0,
  lower_case = 0,
  upper_case = 0,
  special = 0
}
local valid_users_params = {
  name = true,
  email = true,
  password = true
}

--halp
local usage = function()
  io.stderr:write("\27[35m"..arg[0].." (cf|uaa|bosh) [options]\27[0m\n")
  helped = true
end

local optionsHelp = function()
	io.stderr:write("\27[35moptions:\n"..
	"  -f, --filename : Specifies the file to use as the config file. If not set,\n"..
	"                   reads from stdin.\n"..
	"  -i, --inplace  : Will write changes to the config directly back to the config\n"..
  "                   file. If not set, output goes to stdout\27[0m\n")
end

local help = function()
	usage()
	io.stderr:write("\27[35m---\n\27[0m")
	optionsHelp()
	os.exit(0)
end

--are you sure?
local promptYN = function(thing)
	local answer = rawmode and "y" or ""
	while answer ~= "y" and answer ~= "n" do
		io.stdout:write("\27[33mAre you sure you want to "..thing.."? \27[0m(y/n): ")
		answer = io.read()
	end
	return answer == "y"
end

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

local printOs = function(percent)
	if numOs < 10 then return end
	if percent > 1 then percent = 1 end
	io.stderr:write("|")
	local current = numOs * percent
	for i=1, current do
		io.stderr:write("O")
	end
	for i=1, numOs - current do
		io.stderr:write("-")
	end
	local append = ""
	if percent == 1 then append = "\n" end
	io.stderr:write("| " .. string.format("%.2f", percent * 100) .. "%" .. append .. "\r")
	io.stderr:flush()
end


local nilToZero = function(value)
  return value or 0
end

local verifyConfig = function()
  --config given?
  if config == nil or config == "" then log.err("No config given") end

  user_exists = {}
  --There is at least one user defined
  if (not config["users"]) or #config["users"] == 0 then
    log.warn("No users were defined. Exiting.")
    os.exit(0)
  end
  for i, v in ipairs(config["users"]) do
    if not v["name"] or v["name"] == "" then
      err("`users.("..i..")` is missing `name` key")
    end
    if not v["email"] or v["email"] == "" then
      err("`users.("..i..")` is missing `email` key")
    end
    for k, _ in pairs(v) do
      if not valid_users_params[k] then
        err("Unrecognized key `users.("..i..")."..v.."`")
      end
    end
    if v["name"] then
      --populate list of users
      user_exists[v["name"]] = true
    end
  end

  --config key present and valid?
  local conf = config["config"]
  if conf == nil then 
    log.err("No `config` key found in input")
    return
  elseif type(conf) ~= "table" then 
    log.err("`config` key not a hash") 
  end

	if not useronly then
		--config.uaa checks
		local uaa = conf["uaa"]
		if uaa == nil then
			log.err("`config.uaa` is not defined")
		elseif type(uaa) ~= "table" then
			log.err("`config.uaa` is not a hash")
		end
		if not uaa["client_secret"] then
			log.err("`config.uaa.client_secret` not defined")
		end
		if not uaa["target"] then
			log.err("`config.uaa.target` not defined")
		end
		recognized_uaa = { client_secret = true, target = true }
		for k, _ in pairs(uaa) do
			if not(recognized_uaa) then
				log.err("`config.uaa."..k.."` is not a recognized key")
			end
		end
	end

  --config.password checks
  local pass = conf["password"]
  if pass ~= nil then
    if type(pass) ~= "table" then
      log.err("Key `config.password` not a hash")
    end
    --no invalid keys. no negative values
    for k, v in pairs(pass) do
      if not pass_params[k] then 
        log.err("Unrecognized key `config.password."..k.."`") 
      end
      if not tonumber(v) then
        log.err("Value "..v.." at key `config.password."..k.."` can not be "..
        "converted to a number")
      elseif tonumber(v) < 0 then
        log.err("Value "..v.." at key `config.password."..k.."` is a number less than 0")
      end
    end
    --max >= min
    if pass["max_length"] < pass["min_length"] then
      log.err("`config.password.min_length` greater than `config.password.max_length`")
    end
    -- required chars shouldn't be greater than min chars
    -- definitely shouldn't be greater than max chars
    reqChars = nilToZero(pass["digits"]) +
                 nilToZero(pass["lower_case"]) +
                 nilToZero(pass["upper_case"]) +
                 nilToZero(pass["special"])
    if pass["max_length"] and reqChars > pass["max_length"] then
      log.err("Characters required for password greater than maximum password length")
      return
    elseif pass["min_length"] and reqChars > pass["min_length"] then
      log.warn("Characters required for password greater than minimum password length")
    end
  end

	if not useronly then
		if not config["admins"] or #config["admins"] == 0 then
			log.warn("No admins were specified to add. Aborting.")
			os.exit(0)
		end
		for _, admin in ipairs(config["admins"]) do
			if not user_exists[admin] then
				log.err("Cannot make unknown user `"..admin.."` into admin")
			end
		end
	end

  --groups checks
  groups = config["groups"]
  if groups then
    for i, group in ipairs(groups) do
      if not group["name"] then err("no name given for group") end
      if not group["members"] or #group["members"] == 0 then log.warn("no members given for `groups."..i.."`") end
      for k, v in pairs(group) do
        if k ~= "name" and k ~= "members" and k ~= "skipcreate" then 
          log.err("unrecognized key `groups."..i.."."..k.."`") 
        elseif k == "skipcreate" and v ~= true and v ~= false then
          log.err("invalid value for `groups."..i..".skipcreate`")
        end
      end
    end
  end
end

local loadConfig = function()
  if (not config) or (not config["config"]) then 
    return 
  end
  for k, v in pairs(config["config"]["password"]) do
    pass_params[k] = v
  end
  reqChars = nilToZero(pass_params["digits"]) +
            nilToZero(pass_params["lower_case"]) +
            nilToZero(pass_params["upper_case"]) +
            nilToZero(pass_params["special"])
  pass_params["min_length"] = math.max(reqChars, pass_params["min_length"])
  for i, user in ipairs(config["users"]) do
		if type(user["name"]) == "number" then
			user["name"] = tostring(user["name"])
		end
		if user["password"] and type(user["password"]) == "number" then
			user["password"] = tostring(user["password"])
		end
	end

	if not useronly then 
		for i, admin in ipairs(config["admins"]) do
			if type(admin) == "number" then
				config["admins"][i] = tostring(admin)
			end
		end
	end
end

local populateCharacters = function()
  --populate special characters table
  specialChars = {}
  specialStr = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
  for char in specialStr:gmatch(".") do
    table.insert(specialChars, char)
  end
  numberChars = {}
  for i=48, 57 do
    table.insert(numberChars, string.char(i))
  end
  lowerChars = {}
  upperChars = {}
  for i=65, 90 do
    table.insert(upperChars, string.char(i)) --uppercase
    table.insert(lowerChars, string.char(i+32)) --lowercase
  end
end

--get a random item from the given table.
--get a random item from either table if two are given
local getRandomChar = function(t1, t2)
  assert(type(t1) == "table")
  assert(not t2 or type(t2) == "table")
  local totalChars = #t1 + (t2 and #t2 or 0)
  index = math.random(totalChars)
  if index > #t1 then return t2[index - #t1]
  else return t1[index] end
end

local shuffle = function(t)
  assert(type(t) == "table")
  for i=1, #t-1 do
    index = math.random(i, #t)
    t[i], t[index] = t[index], t[i]
  end
end

local charIsNumber = function(c)
	return string.byte(c) >= 48 and string.byte(c) <= 57
end

local createPassword = function()
  local charPool = {}
  local passLen = math.random(pass_params["min_length"], pass_params["max_length"])
  for i=1, pass_params["digits"] do
    table.insert(charPool, getRandomChar(numberChars))
  end
  for i=1, pass_params["lower_case"] do
    table.insert(charPool, getRandomChar(lowerChars))
  end
  for i=1, pass_params["upper_case"] do
    table.insert(charPool, getRandomChar(upperChars))
  end
  for i=1, pass_params["special"] do
    table.insert(charPool, getRandomChar(specialChars))
  end
  while #charPool < passLen do
    table.insert(charPool, getRandomChar(upperChars, lowerChars))
  end
  shuffle(charPool)
  --So, there's this problem where the password gets dumped out unquoted and 
  --then parsed as a number if it starts with a number. And then it gets truncated
  --to just the number. And its not a good thing. This is a hack so that at least
  --we don't generate any passwords that lead to this truncation.
  --TODO fix the case where the whole pass is numbers
  while charIsNumber(charPool[1]) or 
  	(charIsNumber(charPool[2]) and (charPool[1] == "-" or charPool[1] == ".")) do
  	shuffle(charPool)
	end
  return table.concat(charPool)
end

local quoteMeta = function(s)
	assert(type(s) == "string")
	s = s:gsub("'", "'\"'\"'")
	return "'"..s.."'"
end

local shouldExec = function(command)
  if newExecute then
    local handle = io.popen(command.." 2>&1")
    local output = handle:read("*a")
    local ok = handle:close()
    if not ok then
      log.warn("`"..command.."` returned with error:\n\t"..output)
      return false
    end
  else
    code = os.execute(command.." 2>&1")
    if code > 0 then
      log.warn("`"..command.."` returned with error:\n")
      return false
    end
  end
  return true
end

local mustExec = function(command)
  if newExecute then
    local handle = io.popen(command.." 2>&1")
    local output = handle:read("*a")
    local ok = handle:close()
    if not ok then
      log.err("`"..command.."` returned with error:\n\t"..output)
      log.triggerErr()
    end
  else
    code = os.execute(command.." 2>&1")
    if tonumber(code) > 0 then
      log.err("`"..command.."` returned with error:\n")
      log.triggerErr()
    end
  end
end

local UAAAuth = function()
	log.info("Authenticating...")
	local skip = config.config.uaa.skipssl and "--skip-ssl-validation " or ""
  mustExec("uaac target "..skip..quoteMeta(config["config"]["uaa"]["target"]))
  mustExec("uaac token client get admin -s "..quoteMeta(config["config"]["uaa"]["client_secret"]))
end

local addUsers = function()
  UAAAuth()
	log.info("Creating users...")
	printOs(0)
  for i, user in ipairs(config["users"]) do
    if not user["password"] then
      user["password"] = createPassword()
    end
    shouldExec("uaac user add "..quoteMeta(user["name"]).." -p "..quoteMeta(user["password"])..
    " --emails "..quoteMeta(user["email"]))
    printOs(i/#(config["users"]))
  end
end

local addToGroups = function(users, groups)
  if not users or not groups then return end
	local userStr = ""
	for _, user in ipairs(users) do
		userStr = userStr.." "..quoteMeta(user)
	end
	printOs(0)
	for i, group in ipairs(groups) do
    shouldExec("uaac member add  "..group..userStr)
    printOs(i/#groups)
	end
end

local addUsersToUAA = function()
  addUsers()
  log.info("Giving UAA admin privileges...")
  addToGroups(config["admins"], {
			"uaa.admin", 
			"scim.read",
			"scim.write"
		})
end

local addUsersToCF = function() addUsers() 
	log.info("Giving CF admin privileges...") 
	addToGroups(config["admins"], { 
		"cloud_controller.admin",
		"scim.read" 
	}) 
end

local addUsersToBOSH = function()
	addUsers()
	log.info("Giving BOSH admin privileges...")
  addToGroups(config["admins"], {
			"bosh.admin", 
			"scim.read",
		})
end

local genPasswords = function()
	log.info("Generating passwords...")
	printOs(0)
  for i, user in ipairs(config["users"]) do
    if not user["password"] then
      user["password"] = createPassword()
      printOs(i/#(config["users"]))
    end
  end
end

local removeUsers = function()
	local confirmed = promptYN("remove all the listed users")
	if confirmed then
		UAAAuth()
		log.info("Removing users from UAA...")
		printOs(0)
		for i, user in ipairs(config["users"]) do
			shouldExec("uaac user delete "..quoteMeta(user["name"]))
			printOs(i/#(config["users"]))
		end
	end
end

local removePasswords = function()
	local confirmed = promptYN("remove all the passwords from the configuration file")
	if not confirmed then return end
	printOs(0)	
	for i, user in ipairs(config["users"]) do
		user["password"] = nil
		printOs(i/#(config["users"]))
	end
end

local writeUpdatedConfig = function(inplace)
	if inplace then
		local handle = io.open(inputfile, "w+")
		ok = handle:write(yaml.dump(config))
		if not ok then
			log.err("Couldn't write to output file!")
		end
		handle:close()
	else
		io.stdout:write(yaml.dump(config))
	end
end

local nonAdminGroups = function()
  if not config["groups"] then return end
  for _, group in ipairs(config["groups"]) do
    if group["skipcreate"] then
      log.info("Attempting to create group `"..group["name"].."`")
      shouldExec("uaac group add "..group["name"])
    end
    log.info("Attempting to populate group `"..group["name"].."`")
    addToGroups(group["members"], {group["name"]})
  end
end

local doAbsolutelyNothing = function()
end


local commandList = {
  uaa = addUsersToUAA,
  UAA = addUsersToUAA,
  cf = addUsersToCF,
  CF = addUsersToCF,
  bosh = addUsersToBOSH,
  BOSH = addUsersToBOSH,
  help = help,
  usage = help,
  password = genPasswords,
  passwords = genPasswords,
  nopass = removePasswords,
  remove = removeUsers,
  groupsonly = doAbsolutelyNothing,
  __index = function(t, k) 
    return function() 
			if k and k ~= "" then 
				log.err("`"..k.."` is not a recognized backend type")
			else log.err("no backend type was specified")
			end
      usage()
    end 
  end
}

setmetatable(commandList, commandList)

local getInputFile = function(i)
	inputfile=arg[i+1]
	return 1
end

local setInplace = function(i)
	inplace=true
	return 0
end

local setRaw = function(i)
	rawmode=true
	return 0
end

newExecute = _VERSION:find("5.2")

options = {
	["-f"] = getInputFile,
	["--filename"] = getInputFile,
	["-i"] = setInplace,
	["--inplace"] = setInplace,
	["--in-place"] = setInplace,
	["-r"] = setRaw,
	["--raw"] = setRaw,
	__index = function(t, k)
		return function(i)
			log.err("`"..k.."` is not a recognized option")
			optionsHelp()
			log.triggerErr()
		end
	end
}
setmetatable(options, options)

--get command
local command = commandList[arg[1]]
local usersOnlyCommands = {
	[genPasswords] = true, [removePasswords] = true, [removeUsers] = true
}
useronly = usersOnlyCommands[command]
if command == help then command() end
--process all the arguments
local toSkip=0
for i=2, #arg do
	if toSkip > 0 then
		toSkip = toSkip - 1
	else
		toSkip = options[arg[i]](i)
	end
end

local output = io.popen("tput cols") 
numOs = tonumber(output:read()) - 12
math.randomseed( os.time() )
--variable set by getInputFile if -f specified
if inputfile then
	local handle = io.open(inputfile, "r")
	input = handle:read("*all")
	handle:close()
else --otherwise, take it from stdin
	if inplace then
		log.err("Cannot specify inplace output without giving the input file explicitly.")
		log.triggerErr()
	end
	log.info("Waiting for stdin...")
	input = io.read("*all")
end
--get that yaml in a table
config = yaml.load(input)
verifyConfig()
log.triggerErr()
--do any additional state setup
loadConfig()
populateCharacters()
--actually perform the user's desired task
command()
log.triggerErr()
nonAdminGroups()
log.triggerErr()
if not helped then
	writeUpdatedConfig(inplace)
end
log.triggerErr()
