local find = string.find
local fmt = string.format
local match = string.match
local sub = string.sub
local tonumber = tonumber

local M = {}

-- Lua 5.1 + Luau keywords (continue added for Luau)
local kw = {}
for v in ([[
and break continue do else elseif end false for function goto if in
local nil not or repeat return then true until while]]):gmatch("%S+") do
  kw[v] = true
end

local z, sourceid, I, buff, ln, tok, seminfo, tokln

local function addtoken(token, info)
  local i = #tok + 1
  tok[i] = token; seminfo[i] = info; tokln[i] = ln
end

local function inclinenumber(i, is_tok)
  local old = sub(z, i, i)
  i = i + 1
  local c = sub(z, i, i)
  if (c == "\n" or c == "\r") and c ~= old then i = i + 1; old = old..c end
  if is_tok then addtoken("TK_EOL", old) end
  ln = ln + 1; I = i; return i
end

local function chunkid()
  if sourceid and match(sourceid, "^[=@]") then return sub(sourceid, 2) end
  return "[string]"
end

local function errorline(s, line)
  local e = M.error or error
  e(fmt("%s:%d: %s", chunkid(), line or ln, s))
end

local function skip_sep(i)
  local s = sub(z, i, i); i = i + 1
  local count = #match(z, "=*", i); i = i + count; I = i
  return (sub(z, i, i) == s) and count or (-count) - 1
end

local function read_long_string(is_str, sep)
  local i = I + 1
  local c = sub(z, i, i)
  if c == "\r" or c == "\n" then i = inclinenumber(i) end
  while true do
    local p, _, r = find(z, "([\r\n%]])", i)
    if not p then errorline(is_str and "unfinished long string" or "unfinished long comment") end
    i = p
    if r == "]" then
      if skip_sep(i) == sep then buff = sub(z, buff, I); I = I + 1; return buff end
      i = I
    else
      buff = buff.."\n"; i = inclinenumber(i)
    end
  end
end

local function read_string(del)
  local i = I
  while true do
    local p, _, r = find(z, "([\n\r\\\"\\'`])", i)
    if p then
      if r == "\n" or r == "\r" then errorline("unfinished string") end
      i = p
      if r == "\\" then
        i = i + 1; r = sub(z, i, i)
        if r == "" then break end
        if r == "u" then
          -- Luau \u{XXXX}
          i = i + 1
          if sub(z, i, i) == "{" then
            local q = find(z, "}", i + 1)
            if not q then errorline("missing '}' in \\u{xxxx}") end
            i = q + 1
          end
        elseif r == "z" then
          -- Luau \z skip whitespace
          i = i + 1
          while match(sub(z, i, i), "%s") do i = i + 1 end
        else
          local p2 = find("abfnrtv\n\r", r, 1, true)
          if p2 then
            if p2 > 7 then i = inclinenumber(i) else i = i + 1 end
          elseif find(r, "%D") then
            i = i + 1
          else
            local _, q, s = find(z, "^(%d%d?%d?)", i)
            i = q + 1
            if s + 1 > 256 then errorline("escape sequence too large") end
          end
        end
      else
        i = i + 1
        if r == del then I = i; return sub(z, buff, i - 1) end
      end
    else break end
  end
  errorline("unfinished string")
end

local function init(_z, _sourceid)
  z = _z; sourceid = _sourceid; I = 1; ln = 1
  tok = {}; seminfo = {}; tokln = {}
  local p, _, q, r = find(z, "^(#[^\r\n]*)(\r?\n?)")
  if p then
    I = I + #q; addtoken("TK_COMMENT", q)
    if #r > 0 then inclinenumber(I, true) end
  end
end

function M.lex(source, source_name)
  init(source, source_name)
  while true do
    local i = I
    while true do --luacheck: ignore 512

      -- identifier / keyword
      local p, _, r = find(z, "^([_%a][_%w]*)", i)
      if p then
        I = i + #r
        addtoken(kw[r] and "TK_KEYWORD" or "TK_NAME", r)
        break
      end

      -- number (Lua5.1 + Luau hex floats)
      local p, _, r = find(z, "^(%.?)%d", i)
      if p then
        if r == "." then i = i + 1 end
        if match(z, "^0[xX]", i) then
          local _, q = find(z, "^0[xX][%x]*%.?[%x]*", i)
          i = q + 1
          -- optional p/P exponent for hex floats (Luau)
          if match(z, "^[pP]", i) then
            i = i + 1
            if match(z, "^[%+%-]", i) then i = i + 1 end
            local _, q2 = find(z, "^%d*", i); i = q2 + 1
          end
          I = i
        else
          local _, q, r2 = find(z, "^%d*[%.%d]*([eE]?)", i) --luacheck: ignore 421
          i = q + 1
          if #r2 == 1 then
            if match(z, "^[%+%-]", i) then i = i + 1 end
          end
          local _, q2 = find(z, "^[_%w]*", i); I = q2 + 1
        end
        local v = sub(z, p, I - 1)
        addtoken("TK_NUMBER", v)
        break
      end

      -- whitespace / newline
      local p, q, r, t = find(z, "^((%s)[ \t\v\f]*)", i)
      if p then
        if t == "\n" or t == "\r" then inclinenumber(i, true)
        else I = q + 1; addtoken("TK_SPACE", r) end
        break
      end

      -- :: operator
      local _, q = find(z, "^::", i)
      if q then I = q + 1; addtoken("TK_OP", "::"); break end

      -- Luau compound ops: ..=, //=, //
      local luau_op = match(z, "^(%.%.=)", i) or match(z, "^(//=)", i) or match(z, "^(//)", i)
      if luau_op then
        I = i + #luau_op; addtoken("TK_OP", luau_op); break
      end

      -- compound assignment ops: +=  -=  *=  /=  %=  ^=
      local op = match(z, "^([%+%-%*/%%%^]=)", i)
      if op then I = i + #op; addtoken("TK_OP", op); break end

      -- other punctuation
      local r = match(z, "^%p", i)
      if r then
        buff = i
        local p = find("-[\"'.`=<>~", r, 1, true) --luacheck: ignore 421
        if p then
          if p <= 2 then
            if p == 1 then
              local c = match(z, "^%-%-(%[?)", i)
              if c then
                i = i + 2; local sep = -1
                if c == "[" then sep = skip_sep(i) end
                if sep >= 0 then addtoken("TK_LCOMMENT", read_long_string(false, sep))
                else I = find(z, "[\n\r]", i) or (#z + 1); addtoken("TK_COMMENT", sub(z, buff, I - 1)) end
                break
              end
            else
              local sep = skip_sep(i)
              if sep >= 0 then addtoken("TK_LSTRING", read_long_string(true, sep))
              elseif sep == -1 then addtoken("TK_OP", "[")
              else errorline("invalid long string delimiter") end
              break
            end
          elseif p <= 5 then
            if p < 5 then I = i + 1; addtoken("TK_STRING", read_string(r)); break end
            r = match(z, "^%.%.?%.?", i)
          else
            r = match(z, "^%p=?", i)
          end
        end
        if not p then r = match(z, "^%p=?", i) end
        I = i + #r; addtoken("TK_OP", r); break
      end

      local r = sub(z, i, i)
      if r ~= "" then I = i + 1; addtoken("TK_OP", r); break end
      addtoken("TK_EOS", ""); return tok, seminfo, tokln

    end
  end
end

return M
