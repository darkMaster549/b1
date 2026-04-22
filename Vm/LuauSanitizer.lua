-- Convert all Luau-specific syntax to standard Lua
local Sanitizer = {}

local TOKEN_TYPES = {
	WHITESPACE = "whitespace",
	COMMENT = "comment",
	STRING = "string",
	INTERPOLATED_STRING = "interpolated_string",
	NUMBER = "number",
	IDENTIFIER = "identifier",
	KEYWORD = "keyword",
	OPERATOR = "operator",
	COMPOUND_ASSIGN = "compound_assign",
	SYMBOL = "symbol",
	VARARG = "vararg",
	EOF = "eof"
}

local KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	["type"] = true,
	["export"] = true
}

local function isAlpha(c)
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end

local function isDigit(c)
	return c >= "0" and c <= "9"
end

local function isAlphaNum(c)
	return isAlpha(c) or isDigit(c)
end

local function isWhitespace(c)
	return c == " " or c == "\t" or c == "\n" or c == "\r"
end

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new(source)
	local self = setmetatable({}, Lexer)
	self.source = source
	self.pos = 1
	self.tokens = {}
	return self
end

function Lexer:peek(offset)
	offset = offset or 0
	local pos = self.pos + offset
	if pos > #self.source then
		return "\0"
	end
	return self.source:sub(pos, pos)
end

function Lexer:advance(count)
	count = count or 1
	self.pos = self.pos + count
end

function Lexer:readWhile(predicate)
	local start = self.pos
	while self.pos <= #self.source and predicate(self:peek()) do
		self:advance()
	end
	return self.source:sub(start, self.pos - 1)
end

function Lexer:skipWhitespace()
	local start = self.pos
	while self.pos <= #self.source and isWhitespace(self:peek()) do
		self:advance()
	end
	if self.pos > start then
		return {
			type = TOKEN_TYPES.WHITESPACE,
			value = self.source:sub(start, self.pos - 1)
		}
	end
	return nil
end

function Lexer:readString(quote)
	local start = self.pos
	self:advance()
	while self.pos <= #self.source do
		local c = self:peek()
		if c == "\\" then
			self:advance(2)
		elseif c == quote then
			self:advance()
			break
		else
			self:advance()
		end
	end
	return {
		type = TOKEN_TYPES.STRING,
		value = self.source:sub(start, self.pos - 1)
	}
end

