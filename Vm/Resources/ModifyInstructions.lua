-- ModifyInstructions.lua
-- Original pass + IronBrew passes (Bounce, TestFlip, EqMutate, TestSpam)

return function(instructions, constants, prototypes)
	local settings = require("Input.Settings")

	-- ==================== PSEUDO / CLOSURE UPVAL FIX ====================
	for i, inst in ipairs(instructions) do
		if inst.OpcodeName == "CLOSURE" then
			local protoIndex = _G.getReg(inst, "B")
			local proto = prototypes[protoIndex + 1]
			if proto and proto.NumUpvalues > 0 then
				for i2 = 1, proto.NumUpvalues do
					local pseudoInst = instructions[i + i2]
					if pseudoInst then
						if pseudoInst.OpcodeName == "GETUPVAL" or pseudoInst.Opcode == 4 then
							pseudoInst.C = 1
						else
							pseudoInst.C = 0
						end
						pseudoInst.OpcodeName = "PSEUDO"
						pseudoInst.Opcode = -1
					end
				end
			end
		end
	end

	-- ==================== MACRO TRANSFORM ====================
	for i, inst in ipairs(instructions) do
		if inst.OpcodeName == "GETGLOBAL" then
			local registerB = _G.getReg(inst, "B") + 1
			local constant = constants[registerB]
			if constant then
				constant = constant.Value
				local opcodeExists = pcall(require, "Vm.OpCodes." .. tostring(constant))
				if constant and opcodeExists then
					local callOpcode = instructions[i + 1]
					if callOpcode and callOpcode.OpcodeName == "CALL" then
						local callingIndex = instructions[inst.Index + 1]
						if callingIndex and callingIndex.OpcodeName == "CALL" and callingIndex.A == inst.A then
							local customInstruction = require("Vm.OpCodes." .. tostring(constant))("custom", callOpcode)
							instructions[i + 1] = customInstruction
							constants[tonumber(_G.getReg(inst, "B") + 1)] = {
								["Index"] = 0,
								["Type"]  = "string",
								["Value"] = tostring(math.random(10000, 30000))
							}
							instructions[i] = {
								OpcodeName = "INVALID",
								Opcode     = "INVALID",
							}
						end
					end
				end
			end
		end
	end

	-- ==================== IB PASSES ====================
	if settings.IBPasses then
		local ok, IBPasses = pcall(require, "Vm.Resources.IBPasses")
		if not ok then
			_G.display("--> IBPasses not found, skipping", "yellow")
		else
			-- Bounce: JMP chaining
			if settings.IBBounce then
				_G.display("--> IB Pass: Bounce", "yellow")
				instructions = IBPasses.Bounce(instructions)
			end

			-- TestFlip: randomly flip EQ/LT/LE/TEST A register
			if settings.IBTestFlip then
				_G.display("--> IB Pass: TestFlip", "yellow")
				instructions = IBPasses.TestFlip(instructions)
			end

			-- EqMutate: expand EQ into LT+JMP+LE+JMP+JMP
			if settings.IBEqMutate then
				_G.display("--> IB Pass: EqMutate", "yellow")
				instructions = IBPasses.EqMutate(instructions)
			end

			-- TestSpam: recursive branch tree duplication
			if settings.IBTestSpam then
				local spamDepth = settings.IBTestSpamDepth or 2
				_G.display("--> IB Pass: TestSpam (depth=" .. spamDepth .. ")", "yellow")
				instructions = IBPasses.TestSpam(instructions, spamDepth)
			end
		end
	end

	return instructions, constants
end
