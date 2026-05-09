-- You cannot directly edit these and you must use flags in Main.lua to change these settings
-- Two of Flaggs Have Bugs and might not work.
return {
	["ConstantProtection"]    = false,  -- Encrypts constants for stronger constant security
	["EncryptStrings"]        = false,  -- Encrypts strings in output for stronger security
	["AntiTamper"]            = false,  -- Injects anti-tamper checks to detect script modification
	["ControlFlowFlattening"] = false,  -- Flattens control flow for simple obfuscation hardening
	["NumberToExpressions"]   = false,  -- Replaces integer literals with equivalent math expressions
	["BlockShuffle"]          = false,  -- Assigns mangled IDs to blocks, shuffles them, dispatch table
	--
	["Debug"]                 = false,  -- Enables debug tools to help debug errors
	["Minify"]                = false,  -- Minifies the output for smaller size
	["Watermark"]             = "Hebrew",  -- Input any watermark you want here
	["LuaUCompatibility"]     = false,  -- Removes Luau specific syntax to make it compatible with Lua 5.1 compiler
	["LuauMode"]              = false,  -- Use Luau 80+ opcode set instead of Lua 5.1 38 opcodes
	--
	-- IronBrew passes
	["IBPasses"]              = true,   -- master toggle for all IB passes
	["IBBounce"]              = false,   -- JMP chaining
	["IBTestFlip"]            = false,   -- flip EQ/LT/LE/TEST A register randomly
	["IBEqMutate"]            = false,  -- expand EQ -> LT+JMP+LE+JMP+JMP (heavy)
	["IBTestSpam"]            = false,  -- recursive branch duplication (very heavy)
	["IBTestSpamDepth"]       = 2,      -- recursion depth (IB uses 3, keep at 2 for sanity)
}