function Lexer:readLongString()
	local start = self.pos
	self:advance()
	local eqCount = 0
	while self:peek() == "=" do
		eqCount = eqCount + 1
		self:advance()
	end
	if self:peek() ~= "[" then
		return {
			type = TOKEN_TYPES.SYMBOL,
			value = "["
		}
	end
	self:advance()
	local closePattern = "]" .. string.rep("=", eqCount) .. "]"
	while self.pos <= #self.source do
		if self.source:sub(self.pos, self.pos + #closePattern - 1) == closePattern then
			self:advance(#closePattern)
			break
		end
		self:advance()
	end
	return {
		type = TOKEN_TYPES.STRING,
		value = self.source:sub(start, self.pos - 1)
	}
end

function Lexer:readComment()
	local start = self.pos
	self:advance(2)
	if self:peek() == "[" then
		local eqStart = self.pos
		self:advance()
		local eqCount = 0
		while self:peek() == "=" do
			eqCount = eqCount + 1
			self:advance()
		end
		if self:peek() == "[" then
			self:advance()
			local closePattern = "]" .. string.rep("=", eqCount) .. "]"
			while self.pos <= #self.source do
				if self.source:sub(self.pos, self.pos + #closePattern - 1) == closePattern then
					self:advance(#closePattern)
					break
				end
				self:advance()
			end
			return {
				type = TOKEN_TYPES.COMMENT,
				value = self.source:sub(start, self.pos - 1)
			}
		else
			self.pos = eqStart
		end
	end
	while self.pos <= #self.source and self:peek() ~= "\n" do
		self:advance()
	end
	return {
		type = TOKEN_TYPES.COMMENT,
		value = self.source:sub(start, self.pos - 1)
	}
end

function Lexer:readInterpolatedString()
	local start = self.pos
	self:advance()
	while self.pos <= #self.source and self:peek() ~= "`" do
		if self:peek() == "\\" then
			self:advance(2)
		else
			self:advance()
		end
	end
	self:advance()
	return {
		type = TOKEN_TYPES.INTERPOLATED_STRING,
		value = self.source:sub(start, self.pos - 1)
	}
end

function Lexer:readNumber()
	local start = self.pos
	if self:peek() == "0" and (self:peek(1) == "x" or self:peek(1) == "X") then
		self:advance(2)
		self:readWhile(function(c)
			return isDigit(c) or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		end)
	else
		self:readWhile(isDigit)
		if self:peek() == "." and isDigit(self:peek(1)) then
			self:advance()
			self:readWhile(isDigit)
		end
		if self:peek() == "e" or self:peek() == "E" then
			self:advance()
			if self:peek() == "+" or self:peek() == "-" then
				self:advance()
			end
			self:readWhile(isDigit)
		end
	end
	return {
		type = TOKEN_TYPES.NUMBER,
		value = self.source:sub(start, self.pos - 1)
	}
end

function Lexer:readIdentifier()
	local start = self.pos
	self:readWhile(isAlphaNum)
	local value = self.source:sub(start, self.pos - 1)
	local tokenType = KEYWORDS[value] and TOKEN_TYPES.KEYWORD or TOKEN_TYPES.IDENTIFIER
	return {
		type = tokenType,
		value = value
	}
end

function Lexer:tokenize()
	while self.pos <= #self.source do
		local c = self:peek()
		local c2 = self.source:sub(self.pos, self.pos + 1)
		local c3 = self.source:sub(self.pos, self.pos + 2)
		if isWhitespace(c) then
			table.insert(self.tokens, self:skipWhitespace())
		elseif c2 == "--" then
			table.insert(self.tokens, self:readComment())
		elseif c == '"' or c == "'" then
			table.insert(self.tokens, self:readString(c))
		elseif c == "[" and (self:peek(1) == "[" or self:peek(1) == "=") then
			table.insert(self.tokens, self:readLongString())
		elseif c == "`" then
			table.insert(self.tokens, self:readInterpolatedString())
		elseif isDigit(c) or (c == "." and isDigit(self:peek(1))) then
			table.insert(self.tokens, self:readNumber())
		elseif isAlpha(c) then
			table.insert(self.tokens, self:readIdentifier())
		elseif c3 == "..." then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.VARARG,
				value = "..."
			})
			self:advance(3)
		elseif c3 == "..=" then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.COMPOUND_ASSIGN,
				value = "..="
			})
			self:advance(3)
		elseif c3 == "//=" then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.COMPOUND_ASSIGN,
				value = "//="
			})
			self:advance(3)
		elseif c2 == "+=" or c2 == "-=" or c2 == "*=" or c2 == "/=" or c2 == "%=" or c2 == "^=" then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.COMPOUND_ASSIGN,
				value = c2
			})
			self:advance(2)
		elseif c2 == "//" then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.OPERATOR,
				value = c2
			})
			self:advance(2)
		elseif c2 == "->" or c2 == "::" or c2 == "==" or c2 == "~=" or c2 == "<=" or c2 == ">=" or c2 == ".." then
			table.insert(self.tokens, {
				type = TOKEN_TYPES.OPERATOR,
				value = c2
			})
			self:advance(2)
		else
			table.insert(self.tokens, {
				type = TOKEN_TYPES.SYMBOL,
				value = c
			})
			self:advance()
		end
	end
	table.insert(self.tokens, {
		type = TOKEN_TYPES.EOF,
		value = ""
	})
	return self.tokens
