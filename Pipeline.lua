local parser        = require("Bytecode.BytecodeParser")
local treeGenerator = require("Vm.TreeGenerator")
local antiEnvLogger = require("Vm.Resources.Templates.EnvLogDetection")
local antitamper    = require("Vm.Resources.Templates.AntiTamper")
local LuauSanitizer = require("Vm.LuauSanitizer")
local minifier      = require("Vm.minifier1")
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

    -- Always sanitize Luau syntax (continue, type annotations, compound ops, etc.)
    _G.display("Sanitizing Luau syntax...", "green")
    writeFile(inputFile, LuauSanitizer.sanitize(_G.readFile(inputFile)))

    -- Compile to bytecode
    local bytecode

    if settings.LuauMode then
        -- Luau mode: try luau compiler
        _G.display("Compiling with Luau compiler...", "cyan")
        local luauOk = os.execute("luau-compile --binary " .. inputFile .. " > Input/luac.out 2>nul")
        if luauOk ~= 0 and luauOk ~= true then
            -- fallback: try 'luau' directly
            luauOk = os.execute("luau --compile=binary " .. inputFile .. " > Input/luac.out 2>nul")
        end
        if luauOk ~= 0 and luauOk ~= true then
            _G.display("Luau compiler not found or failed! Falling back to luac5.1...", "yellow")
            _G.display("(Install luau from https://github.com/luau-lang/luau/releases)", "yellow")
            settings.LuauMode = false
            local ok51 = os.execute("luac5.1 -o Input/luac.out " .. inputFile)
            if ok51 ~= 0 and ok51 ~= true then
                _G.display("luac5.1 compilation also failed!", "red")
                restoreInput(inputFile, savedInput)
                return
            end
        end
    else
        -- Default: Lua 5.1
        _G.display("Compiling to Lua 5.1 bytecode...", "green")
        local ok = os.execute("luac5.1 -o Input/luac.out " .. inputFile)
        if ok ~= 0 and ok ~= true then
            _G.display("luac compilation failed!", "red")
            restoreInput(inputFile, savedInput)
            return
        end
    end

    bytecode = _G.readFile("Input/luac.out")
    if not bytecode or #bytecode == 0 then
        _G.display("Compiler produced no output! Check your input file.", "red")
        restoreInput(inputFile, savedInput)
        return
    end

    _G.display("Parsing bytecode...", "green")
    local parsed = parser(bytecode)

    _G.display("Generating VM tree...", "green")
    local vmTree = treeGenerator(parsed):gsub(":INSERTENVLOG:", antiEnvLogger)

    if settings.LuauMode or settings.LuaUCompatibility then
        _G.display("Applying Roblox compatibility fixes...", "yellow")
        vmTree = vmTree:gsub("os%.time%(%)", "tick and tick() or 0")
        vmTree = vmTree:gsub("_ENV or getfenv%(%)", "_ENV")
        vmTree = vmTree:gsub("getfenv%(%)", "_ENV")
    end

    if settings.Minify then
        _G.display("Minifying output...", "green")
        local ok2, result = pcall(function()
            return minifier.Minify(vmTree, {
                RenameVariables = true,
                RenameGlobals   = true,
            })
        end)
        if ok2 and result and #result > 0 then
            vmTree = result
            _G.display("Minification successful.", "green")
        else
            _G.display("Minification skipped (complex output).", "yellow")
            if not ok2 then
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
