local parser        = require("Bytecode.BytecodeParser")
local treeGenerator = require("Vm.TreeGenerator")
local antiEnvLogger = require("Vm.Resources.Templates.EnvLogDetection")
local antitamper    = require("Vm.Resources.Templates.AntiTamper")
local LuauSanitizer = require("Vm.LuauSanitizer")
local luasrcdiet    = require("luasrcdiet.init")
local settings      = require("Input.Settings")

local function writeFile(path, content)
    local h = io.open(path, "w")
    h:write(content)
    h:close()
end

local function writeFileBin(path, content)
    local h = io.open(path, "wb")
    h:write(content)
    h:close()
end

local function restoreInput(path, content)
    writeFileBin(path, (content:gsub("\r\n", "\n"):gsub("\r", "\n")))
end

return function(inputFile, outputTo)
    local savedInput = _G.readFile(inputFile)
    outputTo = outputTo or "Input/Output.lua"

    writeFile(inputFile, _G.readFile("Vm/Resources/Templates/AddToInput.lua") .. "\n" .. savedInput)

    if settings.AntiTamper then
        _G.display("Adding Anti-Tamper...", "green")
        writeFile(inputFile, antitamper .. " \n " .. _G.readFile(inputFile))
    end

    if settings.LuaUCompatibility then
        _G.display("LuaU Compatibility mode enabled.", "yellow")
        writeFile(inputFile, LuauSanitizer.sanitize(_G.readFile(inputFile)))
    end

    _G.display("Compiling to bytecode...", "green")
    local ok = os.execute("luac5.1 -o Input/luac.out " .. inputFile)

    if ok ~= 0 and ok ~= true then
        _G.display("luac compilation failed!", "red")
        restoreInput(inputFile, savedInput)
        return
    end

    local bytecode = _G.readFile("Input/luac.out")
    if not bytecode or #bytecode == 0 then
        _G.display("luac produced no output! Check your input file.", "red")
        restoreInput(inputFile, savedInput)
        return
    end

    _G.display("Parsing bytecode...", "green")
    local parsed = parser(bytecode)

    _G.display("Generating VM tree...", "green")
    local vmTree = treeGenerator(parsed):gsub(":INSERTENVLOG:", antiEnvLogger)

    -- Roblox LuaU compatibility fixes
    if settings.LuaUCompatibility then
        _G.display("Applying Roblox compatibility fixes...", "yellow")
        vmTree = vmTree:gsub("os%.time%(%)", "tick and tick() or 0")
        vmTree = vmTree:gsub("_ENV or getfenv%(%)", "_ENV")
        vmTree = vmTree:gsub("getfenv%(%)", "_ENV")
    end

    if settings.Minify then
        _G.display("Minifying output...", "green")
        local opts = {}
        for k, v in pairs(luasrcdiet.MAXIMUM_OPTS) do
            opts[k] = v
        end
        opts["opt-strings"] = false
        local ok, result = pcall(function()
            return luasrcdiet.optimize(opts, vmTree)
        end)
        if ok and result and #result > 0 then
            vmTree = result
            _G.display("Minification successful.", "green")
        else
            _G.display("Minification skipped (complex output).", "yellow")
            if not ok then
                _G.display("Error: " .. tostring(result), "red")
            end
        end
    end

    local out = io.open(outputTo, "w")
    if out then
        out:write(vmTree)
        out:close()
        _G.display("Output written to " .. outputTo, "green")
    else
        _G.display("Error writing to " .. outputTo, "red")
    end

    print("File has been obfuscated.")
    restoreInput(inputFile, savedInput)
end