end

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
	local self = setmetatable({}, Parser)
	self.tokens = tokens
	self.pos = 1
	self.output = {}
	return self
end

function Parser:peek(offset)
	offset = offset or 0
	local pos = self.pos + offset
	if pos > #self.tokens then
		return self.tokens[#self.tokens]
	end
	return self.tokens[pos]
end

function Parser:current()
	return self:peek(0)
end

function Parser:advance()
	local token = self.tokens[self.pos]
	self.pos = self.pos + 1
	return token
end

function Parser:emit(value)
	table.insert(self.output, value)
end

function Parser:emitToken(token)
	if token then
		table.insert(self.output, token.value)
	end
end

function Parser:skipNonCode()
	while self:current().type == TOKEN_TYPES.WHITESPACE or self:current().type == TOKEN_TYPES.COMMENT do
		self:emitToken(self:advance())
	end
end

function Parser:peekNonWhitespace(offset)
	offset = offset or 0
	local pos = self.pos
	local count = 0
	while pos <= #self.tokens do
		local t = self.tokens[pos]
		if t.type ~= TOKEN_TYPES.WHITESPACE and t.type ~= TOKEN_TYPES.COMMENT then
			if count == offset then
				return t
			end
			count = count + 1
		end
		pos = pos + 1
	end
	return self.tokens[#self.tokens]
end

function Parser:skipTypeAnnotation()
	local depth = 0
	while self:current().type ~= TOKEN_TYPES.EOF do
		local t = self:current()
		if t.type == TOKEN_TYPES.WHITESPACE then
			self:advance()
		elseif t.value == "<" or t.value == "(" or t.value == "{" then
			depth = depth + 1
			self:advance()
		elseif t.value == ">" or t.value == ")" or t.value == "}" then
			if depth > 0 then
				depth = depth - 1
				self:advance()
			else
				break
			end
		elseif (t.value == "," or t.value == "=" or t.value == ";") and depth == 0 then
			break
		elseif t.type == TOKEN_TYPES.IDENTIFIER or t.type == TOKEN_TYPES.KEYWORD or
               t.value == "|" or t.value == "&" or t.value == "?" or t.value == "." or
               t.value == ":" or t.value == "[" or t.value == "]" or t.type == TOKEN_TYPES.VARARG or
               t.type == TOKEN_TYPES.NUMBER or t.type == TOKEN_TYPES.STRING then
			self:advance()
		elseif t.value == "-" and self:peekNonWhitespace(1).value == ">" then
			self:advance()
			while self:current().type == TOKEN_TYPES.WHITESPACE do
				self:advance()
			end
			self:advance()
		else
			break
		end
	end
end

function Parser:parseTypeDeclaration()
	while self:current().type ~= TOKEN_TYPES.EOF do
		local t = self:current()
		if t.type == TOKEN_TYPES.WHITESPACE and t.value:find("\n") then
			self:advance()
			break
		elseif t.type == TOKEN_TYPES.EOF then
			break
		else
			self:advance()
		end
	end
end

function Parser:parseFunctionParams()
	self:emit("(")
	self:advance()
	local first = true
	while self:current().type ~= TOKEN_TYPES.EOF and self:current().value ~= ")" do
		local t = self:current()
		if t.type == TOKEN_TYPES.WHITESPACE then
			self:emitToken(self:advance())
		elseif t.value == "," then
			self:emitToken(self:advance())
			first = false
		elseif t.type == TOKEN_TYPES.IDENTIFIER or t.type == TOKEN_TYPES.VARARG then
			self:emitToken(self:advance())
			while self:current().type == TOKEN_TYPES.WHITESPACE do
				self:emitToken(self:advance())
			end
			if self:current().value == ":" then
				self:advance()
				self:skipTypeAnnotation()
			end
		else
			self:emitToken(self:advance())
		end
	end

	if self:current().value == ")" then
		self:emit(")")
		self:advance()
	end

	while self:current().type == TOKEN_TYPES.WHITESPACE do
		self:emitToken(self:advance())
	end

	if self:current().value == ":" then
		self:advance()
		self:skipTypeAnnotation()
	elseif self:current().value == "-" and self:peekNonWhitespace(1).value == ">" then
		self:advance()
		while self:current().type == TOKEN_TYPES.WHITESPACE do
			self:advance()
		end
		self:advance()
		self:skipTypeAnnotation()
	end
end

function Parser:parseInterpolatedString(token)
	local content = token.value:sub(2, #token.value - 1)
	local parts = {}
	local pos = 1
	local currentStr = ""

	while pos <= #content do
		local c = content:sub(pos, pos)
		if c == "\\" and pos + 1 <= #content then
			currentStr = currentStr .. content:sub(pos + 1, pos + 1)
			pos = pos + 2
		elseif c == "{" then
			if currentStr ~= "" then
				table.insert(parts, {
					type = "str",
					value = currentStr
				})
				currentStr = ""
			end
			local braceDepth = 1
			local exprStart = pos + 1
			pos = pos + 1
			while pos <= #content and braceDepth > 0 do
				if content:sub(pos, pos) == "{" then
					braceDepth = braceDepth + 1
				elseif content:sub(pos, pos) == "}" then
					braceDepth = braceDepth - 1
				end
				pos = pos + 1
			end
			local expr = content:sub(exprStart, pos - 2)
			table.insert(parts, {
				type = "expr",
				value = expr
			})
		else
			currentStr = currentStr .. c
			pos = pos + 1
		end
	end

	if currentStr ~= "" then
		table.insert(parts, {
			type = "str",
			value = currentStr
		})
	end

	if #parts == 0 then
		self:emit('""')
	elseif #parts == 1 and parts[1].type == "str" then
		self:emit('"' .. parts[1].value .. '"')
	else
		self:emit("(")
		for j, part in ipairs(parts) do
			if j > 1 then
				self:emit(" .. ")
			end
			if part.type == "str" then
				self:emit('"' .. part.value .. '"')
			else
				self:emit("tostring(" .. part.value .. ")")
			end
		end
		self:emit(")")
	end
end

function Parser:collectVariable()
	local varTokens = {}
	local wsTokens = {}
	local i = #self.output
	local parenDepth = 0
	local bracketDepth = 0

	while i >= 1 do
		local val = self.output[i]
		if val:match("^%s+$") then
			table.insert(wsTokens, 1, val)
			self.output[i] = nil
			i = i - 1
		elseif val == ")" then
			wsTokens = {}
			parenDepth = parenDepth + 1
			table.insert(varTokens, 1, val)
			self.output[i] = nil
			i = i - 1
		elseif val == "(" then
			if parenDepth > 0 then
				wsTokens = {}
				parenDepth = parenDepth - 1
				table.insert(varTokens, 1, val)
				self.output[i] = nil
				i = i - 1
			else
				for _, ws in ipairs(wsTokens) do
					table.insert(self.output, ws)
				end
				break
			end
		elseif val == "]" then
			wsTokens = {}
			bracketDepth = bracketDepth + 1
			table.insert(varTokens, 1, val)
			self.output[i] = nil
			i = i - 1
		elseif val == "[" then
			if bracketDepth > 0 then
				wsTokens = {}
				bracketDepth = bracketDepth - 1
				table.insert(varTokens, 1, val)
				self.output[i] = nil
				i = i - 1
			else
				for _, ws in ipairs(wsTokens) do
					table.insert(self.output, ws)
				end
				break
			end
		elseif val:match("^[%a_][%w_]*$") or val == "." or val == ":" then
			wsTokens = {}
			table.insert(varTokens, 1, val)
			self.output[i] = nil
			i = i - 1
		else
			for _, ws in ipairs(wsTokens) do
				table.insert(self.output, ws)
			end
			break
		end
	end

	while #self.output > 0 and self.output[#self.output] == nil do
		table.remove(self.output)
	end

	return table.concat(varTokens)
end

function Parser:parse()
	while self:current().type ~= TOKEN_TYPES.EOF do
		local t = self:current()
		repeat
			if t.type == TOKEN_TYPES.KEYWORD and (t.value == "type" or t.value == "export") then
				local isExport = t.value == "export"
				self:advance()
				if isExport then
					while self:current().type == TOKEN_TYPES.WHITESPACE do
						self:advance()
					end
					if self:current().value ~= "type" then
						self:emit("export")
						break
					end
					self:advance()
				end

				while self:current().type == TOKEN_TYPES.WHITESPACE do
					self:advance()
				end

				if self:current().type == TOKEN_TYPES.IDENTIFIER then
					local nextNonWs = self:peekNonWhitespace(1)
					if nextNonWs.value == "=" or nextNonWs.value == "<" then
						self:parseTypeDeclaration()
						break
					end
				end

				self:emit("type")
			elseif t.type == TOKEN_TYPES.KEYWORD and t.value == "function" then
				self:emitToken(self:advance())

				while self:current().type == TOKEN_TYPES.WHITESPACE do
					self:emitToken(self:advance())
				end

				while self:current().type == TOKEN_TYPES.IDENTIFIER or
                      self:current().value == "." or self:current().value == ":" do
					self:emitToken(self:advance())
				end

				while self:current().type == TOKEN_TYPES.WHITESPACE do
					self:emitToken(self:advance())
				end

				if self:current().value == "<" then
					local depth = 1
					self:advance()
					while depth > 0 and self:current().type ~= TOKEN_TYPES.EOF do
						if self:current().value == "<" then
							depth = depth + 1
						end
						if self:current().value == ">" then
							depth = depth - 1
						end
						self:advance()
					end
					while self:current().type == TOKEN_TYPES.WHITESPACE do
						self:emitToken(self:advance())
					end
				end

				if self:current().value == "(" then
					self:parseFunctionParams()
				end

			elseif t.type == TOKEN_TYPES.KEYWORD and t.value == "local" then
				self:emitToken(self:advance())
				while self:current().type == TOKEN_TYPES.WHITESPACE do
					self:emitToken(self:advance())
				end

				if self:current().value == "function" then
					break
				end

				while self:current().type == TOKEN_TYPES.IDENTIFIER do
					self:emitToken(self:advance())
					while self:current().type == TOKEN_TYPES.WHITESPACE do
						self:emitToken(self:advance())
					end
					if self:current().value == ":" then
						self:advance()
						self:skipTypeAnnotation()
					end
					while self:current().type == TOKEN_TYPES.WHITESPACE do
						self:emitToken(self:advance())
					end
					if self:current().value == "," then
						self:emitToken(self:advance())
						while self:current().type == TOKEN_TYPES.WHITESPACE do
							self:emitToken(self:advance())
						end
					else
						break
					end
				end
			elseif t.type == TOKEN_TYPES.COMPOUND_ASSIGN then
				local op = t.value:sub(1, #t.value - 1)
				if op == "//" then
					op = "math.floor(a/b)"
				end
				local varStr = self:collectVariable()
				if varStr == "" then
					self:emit(t.value)
					self:advance()
				else
					if t.value == "//=" then
						self:emit(varStr)
						self:emit(" = math.floor(")
						self:emit(varStr)
						self:emit(" / ")
						self:advance()
						while self:current().type == TOKEN_TYPES.WHITESPACE do
							self:advance()
						end
						local depth = 0
						while self:current().type ~= TOKEN_TYPES.EOF do
							local curr = self:current()
							if curr.value == "(" or curr.value == "[" or curr.value == "{" then
								depth = depth + 1
								self:emitToken(self:advance())
							elseif curr.value == ")" or curr.value == "]" or curr.value == "}" then
								if depth > 0 then
									depth = depth - 1
									self:emitToken(self:advance())
								else
									break
								end
							elseif depth == 0 and (curr.type == TOKEN_TYPES.WHITESPACE and curr.value:find("\n")) then
								break
							elseif depth == 0 and (curr.value == ";" or curr.value == ",") then
								break
							elseif curr.type == TOKEN_TYPES.KEYWORD and
								   (curr.value == "then" or curr.value == "do" or curr.value == "end" or
								    curr.value == "else" or curr.value == "elseif" or curr.value == "local" or
								    curr.value == "return" or curr.value == "if" or curr.value == "while" or
								    curr.value == "for" or curr.value == "function" or curr.value == "repeat") then
								break
							else
								self:emitToken(self:advance())
							end
						end
						self:emit(")")
					else
						self:emit(varStr)
						self:emit(" = ")
						self:emit(varStr)
						self:emit(" " .. op .. " ")
						self:advance()
					end
				end
			elseif t.type == TOKEN_TYPES.INTERPOLATED_STRING then
				self:parseInterpolatedString(t)
				self:advance()
			elseif t.value == "(" then
				local prevIdx = #self.output
				while prevIdx >= 1 and self.output[prevIdx]:match("^%s+$") do
					prevIdx = prevIdx - 1
				end
				if prevIdx >= 1 and self.output[prevIdx] == "function" then
					self:parseFunctionParams()
				else
					self:emitToken(self:advance())
				end
			else
				self:emitToken(self:advance())
			end
		until true
	end
	return table.concat(self.output)
end

-- Transform `continue` into Lua 5.1 compatible repeat...until true + break.
-- Strategy: wrap each loop body in `repeat ... until true`, then
-- replace `continue` with `break` (which breaks the inner repeat,
-- continuing the outer loop).
--
-- Input:
--   for i, v in ipairs(t) do
--       if v == "x" then continue end
--       print(v)
--   end
--
-- Output:
--   for i, v in ipairs(t) do repeat
--       if v == "x" then break end
--       print(v)
--   until true end
--
local function transformContinue(src)
	-- First pass: tokenize into {kind, value} pairs.
	-- kind = "kw" | "ws" | "other"
	local tokens = {}
	local i = 1
	local n = #src

	while i <= n do
		local c = src:sub(i, i)

		-- comments
		if c == "-" and src:sub(i, i+1) == "--" then
			local j = i + 2
			if src:sub(j, j) == "[" then
				local eqStart = j + 1
				local eqs = src:match("^=*", eqStart)
				local eqCount = #eqs
				local closeStart = eqStart + eqCount
				if src:sub(closeStart, closeStart) == "[" then
					local closePattern = "]" .. string.rep("=", eqCount) .. "]"
					local closePos = src:find(closePattern, closeStart + 1, true)
					if closePos then
						table.insert(tokens, {"other", src:sub(i, closePos + #closePattern - 1)})
						i = closePos + #closePattern
					else
						table.insert(tokens, {"other", src:sub(i)})
						i = n + 1
					end
				else
					local eol = src:find("\n", j) or n
					table.insert(tokens, {"other", src:sub(i, eol)})
					i = eol + 1
				end
			else
				local eol = src:find("\n", i+2) or n
				table.insert(tokens, {"other", src:sub(i, eol)})
				i = eol + 1
			end

		-- long strings
		elseif c == "[" then
			local eqStart = i + 1
			local eqs = src:match("^=*", eqStart)
			local eqCount = #eqs
			local closeStart = eqStart + eqCount
			if src:sub(closeStart, closeStart) == "[" then
				local closePattern = "]" .. string.rep("=", eqCount) .. "]"
				local closePos = src:find(closePattern, closeStart + 1, true)
				if closePos then
					table.insert(tokens, {"other", src:sub(i, closePos + #closePattern - 1)})
					i = closePos + #closePattern
				else
					table.insert(tokens, {"other", c})
					i = i + 1
				end
			else
				table.insert(tokens, {"other", c})
				i = i + 1
			end

		-- short strings
		elseif c == '"' or c == "'" then
			local del = c
			local j = i + 1
			while j <= n do
				local ch = src:sub(j, j)
				if ch == "\\" then j = j + 2
				elseif ch == del then j = j + 1; break
				elseif ch == "\n" or ch == "\r" then break
				else j = j + 1 end
			end
			table.insert(tokens, {"other", src:sub(i, j - 1)})
			i = j

		-- identifiers / keywords
		elseif c:match("[%a_]") then
			local word = src:match("^[%a_][%w_]*", i)
			local kwset = {
				["and"]=true, ["break"]=true, ["continue"]=true, ["do"]=true,
				["else"]=true, ["elseif"]=true, ["end"]=true, ["false"]=true,
				["for"]=true, ["function"]=true, ["goto"]=true, ["if"]=true,
				["in"]=true, ["local"]=true, ["nil"]=true, ["not"]=true,
				["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true,
				["true"]=true, ["until"]=true, ["while"]=true,
			}
			if kwset[word] then
				table.insert(tokens, {"kw", word})
			else
				table.insert(tokens, {"name", word})
			end
			i = i + #word

		-- numbers
		elseif c:match("%d") or (c == "." and src:sub(i+1,i+1):match("%d")) then
			local num = src:match("^[%d%.]+[eE]?[%+%-]?[%d_a-fA-FxX]*", i)
			table.insert(tokens, {"other", num})
			i = i + #num

		-- whitespace
		elseif c:match("%s") then
			local ws = src:match("^%s+", i)
			table.insert(tokens, {"ws", ws})
			i = i + #ws

		else
			table.insert(tokens, {"other", c})
			i = i + 1
		end
	end

	-- Second pass: walk tokens tracking loop nesting.
	-- When we enter a for/while loop body (after `do`), inject `repeat`.
	-- When we exit that loop body (at its matching `end`), inject `until true`.
	-- Replace `continue` with `break` inside loops.
	-- For `repeat...until` loops, same wrapping but before `until`.
	--
	-- Stack entries:
	--   kind = "for_while" | "repeat_loop" | "func" | "if" | "other"
	--   needsWrap = true if we injected a repeat inside this loop
	--   doSeen = true once we've passed the `do` keyword for for/while

	local stack = {}
	local out = {}

	local function push(kind)
		table.insert(stack, {kind=kind, needsWrap=false, doSeen=false})
	end

	local function pop()
		return table.remove(stack)
	end

	local function topLoop()
		for j = #stack, 1, -1 do
			local e = stack[j]
			if e.kind == "for_while" or e.kind == "repeat_loop" then
				return e
			end
			if e.kind == "func" then return nil end
		end
		return nil
	end

	-- Check if any loop in scope has a continue (needs wrapping).
	-- We do a pre-scan to find which loops contain `continue`.
	-- Simpler: just always wrap loops that contain continue.
	-- We'll do a quick pre-scan first.

	local loopsWithContinue = {}
	do
		local stk = {}
		local loopId = 0
		local idStack = {}
		for _, tok in ipairs(tokens) do
			if tok[1] == "kw" then
				local v = tok[2]
				if v == "for" or v == "while" then
					loopId = loopId + 1
					table.insert(stk, {kind="for_while", id=loopId, doSeen=false})
					table.insert(idStack, loopId)
				elseif v == "repeat" then
					loopId = loopId + 1
					table.insert(stk, {kind="repeat_loop", id=loopId})
					table.insert(idStack, loopId)
				elseif v == "function" then
					table.insert(stk, {kind="func"})
					table.insert(idStack, 0)
				elseif v == "do" then
					local top = stk[#stk]
					if top and top.kind == "for_while" and not top.doSeen then
						top.doSeen = true
					else
						table.insert(stk, {kind="other"})
						table.insert(idStack, 0)
					end
				elseif v == "if" then
					table.insert(stk, {kind="if"})
					table.insert(idStack, 0)
				elseif v == "end" then
					table.remove(stk)
					table.remove(idStack)
				elseif v == "until" then
					local top = stk[#stk]
					if top and top.kind == "repeat_loop" then
						table.remove(stk)
						table.remove(idStack)
					end
				elseif v == "continue" then
					-- find innermost loop id
					for j = #stk, 1, -1 do
						local e = stk[j]
						if e.kind == "for_while" or e.kind == "repeat_loop" then
							loopsWithContinue[e.id] = true
							break
						end
						if e.kind == "func" then break end
					end
				end
			end
		end
	end

	-- Now do the actual transform pass.
	-- For loops that have continue: wrap body in repeat...until true,
	-- replace continue with break.
	local stk2 = {}
	local loopId2 = 0

	local function push2(kind, id)
		table.insert(stk2, {kind=kind, id=id, doSeen=false, wrapped=false})
	end

	local function pop2()
		return table.remove(stk2)
	end

	local function topLoop2()
		for j = #stk2, 1, -1 do
			local e = stk2[j]
			if e.kind == "for_while" or e.kind == "repeat_loop" then
				return e
			end
			if e.kind == "func" then return nil end
		end
		return nil
	end

	local ti = 1
	while ti <= #tokens do
		local tok = tokens[ti]
		ti = ti + 1

		if tok[1] ~= "kw" then
			table.insert(out, tok[2])
		else
			local v = tok[2]

			if v == "for" or v == "while" then
				loopId2 = loopId2 + 1
				push2("for_while", loopId2)
				table.insert(out, v)

			elseif v == "repeat" then
				loopId2 = loopId2 + 1
				local id = loopId2
				push2("repeat_loop", id)
				table.insert(out, v)
				-- if this repeat loop has continue, inject inner repeat after `repeat`
				if loopsWithContinue[id] then
					stk2[#stk2].wrapped = true
					table.insert(out, " repeat")
				end

			elseif v == "function" then
				push2("func", 0)
				table.insert(out, v)

			elseif v == "do" then
				local top = stk2[#stk2]
				if top and top.kind == "for_while" and not top.doSeen then
					top.doSeen = true
					table.insert(out, v)
					-- inject `repeat` right after `do` if this loop has continue
					if loopsWithContinue[top.id] then
						top.wrapped = true
						table.insert(out, " repeat")
					end
				else
					push2("other", 0)
					table.insert(out, v)
				end

			elseif v == "if" then
				push2("if", 0)
				table.insert(out, v)

			elseif v == "end" then
				local top = pop2()
				if top and top.kind == "for_while" and top.wrapped then
					-- close the inner repeat before the loop's end
					table.insert(out, " until true ")
				end
				table.insert(out, v)

			elseif v == "until" then
				local top = stk2[#stk2]
				if top and top.kind == "repeat_loop" then
					if top.wrapped then
						-- close inner repeat before outer until
						table.insert(out, " until true ")
					end
					pop2()
				end
				table.insert(out, v)

			elseif v == "continue" then
				local loop = topLoop2()
				if loop and loop.wrapped then
					-- break out of the inner repeat, continuing the outer loop
					table.insert(out, "break")
				else
					-- loop has no continue (shouldn't reach here) emit as-is
					table.insert(out, v)
				end

			else
				table.insert(out, v)
			end
		end
	end

	return table.concat(out)
end

function Sanitizer.sanitize(code)
	local lexer = Lexer.new(code)
	local tokens = lexer:tokenize()
	local parser = Parser.new(tokens)
	local sanitized = parser:parse()
	sanitized = transformContinue(sanitized)
	return sanitized
end

return Sanitizer
