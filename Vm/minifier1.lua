-- Lua Minifier written in Pure Lua --

-- [[ Writted By darkMaster549 ]] --
local WhiteChars = {[' ']=true,['\n']=true,['\t']=true,['\r']=true}

local Keywords = {
    ['and']=true,['break']=true,['do']=true,['else']=true,
    ['elseif']=true,['end']=true,['false']=true,['for']=true,
    ['function']=true,['goto']=true,['if']=true,['in']=true,
    ['local']=true,['nil']=true,['not']=true,['or']=true,
    ['repeat']=true,['return']=true,['then']=true,['true']=true,
    ['until']=true,['while']=true,['continue']=true,
}

local BlockFollowKeyword = {['else']=true,['elseif']=true,['until']=true,['end']=true}

local UnopSet = {['-']=true,['not']=true,['#']=true}

local BinopSet = {
    ['+']=true,['-']=true,['*']=true,['/']=true,['%']=true,['^']=true,['#']=true,
    ['..']=true,['.']=true,[':']=true,
    ['>']=true,['<']=true,['<=']=true,['>=']=true,['~=']=true,['==']=true,
    ['+=']=true,['-=']=true,['*=']=true,['/=']=true,['%=']=true,['^=']=true,['..=']=true,
    ['and']=true,['or']=true,
    ['~>']=true, -- Luau pipe
}

local BinaryPriority = {
    ['+']=  {6,6}, ['-']= {6,6},
    ['*']=  {7,7}, ['/']= {7,7}, ['%']= {7,7},
    ['^']=  {10,9},
    ['..']=  {5,4},
    ['==']=  {3,3}, ['~=']= {3,3},
    ['>']=  {3,3}, ['<']= {3,3}, ['>=']=  {3,3}, ['<=']=  {3,3},
    ['+=']=  {3,3}, ['-=']= {3,3}, ['*=']= {3,3}, ['/=']= {3,3},
    ['^=']=  {3,3}, ['%=']= {3,3}, ['..=']= {3,3},
    ['and']= {2,2},
    ['or']=  {1,1},
}

local UnaryPriority = 8

local Symbols = {
    ['+']=true,['-']=true,['*']=true,[')']=true,[';']=true,
    ['/']=true,['^']=true,['%']=true,['#']=true,
    [',']=true,['{']=true,['}']=true,[':']=true,
    ['[']=true,[']']=true,['(']=true,['.']=true,
}

local EqualSymbols = {['~']=true,['=']=true,['>']=true,['<']=true}
local CompoundSymbols = {['+']=true,['-']=true,['*']=true,['/']=true,['^']=true,['%']=true}
local Compounds = {['+=']=true,['-=']=true,['*=']=true,['/=']=true,['^=']=true,['%=']=true,['..=']=true}

local function isDigit(c)
    return c >= '0' and c <= '9'
end

local function isHexDigit(c)
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')
end

local function isIdentStart(c)
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
end

local function isIdent(c)
    return isIdentStart(c) or isDigit(c)
end

