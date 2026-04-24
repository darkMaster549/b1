-- You cannot directly edit these and you must use flags in Main.lua to change these settings

return {
	["ConstantProtection"] = false,						-- Encrypts constants for stronger constant security
	["EncryptStrings"] = false, 						-- Encrypts strings in output for stronger security
	["AntiTamper"] = false,								-- Injects anti-tamper checks to detect script modification
	["ControlFlowFlattening"] = false,					-- Flattens control flow for simple obfuscation hardening
	--
	["Debug"] = false,									-- Enables debug tools to help debug errors
	["Minify"] = false, 								-- Minifies the output for smaller size
    ["Watermark"] = "Hebrew", 	-- Input any watermark you want here
	["LuaUCompatibility"] = false,						-- Removes Luau specific syntax to make it compatible with Lua 5.1 compiler
	["LuauMode"] = false,								-- Use Luau 80+ opcode set instead of Lua 5.1 38 opcodes
}