------------------------------------------------------------------------
-- LEXER
------------------------------------------------------------------------
local function CreateLuaTokenStream(text)
    local p = 1
    local len = #text
    local tokenBuffer = {}

    local function look(n)
        n = n or 0
        local idx = p + n
        if idx <= len then
            return text:sub(idx, idx)
        end
        return ''
    end

    local function get()
        if p <= len then
            local c = text:sub(p, p)
            p = p + 1
            return c
        end
        return ''
    end

    local function err(msg)
        error(msg, 2)
    end

    local function longdata(eqcount)
        while true do
            local c = get()
            if c == '' then
                err("Unfinished long string.")
            elseif c == ']' then
                local startp = p
                local eq = 0
                while look() == '=' do
                    p = p + 1
                    eq = eq + 1
                end
                if look() == ']' and eq == eqcount then
                    p = p + 1
                    return
                end
                p = startp
            end
        end
    end

    local function getopen()
        local startp = p
        local eq = 0
        while look() == '=' do
            p = p + 1
            eq = eq + 1
        end
        if look() == '[' then
            p = p + 1
            return eq
        else
            p = startp
            return nil
        end
    end

    local whiteStart = 1
    local tokenStart = 1

    local function token(ttype)
        local src = text:sub(tokenStart, p - 1)
        local tk = {
            Type = ttype,
            Source = src,
            LeadingWhite = text:sub(whiteStart, tokenStart - 1),
        }
        tokenBuffer[#tokenBuffer + 1] = tk
        whiteStart = p
        tokenStart = p
        return tk
    end

    while true do
        whiteStart = p
        -- skip whitespace and comments
        while true do
            local c = look()
            if c == '' then
                break
            elseif c == '-' and look(1) == '-' then
                p = p + 2
                if look() == '[' then
                    p = p + 1
                    local eq = getopen()
                    if eq ~= nil then
                        longdata(eq)
                    else
                        while true do
                            local c2 = get()
                            if c2 == '' or c2 == '\n' then break end
                        end
                    end
                else
                    while true do
                        local c2 = get()
                        if c2 == '' or c2 == '\n' then break end
                    end
                end
            elseif WhiteChars[c] then
                p = p + 1
            else
                break
            end
        end

        tokenStart = p
        local c1 = get()

        if c1 == '' then
            token('Eof')
            break
        elseif c1 == "'" or c1 == '"' then
            while true do
                local c2 = get()
                if c2 == '\\' then
                    local c3 = get()
                    if isDigit(c3) then
                        while isDigit(look()) do
                            get()
                        end
                    end
                elseif c2 == c1 then
                    break
                elseif c2 == '' then
                    err("Unfinished string!")
                end
            end
            token('String')
        elseif c1 == '[' then
            local eq = getopen()
            if eq ~= nil then
                longdata(eq)
                token('String')
            else
                token('Symbol')
            end
        elseif isIdentStart(c1) then
            while isIdent(look()) do
                p = p + 1
            end
            local word = text:sub(tokenStart, p - 1)
            if Keywords[word] then
                token('Keyword')
            else
                token('Ident')
            end
        elseif isDigit(c1) or (c1 == '.' and isDigit(look())) then
            if c1 == '0' and (look() == 'x' or look() == 'X') then
                p = p + 1
                while isHexDigit(look()) do p = p + 1 end
            elseif c1 == '0' and (look() == 'b' or look() == 'B') then
                p = p + 1
                while look() == '0' or look() == '1' do p = p + 1 end
            else
                while isDigit(look()) do p = p + 1 end
                if look() == '.' then
                    p = p + 1
                    while isDigit(look()) do p = p + 1 end
                end
                if look() == 'e' or look() == 'E' then
                    p = p + 1
                    if look() == '-' or look() == '+' then p = p + 1 end
                    while isDigit(look()) do p = p + 1 end
                end
            end
            token('Number')
        elseif c1 == '.' then
            if look() == '.' then
                p = p + 1
                if look() == '.' then
                    p = p + 1
                elseif look() == '=' then
                    p = p + 1
                end
            end
            token('Symbol')
        elseif EqualSymbols[c1] then
            if look() == '=' then p = p + 1 end
            token('Symbol')
        elseif CompoundSymbols[c1] and look() == '=' then
            p = p + 1
            token('Symbol')
        elseif Symbols[c1] then
            token('Symbol')
        else
            err("Bad symbol `" .. c1 .. "` in source.")
        end
    end

    return tokenBuffer
end

------------------------------------------------------------------------
-- PARSER
------------------------------------------------------------------------
local function CreateLuaParser(text)
    local tokens = CreateLuaTokenStream(text)
    local p = 1

    local function get()
        local tok = tokens[p]
        if p < #tokens then p = p + 1 end
        return tok
    end

    local function peek(n)
        local idx = p + (n or 0)
        return tokens[idx] or tokens[#tokens]
    end

    local function isBlockFollow()
        local tok = peek()
        return tok.Type == 'Eof' or (tok.Type == 'Keyword' and BlockFollowKeyword[tok.Source])
    end

    local function isUnop()
        return UnopSet[peek().Source] or false
    end

    local function isBinop()
        return BinopSet[peek().Source] or false
    end

    local function expect(ttype, source)
        local tk = peek()
        if tk.Type == ttype and (source == nil or tk.Source == source) then
            return get()
        else
            if source then
                error("`" .. source .. "` expected, got `" .. tk.Source .. "`", 2)
            else
                error(ttype .. " expected, got `" .. tk.Source .. "`", 2)
            end
        end
    end

    local function MkNode(node)
        return node
    end

    local block
    local expr

    local function exprlist()
        local exprList = {expr()}
        local commaList = {}
        while peek().Source == ',' do
            commaList[#commaList+1] = get()
            exprList[#exprList+1] = expr()
        end
        return exprList, commaList
    end

    local function prefixexpr()
        local tk = peek()
        if tk.Source == '(' then
            local op = get()
            local inner = expr()
            local cp = expect('Symbol', ')')
            local node = MkNode({
                Type = 'ParenExpr',
                Expression = inner,
                Token_OpenParen = op,
                Token_CloseParen = cp,
                GetFirstToken = function(self) return self.Token_OpenParen end,
                GetLastToken  = function(self) return self.Token_CloseParen end,
            })
            return node
        elseif tk.Type == 'Ident' then
            local node = MkNode({
                Type = 'VariableExpr',
                Token = get(),
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
            return node
        else
            error("Unexpected symbol: " .. tk.Type .. " `" .. tk.Source .. "`", 2)
        end
    end

    local function tableexpr()
        local obrace = expect('Symbol', '{')
        local entries = {}
        local separators = {}
        while peek().Source ~= '}' do
            local entry
            if peek().Source == '[' then
                local ob = get()
                local index = expr()
                local cb = expect('Symbol', ']')
                local eq = expect('Symbol', '=')
                local value = expr()
                entry = {
                    EntryType = 'Index',
                    Index = index,
                    Value = value,
                    Token_OpenBracket = ob,
                    Token_CloseBracket = cb,
                    Token_Equals = eq,
                }
            elseif peek().Type == 'Ident' and peek(1).Source == '=' then
                local field = get()
                local eq = get()
                local value = expr()
                entry = {
                    EntryType = 'Field',
                    Field = field,
                    Value = value,
                    Token_Equals = eq,
                }
            else
                local value = expr()
                entry = {EntryType = 'Value', Value = value}
            end
            entries[#entries+1] = entry
            if peek().Source == ',' or peek().Source == ';' then
                separators[#separators+1] = get()
            else
                break
            end
        end
        local cbrace = expect('Symbol', '}')
        local node = MkNode({
            Type = 'TableLiteral',
            EntryList = entries,
            Token_SeparatorList = separators,
            Token_OpenBrace = obrace,
            Token_CloseBrace = cbrace,
            GetFirstToken = function(self) return self.Token_OpenBrace end,
            GetLastToken  = function(self) return self.Token_CloseBrace end,
        })
        return node
    end

    local function varlist(acceptVarg)
        local varList = {}
        local commaList = {}
        if peek().Type == 'Ident' then
            varList[#varList+1] = get()
        elseif peek().Source == '...' and acceptVarg then
            return varList, commaList, get()
        end
        while peek().Source == ',' do
            commaList[#commaList+1] = get()
            if peek().Source == '...' and acceptVarg then
                return varList, commaList, get()
            else
                varList[#varList+1] = expect('Ident')
            end
        end
        return varList, commaList, nil
    end

    local function blockbody(terminator)
        local body = block()
        local after = peek()
        if after.Type == 'Keyword' and after.Source == terminator then
            return body, get()
        else
            error(terminator .. " expected, got `" .. after.Source .. "`", 2)
        end
    end

    local function functionargs()
        local tk = peek()
        if tk.Source == '(' then
            local op = get()
            local argList = {}
            local argCommaList = {}
            while peek().Source ~= ')' do
                argList[#argList+1] = expr()
                if peek().Source == ',' then
                    argCommaList[#argCommaList+1] = get()
                else
                    break
                end
            end
            local cp = expect('Symbol', ')')
            local node = MkNode({
                CallType = 'ArgCall',
                ArgList = argList,
                Token_CommaList = argCommaList,
                Token_OpenParen = op,
                Token_CloseParen = cp,
                GetFirstToken = function(self) return self.Token_OpenParen end,
                GetLastToken  = function(self) return self.Token_CloseParen end,
            })
            return node
        elseif tk.Source == '{' then
            local te = tableexpr()
            local node = MkNode({
                CallType = 'TableCall',
                TableExpr = te,
                GetFirstToken = function(self) return self.TableExpr:GetFirstToken() end,
                GetLastToken  = function(self) return self.TableExpr:GetLastToken() end,
            })
            return node
        elseif tk.Type == 'String' then
            local tok = get()
            local node = MkNode({
                CallType = 'StringCall',
                Token = tok,
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
            return node
        else
            error("Function arguments expected.", 2)
        end
    end

    local funcdecl

    local function primaryexpr()
        local base = prefixexpr()

        while true do
            local tk = peek()
            if tk.Source == '.' then
                local dotTk = get()
                local fieldName = expect('Ident')
                local node = MkNode({
                    Type = 'FieldExpr',
                    Base = base,
                    Field = fieldName,
                    Token_Dot = dotTk,
                    GetFirstToken = function(self) return self.Base:GetFirstToken() end,
                    GetLastToken  = function(self) return self.Field end,
                })
                base = node
            elseif tk.Source == ':' then
                local colonTk = get()
                local methodName = expect('Ident')
                local fargs = functionargs()
                local node = MkNode({
                    Type = 'MethodExpr',
                    Base = base,
                    Method = methodName,
                    FunctionArguments = fargs,
                    Token_Colon = colonTk,
                    GetFirstToken = function(self) return self.Base:GetFirstToken() end,
                    GetLastToken  = function(self) return self.FunctionArguments:GetLastToken() end,
                })
                base = node
            elseif tk.Source == '[' then
                local ob = get()
                local index = expr()
                local cb = expect('Symbol', ']')
                local node = MkNode({
                    Type = 'IndexExpr',
                    Base = base,
                    Index = index,
                    Token_OpenBracket = ob,
                    Token_CloseBracket = cb,
                    GetFirstToken = function(self) return self.Base:GetFirstToken() end,
                    GetLastToken  = function(self) return self.Token_CloseBracket end,
                })
                base = node
            elseif tk.Source == '{' or tk.Source == '(' or tk.Type == 'String' then
                local fargs = functionargs()
                local node = MkNode({
                    Type = 'CallExpr',
                    Base = base,
                    FunctionArguments = fargs,
                    GetFirstToken = function(self) return self.Base:GetFirstToken() end,
                    GetLastToken  = function(self) return self.FunctionArguments:GetLastToken() end,
                })
                base = node
            elseif Compounds[tk.Source] then
                local compTk = get()
                local rhs = expr()
                local node = MkNode({
                    Type = 'CompoundStat',
                    Base = base,
                    Token_Compound = compTk,
                    Rhs = rhs,
                    Lhs = base,
                    GetFirstToken = function(self) return self.Base:GetFirstToken() end,
                    GetLastToken  = function(self) return self.Rhs:GetLastToken() end,
                })
                base = node
            else
                return base
            end
        end
    end

    local function simpleexpr()
        local tk = peek()
        if tk.Type == 'Number' then
            local tok = get()
            return MkNode({
                Type = 'NumberLiteral', Token = tok,
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
        elseif tk.Type == 'String' then
            local tok = get()
            return MkNode({
                Type = 'StringLiteral', Token = tok,
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
        elseif tk.Source == 'nil' then
            return MkNode({
                Type = 'NilLiteral', Token = get(),
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
        elseif tk.Source == 'true' or tk.Source == 'false' then
            return MkNode({
                Type = 'BooleanLiteral', Token = get(),
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
        elseif tk.Source == '...' then
            return MkNode({
                Type = 'VargLiteral', Token = get(),
                GetFirstToken = function(self) return self.Token end,
                GetLastToken  = function(self) return self.Token end,
            })
        elseif tk.Source == '{' then
            return tableexpr()
        elseif tk.Source == 'function' then
            return funcdecl(true)
        else
            return primaryexpr()
        end
    end

    local subexpr
    subexpr = function(limit)
        local curNode
        if isUnop() then
            local opTk = get()
            local ex = subexpr(UnaryPriority)
            curNode = MkNode({
                Type = 'UnopExpr',
                Token_Op = opTk,
                Rhs = ex,
                GetFirstToken = function(self) return self.Token_Op end,
                GetLastToken  = function(self) return self.Rhs:GetLastToken() end,
            })
        else
            curNode = simpleexpr()
        end

        while isBinop() and BinaryPriority[peek().Source] and BinaryPriority[peek().Source][1] > limit do
            local opTk = get()
            local rhs = subexpr(BinaryPriority[opTk.Source][2])
            curNode = MkNode({
                Type = 'BinopExpr',
                Lhs = curNode,
                Rhs = rhs,
                Token_Op = opTk,
                GetFirstToken = function(self) return self.Lhs:GetFirstToken() end,
                GetLastToken  = function(self) return self.Rhs:GetLastToken() end,
            })
        end
        return curNode
    end

    expr = function() return subexpr(0) end

    funcdecl = function(isAnonymous)
        local functionKw = get()
        local nameChain, nameChainSep
        if not isAnonymous then
            nameChain = {}
            nameChainSep = {}
            nameChain[#nameChain+1] = expect('Ident')
            while peek().Source == '.' do
                nameChainSep[#nameChainSep+1] = get()
                nameChain[#nameChain+1] = expect('Ident')
            end
            if peek().Source == ':' then
                nameChainSep[#nameChainSep+1] = get()
                nameChain[#nameChain+1] = expect('Ident')
            end
        end

        local op = expect('Symbol', '(')
        local argList, argCommaList, vargToken = varlist(true)
        local cp = expect('Symbol', ')')
        local fbody, enTk = blockbody('end')

        local node = MkNode({
            Type = isAnonymous and 'FunctionLiteral' or 'FunctionStat',
            NameChain = nameChain,
            ArgList = argList,
            Body = fbody,
            Token_Function = functionKw,
            Token_NameChainSeparator = nameChainSep,
            Token_OpenParen = op,
            Token_Varg = vargToken,
            Token_ArgCommaList = argCommaList,
            Token_CloseParen = cp,
            Token_End = enTk,
            GetFirstToken = function(self) return self.Token_Function end,
            GetLastToken  = function(self) return self.Token_End end,
        })
        return node
    end

    local function exprstat()
        local ex = primaryexpr()
        if ex.Type == 'MethodExpr' or ex.Type == 'CallExpr' then
            return MkNode({
                Type = 'CallExprStat',
                Expression = ex,
                GetFirstToken = function(self) return self.Expression:GetFirstToken() end,
                GetLastToken  = function(self) return self.Expression:GetLastToken() end,
            })
        elseif ex.Type == 'CompoundStat' then
            return ex
        else
            local lhs = {ex}
            local lhsSep = {}
            while peek().Source == ',' do
                lhsSep[#lhsSep+1] = get()
                local lhsPart = primaryexpr()
                if lhsPart.Type == 'MethodExpr' or lhsPart.Type == 'CallExpr' then
                    error("Bad left hand side of assignment", 2)
                end
                lhs[#lhs+1] = lhsPart
            end
            local eq = expect('Symbol', '=')
            local rhs = {expr()}
            local rhsSep = {}
            while peek().Source == ',' do
                rhsSep[#rhsSep+1] = get()
                rhs[#rhs+1] = expr()
            end
            return MkNode({
                Type = 'AssignmentStat',
                Lhs = lhs, Rhs = rhs,
                Token_Equals = eq,
                Token_LhsSeparatorList = lhsSep,
                Token_RhsSeparatorList = rhsSep,
                GetFirstToken = function(self) return self.Lhs[1]:GetFirstToken() end,
                GetLastToken  = function(self) return self.Rhs[#self.Rhs]:GetLastToken() end,
            })
        end
    end

    local function ifstat()
        local ifKw = get()
        local condition = expr()
        local thenKw = expect('Keyword', 'then')
        local ifBody = block()
        local elseClauses = {}
        while peek().Source == 'elseif' or peek().Source == 'else' do
            local elseifKw = get()
            local elseifCond, elseifThen
            if elseifKw.Source == 'elseif' then
                elseifCond = expr()
                elseifThen = expect('Keyword', 'then')
            end
            local elseifBody = block()
            elseClauses[#elseClauses+1] = {
                Condition = elseifCond,
                Body = elseifBody,
                ClauseType = elseifKw.Source,
                Token = elseifKw,
                Token_Then = elseifThen,
            }
            if elseifKw.Source == 'else' then break end
        end
        local enKw = expect('Keyword', 'end')
        return MkNode({
            Type = 'IfStat',
            Condition = condition,
            Body = ifBody,
            ElseClauseList = elseClauses,
            Token_If = ifKw,
            Token_Then = thenKw,
            Token_End = enKw,
            GetFirstToken = function(self) return self.Token_If end,
            GetLastToken  = function(self) return self.Token_End end,
        })
    end

    local function dostat()
        local doKw = get()
        local body, enKw = blockbody('end')
        return MkNode({
            Type = 'DoStat',
            Body = body,
            Token_Do = doKw,
            Token_End = enKw,
            GetFirstToken = function(self) return self.Token_Do end,
            GetLastToken  = function(self) return self.Token_End end,
        })
    end

    local function whilestat()
        local whileKw = get()
        local condition = expr()
        local doKw = expect('Keyword', 'do')
        local body, enKw = blockbody('end')
        return MkNode({
            Type = 'WhileStat',
            Condition = condition,
            Body = body,
            Token_While = whileKw,
            Token_Do = doKw,
            Token_End = enKw,
            GetFirstToken = function(self) return self.Token_While end,
            GetLastToken  = function(self) return self.Token_End end,
        })
    end

    local function forstat()
        local forKw = get()
        local loopVars, loopVarCommas = varlist(false)
        if peek().Source == '=' then
            local eqTk = get()
            local exprList, exprCommaList = exprlist()
            local doTk = expect('Keyword', 'do')
            local body, enTk = blockbody('end')
            return MkNode({
                Type = 'NumericForStat',
                VarList = loopVars,
                RangeList = exprList,
                Body = body,
                Token_For = forKw,
                Token_VarCommaList = loopVarCommas,
                Token_Equals = eqTk,
                Token_RangeCommaList = exprCommaList,
                Token_Do = doTk,
                Token_End = enTk,
                GetFirstToken = function(self) return self.Token_For end,
                GetLastToken  = function(self) return self.Token_End end,
            })
        elseif peek().Source == 'in' then
            local inTk = get()
            local exprList, exprCommaList = exprlist()
            local doTk = expect('Keyword', 'do')
            local body, enTk = blockbody('end')
            return MkNode({
                Type = 'GenericForStat',
                VarList = loopVars,
                GeneratorList = exprList,
                Body = body,
                Token_For = forKw,
                Token_VarCommaList = loopVarCommas,
                Token_In = inTk,
                Token_GeneratorCommaList = exprCommaList,
                Token_Do = doTk,
                Token_End = enTk,
                GetFirstToken = function(self) return self.Token_For end,
                GetLastToken  = function(self) return self.Token_End end,
            })
        else
            error("'=' or 'in' expected in for statement", 2)
        end
    end

    local function repeatstat()
        local repeatKw = get()
        local body, untilTk = blockbody('until')
        local condition = expr()
        return MkNode({
            Type = 'RepeatStat',
            Body = body,
            Condition = condition,
            Token_Repeat = repeatKw,
            Token_Until = untilTk,
            GetFirstToken = function(self) return self.Token_Repeat end,
            GetLastToken  = function(self) return self.Condition:GetLastToken() end,
        })
    end

    local function localdecl()
        local localKw = get()
        if peek().Source == 'function' then
            local funcStat = funcdecl(false)
            if #funcStat.NameChain > 1 then
                error("`(` expected.", 2)
            end
            return MkNode({
                Type = 'LocalFunctionStat',
                FunctionStat = funcStat,
                Token_Local = localKw,
                GetFirstToken = function(self) return self.Token_Local end,
                GetLastToken  = function(self) return self.FunctionStat:GetLastToken() end,
            })
        elseif peek().Type == 'Ident' then
            local varList, varCommaList = varlist(false)
            local exprList, exprCommaList = {}, {}
            local eqToken
            if peek().Source == '=' then
                eqToken = get()
                exprList, exprCommaList = exprlist()
            end
            return MkNode({
                Type = 'LocalVarStat',
                VarList = varList,
                ExprList = exprList,
                Token_Local = localKw,
                Token_Equals = eqToken,
                Token_VarCommaList = varCommaList,
                Token_ExprCommaList = exprCommaList,
                GetFirstToken = function(self) return self.Token_Local end,
                GetLastToken  = function(self)
                    if #self.ExprList > 0 then
                        return self.ExprList[#self.ExprList]:GetLastToken()
                    else
                        return self.VarList[#self.VarList]
                    end
                end,
            })
        else
            error("`function` or identifier expected", 2)
        end
    end

    local function retstat()
        local returnKw = get()
        local exprList, commaList = {}, {}
        if not isBlockFollow() and peek().Source ~= ';' then
            exprList, commaList = exprlist()
        end
        local self2 = {
            Type = 'ReturnStat',
            ExprList = exprList,
            Token_Return = returnKw,
            Token_CommaList = commaList,
            GetFirstToken = function(s) return s.Token_Return end,
            GetLastToken  = function(s)
                if #s.ExprList > 0 then
                    return s.ExprList[#s.ExprList]:GetLastToken()
                else
                    return s.Token_Return
                end
            end,
        }
        return self2
    end

    local function breakstat()
        local bk = get()
        return {
            Type = 'BreakStat',
            Token_Break = bk,
            GetFirstToken = function(s) return s.Token_Break end,
            GetLastToken  = function(s) return s.Token_Break end,
        }
    end

    local function continuestat()
        local ck = get()
        return {
            Type = 'ContinueStat',
            Token_Continue = ck,
            GetFirstToken = function(s) return s.Token_Continue end,
            GetLastToken  = function(s) return s.Token_Continue end,
        }
    end

    local function statement()
        local tok = peek()
        if tok.Source == 'if' then
            return false, ifstat()
        elseif tok.Source == 'while' then
            return false, whilestat()
        elseif tok.Source == 'do' then
            return false, dostat()
        elseif tok.Source == 'for' then
            return false, forstat()
        elseif tok.Source == 'repeat' then
            return false, repeatstat()
        elseif tok.Source == 'function' then
            return false, funcdecl(false)
        elseif tok.Source == 'local' then
            return false, localdecl()
        elseif tok.Source == 'return' then
            return true, retstat()
        elseif tok.Source == 'break' then
            return true, breakstat()
        elseif tok.Source == 'continue' then
            return true, continuestat()
        else
            return false, exprstat()
        end
    end

    block = function()
        local statements = {}
        local semicolons = {}
        local isLast = false

        while not isLast and not isBlockFollow() do
            local isL, stat = statement()
            isLast = isL
            if stat then
                statements[#statements+1] = stat
            end
            if peek().Type == 'Symbol' and peek().Source == ';' then
                semicolons[#statements] = get()
            end
        end

        local node = {
            Type = 'StatList',
            StatementList = statements,
            SemicolonList = semicolons,
            GetFirstToken = function(self)
                if #self.StatementList == 0 then return nil end
                return self.StatementList[1]:GetFirstToken()
            end,
            GetLastToken = function(self)
                if #self.StatementList == 0 then return nil end
                if self.SemicolonList[#self.StatementList] then
                    return self.SemicolonList[#self.StatementList]
                end
                return self.StatementList[#self.StatementList]:GetLastToken()
            end,
        }
        return node
    end

    return block()
end

------------------------------------------------------------------------
-- VARIABLE INFO
------------------------------------------------------------------------
local function AddVariableInfo(ast)
    local globalVars = {}
    local currentScope
    local locationGen = 0

    local function markLocation()
        locationGen = locationGen + 1
        return locationGen
    end

    local function pushScope()
        local scope = {
            ParentScope = currentScope,
            ChildScopeList = {},
            VariableList = {},
            BeginLocation = markLocation(),
            Depth = currentScope and (currentScope.Depth + 1) or 1,
        }
        if currentScope then
            currentScope.ChildScopeList[#currentScope.ChildScopeList+1] = scope
        end
        currentScope = scope
    end

    local function popScope()
        local scope = currentScope
        scope.EndLocation = markLocation()
        for _, v in ipairs(scope.VariableList) do
            v.ScopeEndLocation = scope.EndLocation
        end
        currentScope = scope.ParentScope
        return scope
    end

    pushScope()

    local function addLocalVar(name, setNameFunc, localInfo)
        local _var = {
            Type = 'Local',
            Name = name,
            RenameList = {setNameFunc},
            AssignedTo = false,
            Info = localInfo,
            Scope = currentScope,
            BeginLocation = markLocation(),
            EndLocation = markLocation(),
            ReferenceLocationList = {markLocation()},
        }
        _var.Rename = function(newName)
            _var.Name = newName
            for _, fn in ipairs(_var.RenameList) do fn(newName) end
        end
        currentScope.VariableList[#currentScope.VariableList+1] = _var
        return _var
    end

    local function getGlobalVar(name)
        for _, v in ipairs(globalVars) do
            if v.Name == name then return v end
        end
        local _var = {
            Type = 'Global',
            Name = name,
            RenameList = {},
            AssignedTo = false,
            Scope = nil,
            BeginLocation = markLocation(),
            EndLocation = markLocation(),
            ReferenceLocationList = {},
        }
        _var.Rename = function(newName)
            _var.Name = newName
            for _, fn in ipairs(_var.RenameList) do fn(newName) end
        end
        globalVars[#globalVars+1] = _var
        return _var
    end

    local function addGlobalReference(name, setNameFunc)
        local _var = getGlobalVar(name)
        _var.RenameList[#_var.RenameList+1] = setNameFunc
        return _var
    end

    local function getLocalVar(scope, name)
        for i = #scope.VariableList, 1, -1 do
            if scope.VariableList[i].Name == name then
                return scope.VariableList[i]
            end
        end
        if scope.ParentScope then
            return getLocalVar(scope.ParentScope, name)
        end
        return nil
    end

    local function referenceVariable(name, setNameFunc)
        local _var = getLocalVar(currentScope, name)
        if _var then
            _var.RenameList[#_var.RenameList+1] = setNameFunc
        else
            _var = addGlobalReference(name, setNameFunc)
        end
        local loc = markLocation()
        _var.EndLocation = loc
        _var.ReferenceLocationList[#_var.ReferenceLocationList+1] = loc
        return _var
    end

    local visitor = {}

    local VisitAst
    local visitExpr
    local visitStat

    visitExpr = function(expr)
        if expr.Type == 'BinopExpr' then
            visitExpr(expr.Lhs)
            visitExpr(expr.Rhs)
        elseif expr.Type == 'UnopExpr' then
            visitExpr(expr.Rhs)
        elseif expr.Type == 'NumberLiteral' or expr.Type == 'StringLiteral'
            or expr.Type == 'NilLiteral' or expr.Type == 'BooleanLiteral'
            or expr.Type == 'VargLiteral' then
            -- nothing
        elseif expr.Type == 'FieldExpr' then
            visitExpr(expr.Base)
        elseif expr.Type == 'IndexExpr' then
            visitExpr(expr.Base)
            visitExpr(expr.Index)
        elseif expr.Type == 'MethodExpr' or expr.Type == 'CallExpr' then
            visitExpr(expr.Base)
            if expr.FunctionArguments.CallType == 'ArgCall' then
                for _, a in ipairs(expr.FunctionArguments.ArgList) do visitExpr(a) end
            elseif expr.FunctionArguments.CallType == 'TableCall' then
                visitExpr(expr.FunctionArguments.TableExpr)
            end
        elseif expr.Type == 'FunctionLiteral' then
            pushScope()
            for i, ident in ipairs(expr.ArgList) do
                addLocalVar(ident.Source, function(name) ident.Source = name end, {Type='Argument',Index=i})
            end
            visitStat(expr.Body)
            popScope()
        elseif expr.Type == 'VariableExpr' then
            expr.Variable = referenceVariable(expr.Token.Source, function(name)
                expr.Token.Source = name
            end)
        elseif expr.Type == 'ParenExpr' then
            visitExpr(expr.Expression)
        elseif expr.Type == 'TableLiteral' then
            for _, entry in ipairs(expr.EntryList) do
                if entry.EntryType == 'Field' then
                    visitExpr(entry.Value)
                elseif entry.EntryType == 'Index' then
                    visitExpr(entry.Index)
                    visitExpr(entry.Value)
                elseif entry.EntryType == 'Value' then
                    visitExpr(entry.Value)
                end
            end
        elseif expr.Type == 'CompoundStat' then
            visitExpr(expr.Lhs)
            visitExpr(expr.Rhs)
        end
    end

    visitStat = function(stat)
        if stat.Type == 'StatList' then
            pushScope()
            for _, ch in ipairs(stat.StatementList) do
                if ch then visitStat(ch) end
            end
            popScope()
        elseif stat.Type == 'BreakStat' or stat.Type == 'ContinueStat' then
            -- nothing
        elseif stat.Type == 'ReturnStat' then
            for _, e in ipairs(stat.ExprList) do visitExpr(e) end
        elseif stat.Type == 'LocalVarStat' then
            if stat.Token_Equals then
                for _, e in ipairs(stat.ExprList) do visitExpr(e) end
            end
            for i, ident in ipairs(stat.VarList) do
                addLocalVar(ident.Source, function(name) stat.VarList[i].Source = name end, {Type='Local'})
            end
        elseif stat.Type == 'LocalFunctionStat' then
            addLocalVar(stat.FunctionStat.NameChain[1].Source, function(name)
                stat.FunctionStat.NameChain[1].Source = name
            end, {Type='LocalFunction'})
            pushScope()
            for i, ident in ipairs(stat.FunctionStat.ArgList) do
                addLocalVar(ident.Source, function(name) ident.Source = name end, {Type='Argument',Index=i})
            end
            visitStat(stat.FunctionStat.Body)
            popScope()
        elseif stat.Type == 'FunctionStat' then
            local nameChain = stat.NameChain
            local _var
            if #nameChain == 1 then
                if getLocalVar(currentScope, nameChain[1].Source) then
                    _var = referenceVariable(nameChain[1].Source, function(name) nameChain[1].Source = name end)
                else
                    _var = addGlobalReference(nameChain[1].Source, function(name) nameChain[1].Source = name end)
                end
            else
                _var = referenceVariable(nameChain[1].Source, function(name) nameChain[1].Source = name end)
            end
            _var.AssignedTo = true
            pushScope()
            for i, ident in ipairs(stat.ArgList) do
                addLocalVar(ident.Source, function(name) ident.Source = name end, {Type='Argument',Index=i})
            end
            visitStat(stat.Body)
            popScope()
        elseif stat.Type == 'RepeatStat' then
            pushScope()
            visitStat(stat.Body)
            visitExpr(stat.Condition)
            popScope()
        elseif stat.Type == 'GenericForStat' then
            for _, e in ipairs(stat.GeneratorList) do visitExpr(e) end
            pushScope()
            for i, ident in ipairs(stat.VarList) do
                addLocalVar(ident.Source, function(name) ident.Source = name end, {Type='ForRange',Index=i})
            end
            visitStat(stat.Body)
            popScope()
        elseif stat.Type == 'NumericForStat' then
            for _, e in ipairs(stat.RangeList) do visitExpr(e) end
            pushScope()
            for i, ident in ipairs(stat.VarList) do
                addLocalVar(ident.Source, function(name) ident.Source = name end, {Type='ForRange',Index=i})
            end
            visitStat(stat.Body)
            popScope()
        elseif stat.Type == 'WhileStat' then
            visitExpr(stat.Condition)
            visitStat(stat.Body)
        elseif stat.Type == 'DoStat' then
            visitStat(stat.Body)
        elseif stat.Type == 'IfStat' then
            visitExpr(stat.Condition)
            visitStat(stat.Body)
            for _, clause in ipairs(stat.ElseClauseList) do
                if clause.Condition then visitExpr(clause.Condition) end
                visitStat(clause.Body)
            end
        elseif stat.Type == 'CallExprStat' then
            visitExpr(stat.Expression)
        elseif stat.Type == 'CompoundStat' then
            visitExpr(stat.Rhs)
        elseif stat.Type == 'AssignmentStat' then
            for _, e in ipairs(stat.Lhs) do visitExpr(e) end
            for _, e in ipairs(stat.Rhs) do visitExpr(e) end
        end
    end

    visitStat(ast)
    return globalVars, popScope()
end

------------------------------------------------------------------------
-- VARIABLE RENAMING
------------------------------------------------------------------------
local VarStartDigits = {}
local VarDigits = {}
do
    for i = string.byte('a'), string.byte('z') do VarStartDigits[#VarStartDigits+1] = string.char(i) end
    for i = string.byte('A'), string.byte('Z') do VarStartDigits[#VarStartDigits+1] = string.char(i) end
    for i = string.byte('a'), string.byte('z') do VarDigits[#VarDigits+1] = string.char(i) end
    for i = string.byte('A'), string.byte('Z') do VarDigits[#VarDigits+1] = string.char(i) end
    for i = string.byte('0'), string.byte('9') do VarDigits[#VarDigits+1] = string.char(i) end
    VarDigits[#VarDigits+1] = '_'
end

local function indexToVarName(index)
    local id = ''
    local d = index % #VarStartDigits
    index = (index - d) / #VarStartDigits
    id = VarStartDigits[d + 1]
    while index > 0 do
        d = index % #VarDigits
        index = (index - d) / #VarDigits
        id = id .. VarDigits[d + 1]
    end
    return id
end

local function MinifyVariables(globalScope, rootScope, renameGlobals)
    local globalUsedNames = {}
    for kw in pairs(Keywords) do
        globalUsedNames[kw] = true
    end

    local allVariables = {}

    for _, _var in ipairs(globalScope) do
        if _var.AssignedTo and renameGlobals then
            allVariables[#allVariables+1] = _var
        else
            globalUsedNames[_var.Name] = true
        end
    end

    local function addFrom(scope)
        for _, _var in ipairs(scope.VariableList) do
            allVariables[#allVariables+1] = _var
        end
        for _, child in ipairs(scope.ChildScopeList) do
            addFrom(child)
        end
    end
    addFrom(rootScope)

    for _, _var in ipairs(allVariables) do
        _var.UsedNameArray = {}
    end

    local nextValidNameIndex = 0
    local varNamesLazy = {}

    local function varIndexToValidName(i)
        local name = varNamesLazy[i]
        if not name then
            name = indexToVarName(nextValidNameIndex)
            nextValidNameIndex = nextValidNameIndex + 1
            while globalUsedNames[name] do
                name = indexToVarName(nextValidNameIndex)
                nextValidNameIndex = nextValidNameIndex + 1
            end
            varNamesLazy[i] = name
        end
        return name
    end

    for _, _var in ipairs(allVariables) do
        _var.Renamed = true
        local i = 0
        while _var.UsedNameArray[i] do i = i + 1 end
        _var.Rename(varIndexToValidName(i))

        if _var.Scope then
            for _, otherVar in ipairs(allVariables) do
                if not otherVar.Renamed then
                    if not otherVar.Scope or otherVar.Scope.Depth < _var.Scope.Depth then
                        for _, refAt in ipairs(otherVar.ReferenceLocationList) do
                            if refAt >= _var.BeginLocation and refAt <= _var.ScopeEndLocation then
                                otherVar.UsedNameArray[i] = true
                                break
                            end
                        end
                    elseif otherVar.Scope.Depth > _var.Scope.Depth then
                        for _, refAt in ipairs(_var.ReferenceLocationList) do
                            if refAt >= otherVar.BeginLocation and refAt <= otherVar.ScopeEndLocation then
                                otherVar.UsedNameArray[i] = true
                                break
                            end
                        end
                    else
                        if _var.BeginLocation < otherVar.EndLocation and _var.EndLocation > otherVar.BeginLocation then
                            otherVar.UsedNameArray[i] = true
                        end
                    end
                end
            end
        else
            for _, otherVar in ipairs(allVariables) do
                if not otherVar.Renamed then
                    if otherVar.Type == 'Global' then
                        otherVar.UsedNameArray[i] = true
                    elseif otherVar.Type == 'Local' then
                        for _, refAt in ipairs(_var.ReferenceLocationList) do
                            if refAt >= otherVar.BeginLocation and refAt <= otherVar.ScopeEndLocation then
                                otherVar.UsedNameArray[i] = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- STRIP / PRINTER
------------------------------------------------------------------------
local function isIdentChar(c)
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
           (c >= '0' and c <= '9') or c == '_'
end

local function StripAndPrint(ast)
    local out = {}

    local function needSpace(a, b)
        local ac = a:sub(-1)
        local bc = b:sub(1,1)
        if ac == '' or bc == '' then return false end
        if isIdentChar(ac) and isIdentChar(bc) then return true end
        if ac == '-' and bc == '-' then return true end
        return false
    end

    local lastSrc = ''

    local function emit(src)
        src = tostring(src)
        if src == '' then return end
        if needSpace(lastSrc, src) then
            out[#out+1] = ' '
        end
        out[#out+1] = src
        lastSrc = src
    end

    local printExpr
    local printStat

    printExpr = function(expr)
        if expr.Type == 'BinopExpr' then
            printExpr(expr.Lhs)
            emit(expr.Token_Op.Source)
            printExpr(expr.Rhs)
        elseif expr.Type == 'UnopExpr' then
            emit(expr.Token_Op.Source)
            printExpr(expr.Rhs)
        elseif expr.Type == 'NumberLiteral' or expr.Type == 'StringLiteral'
            or expr.Type == 'NilLiteral' or expr.Type == 'BooleanLiteral'
            or expr.Type == 'VargLiteral' then
            emit(expr.Token.Source)
        elseif expr.Type == 'FieldExpr' then
            printExpr(expr.Base)
            emit('.')
            emit(expr.Field.Source)
        elseif expr.Type == 'IndexExpr' then
            printExpr(expr.Base)
            emit('[')
            printExpr(expr.Index)
            emit(']')
        elseif expr.Type == 'MethodExpr' or expr.Type == 'CallExpr' then
            printExpr(expr.Base)
            if expr.Type == 'MethodExpr' then
                emit(':')
                emit(expr.Method.Source)
            end
            local fargs = expr.FunctionArguments
            if fargs.CallType == 'StringCall' then
                emit(fargs.Token.Source)
            elseif fargs.CallType == 'ArgCall' then
                emit('(')
                for i, argExpr in ipairs(fargs.ArgList) do
                    printExpr(argExpr)
                    if fargs.Token_CommaList[i] then emit(',') end
                end
                emit(')')
            elseif fargs.CallType == 'TableCall' then
                printExpr(fargs.TableExpr)
            end
        elseif expr.Type == 'FunctionLiteral' then
            emit('function')
            emit('(')
            for i, arg in ipairs(expr.ArgList) do
                emit(arg.Source)
                if expr.Token_ArgCommaList[i] then emit(',') end
            end
            if expr.Token_Varg then emit('...') end
            emit(')')
            printStat(expr.Body)
            emit('end')
        elseif expr.Type == 'VariableExpr' then
            emit(expr.Token.Source)
        elseif expr.Type == 'ParenExpr' then
            emit('(')
            printExpr(expr.Expression)
            emit(')')
        elseif expr.Type == 'TableLiteral' then
            emit('{')
            for i, entry in ipairs(expr.EntryList) do
                if entry.EntryType == 'Field' then
                    emit(entry.Field.Source)
                    emit('=')
                    printExpr(entry.Value)
                elseif entry.EntryType == 'Index' then
                    emit('[')
                    printExpr(entry.Index)
                    emit(']')
                    emit('=')
                    printExpr(entry.Value)
                elseif entry.EntryType == 'Value' then
                    printExpr(entry.Value)
                end
                if i < #expr.EntryList then emit(',') end
            end
            emit('}')
        elseif expr.Type == 'CompoundStat' then
            printStat(expr)
        else
            error("printExpr: unknown type " .. tostring(expr.Type))
        end
    end

    printStat = function(stat)
        if stat.Type == 'StatList' then
            for i, ch in ipairs(stat.StatementList) do
                if ch then
                    printStat(ch)
                end
            end
        elseif stat.Type == 'BreakStat' then
            emit('break')
        elseif stat.Type == 'ContinueStat' then
            emit('continue')
        elseif stat.Type == 'ReturnStat' then
            emit('return')
            for i, e in ipairs(stat.ExprList) do
                printExpr(e)
                if stat.Token_CommaList[i] then emit(',') end
            end
        elseif stat.Type == 'LocalVarStat' then
            emit('local')
            for i, v in ipairs(stat.VarList) do
                emit(v.Source)
                if stat.Token_VarCommaList[i] then emit(',') end
            end
            if stat.Token_Equals then
                emit('=')
                for i, e in ipairs(stat.ExprList) do
                    printExpr(e)
                    if stat.Token_ExprCommaList[i] then emit(',') end
                end
            end
        elseif stat.Type == 'LocalFunctionStat' then
            emit('local')
            emit('function')
            emit(stat.FunctionStat.NameChain[1].Source)
            emit('(')
            for i, arg in ipairs(stat.FunctionStat.ArgList) do
                emit(arg.Source)
                if stat.FunctionStat.Token_ArgCommaList[i] then emit(',') end
            end
            if stat.FunctionStat.Token_Varg then emit('...') end
            emit(')')
            printStat(stat.FunctionStat.Body)
            emit('end')
        elseif stat.Type == 'FunctionStat' then
            emit('function')
            for i, part in ipairs(stat.NameChain) do
                emit(part.Source)
                if stat.Token_NameChainSeparator and stat.Token_NameChainSeparator[i] then
                    emit(stat.Token_NameChainSeparator[i].Source)
                end
            end
            emit('(')
            for i, arg in ipairs(stat.ArgList) do
                emit(arg.Source)
                if stat.Token_ArgCommaList[i] then emit(',') end
            end
            if stat.Token_Varg then emit('...') end
            emit(')')
            printStat(stat.Body)
            emit('end')
        elseif stat.Type == 'RepeatStat' then
            emit('repeat')
            printStat(stat.Body)
            emit('until')
            printExpr(stat.Condition)
        elseif stat.Type == 'GenericForStat' then
            emit('for')
            for i, v in ipairs(stat.VarList) do
                emit(v.Source)
                if stat.Token_VarCommaList[i] then emit(',') end
            end
            emit('in')
            for i, e in ipairs(stat.GeneratorList) do
                printExpr(e)
                if stat.Token_GeneratorCommaList[i] then emit(',') end
            end
            emit('do')
            printStat(stat.Body)
            emit('end')
        elseif stat.Type == 'NumericForStat' then
            emit('for')
            for i, v in ipairs(stat.VarList) do
                emit(v.Source)
                if stat.Token_VarCommaList[i] then emit(',') end
            end
            emit('=')
            for i, e in ipairs(stat.RangeList) do
                printExpr(e)
                if stat.Token_RangeCommaList[i] then emit(',') end
            end
            emit('do')
            printStat(stat.Body)
            emit('end')
        elseif stat.Type == 'WhileStat' then
            emit('while')
            printExpr(stat.Condition)
            emit('do')
            printStat(stat.Body)
            emit('end')
        elseif stat.Type == 'DoStat' then
            emit('do')
            printStat(stat.Body)
            emit('end')
        elseif stat.Type == 'IfStat' then
            emit('if')
            printExpr(stat.Condition)
            emit('then')
            printStat(stat.Body)
            for _, clause in ipairs(stat.ElseClauseList) do
                emit(clause.Token.Source)
                if clause.Condition then
                    printExpr(clause.Condition)
                    emit('then')
                end
                printStat(clause.Body)
            end
            emit('end')
        elseif stat.Type == 'CallExprStat' then
            printExpr(stat.Expression)
        elseif stat.Type == 'CompoundStat' then
            printExpr(stat.Lhs)
            emit(stat.Token_Compound.Source)
            printExpr(stat.Rhs)
        elseif stat.Type == 'AssignmentStat' then
            for i, e in ipairs(stat.Lhs) do
                printExpr(e)
                if stat.Token_LhsSeparatorList[i] then emit(',') end
            end
            emit('=')
            for i, e in ipairs(stat.Rhs) do
                printExpr(e)
                if stat.Token_RhsSeparatorList[i] then emit(',') end
            end
        else
            error("printStat: unknown type " .. tostring(stat.Type))
        end
    end

    printStat(ast)
    return table.concat(out)
end

------------------------------------------------------------------------
-- ENTRY POINT
------------------------------------------------------------------------
local LuaMinifier = {}

function LuaMinifier.Minify(source, options)
    options = options or {}
    local renameVars    = options.RenameVariables ~= false
    local renameGlobals = options.RenameGlobals == true

    local ast = CreateLuaParser(source)
    local glb, root = AddVariableInfo(ast)

    if renameVars then
        MinifyVariables(glb, root, renameGlobals)
    end

    return StripAndPrint(ast)
end

return LuaMinifier
