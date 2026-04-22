local minifier = (function()

local function merge(...)
  local result = {}
  for _, tab in ipairs{...} do
    for key, val in pairs(tab) do result[key] = val end
  end
  return result
end

local llex = (function()
  local find = string.find
  local fmt = string.format
  local match = string.match
  local sub = string.sub
  local tonumber = tonumber
  local M = {}
  local kw = {}
  for v in ([[and break continue do else elseif end false for function goto if in local nil not or repeat return then true until while]]):gmatch("%S+") do
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
    if (c == "\n" or c == "\r") and (c ~= old) then i = i + 1; old = old..c end
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
      local p, _, r = find(z, "([\n\r\\\"'`])", i)
      if p then
        if r == "\n" or r == "\r" then errorline("unfinished string") end
        i = p
        if r == "\\" then
          i = i + 1; r = sub(z, i, i)
          if r == "" then break end
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
      while true do
        local p, _, r = find(z, "^([_%a][_%w]*)", i)
        if p then
          I = i + #r
          if kw[r] then addtoken("TK_KEYWORD", r) else addtoken("TK_NAME", r) end
          break
        end
        local p2, _, r2 = find(z, "^(%.?)%d", i)
        if p2 then
          if r2 == "." then i = i + 1 end
          local _, q, r3 = find(z, "^%d*[%.%d]*([eE]?)", i)
          i = q + 1
          if #r3 == 1 then if match(z, "^[%+%-]", i) then i = i + 1 end end
          local _, q2 = find(z, "^[_%w]*", i)
          I = q2 + 1
          local v = sub(z, p2, q2)
          if not tonumber(v) then errorline("malformed number") end
          addtoken("TK_NUMBER", v); break
        end
        local p3, q3, r4, t = find(z, "^((%s)[ \t\v\f]*)", i)
        if p3 then
          if t == "\n" or t == "\r" then inclinenumber(i, true)
          else I = q3 + 1; addtoken("TK_SPACE", r4) end
          break
        end
        local _, q4 = find(z, "^::", i)
        if q4 then I = q4 + 1; addtoken("TK_OP", "::"); break end
        local op = match(z, "^([%+%-%*/%%]=)", i)
        if op then I = i + #op; addtoken("TK_OP", op); break end
        local r5 = match(z, "^%p", i)
        if r5 then
          buff = i
          local p4 = find("-[\"'.`=<>~", r5, 1, true)
          if p4 then
            if p4 <= 2 then
              if p4 == 1 then
                local c = match(z, "^%-%-(%[?)", i)
                if c then
                  i = i + 2
                  local sep = -1
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
            elseif p4 <= 5 then
              if p4 < 5 then I = i + 1; addtoken("TK_STRING", read_string(r5)); break end
              r5 = match(z, "^%.%.?%.?", i)
            else
              r5 = match(z, "^%p=?", i)
            end
          end
          if not p4 then r5 = match(z, "^%p=?", i) end
          I = i + #r5; addtoken("TK_OP", r5); break
        end
        local r6 = sub(z, i, i)
        if r6 ~= "" then I = i + 1; addtoken("TK_OP", r6); break end
        addtoken("TK_EOS", ""); return tok, seminfo, tokln
      end
    end
  end
  return M
end)()

local lparser = (function()
  local fmt = string.format
  local gmatch = string.gmatch
  local pairs = pairs
  local M = {}
  local toklist, seminfolist, toklnlist, xreflist, tpos,
        line, lastln, tok, seminfo, ln, xref, nameref, fs, top_fs,
        globalinfo, globallookup, localinfo, ilocalinfo, ilocalrefs, statinfo
  local explist1, expr, block, exp1, body, chunk
  local block_follow = {}
  for v in gmatch("else elseif end until <eof>", "%S+") do block_follow[v] = true end
  local binopr_left = {}
  local binopr_right = {}
  for op, lt, rt in gmatch([[
{+ 6 6}{- 6 6}{* 7 7}{/ 7 7}{% 7 7}
{^ 10 9}{.. 5 4}
{~= 3 3}{== 3 3}
{< 3 3}{<= 3 3}{> 3 3}{>= 3 3}
{and 2 2}{or 1 1}
]], "{(%S+)%s(%d+)%s(%d+)}") do
    binopr_left[op] = lt + 0; binopr_right[op] = rt + 0
  end
  local unopr = { ["not"]=true, ["-"]=true, ["#"]=true }
  local UNARY_PRIORITY = 8
  local function errorline(s, line2)
    local e = M.error or error
    e(fmt("(source):%d: %s", line2 or ln, s))
  end
  local function nextt()
    lastln = toklnlist[tpos]
    tok, seminfo, ln, xref = toklist[tpos], seminfolist[tpos], toklnlist[tpos], xreflist[tpos]
    tpos = tpos + 1
  end
  local function lookahead() return toklist[tpos] end
  local function syntaxerror(msg)
    if tok ~= "<number>" and tok ~= "<string>" then
      if tok == "<n>" then tok = seminfo end
      tok = "'"..tok.."'"
    end
    errorline(msg.." near "..tok)
  end
  local function error_expected(token) syntaxerror("'"..token.."' expected") end
  local function testnext(c) if tok == c then nextt(); return true end end
  local function check(c) if tok ~= c then error_expected(c) end end
  local function checknext(c) check(c); nextt() end
  local function check_condition(c, msg) if not c then syntaxerror(msg) end end
  local function check_match(what, who, where)
    if not testnext(what) then
      if where == ln then error_expected(what)
      else syntaxerror("'"..what.."' expected (to close '"..who.."' at line "..where..")") end
    end
  end
  local function str_checkname()
    check("<n>"); local ts = seminfo; nameref = xref; nextt(); return ts
  end
  local function new_localvar(name, special)
    local bl = fs.bl
    local locallist = bl and bl.locallist or fs.locallist
    local id = #localinfo + 1
    localinfo[id] = { name=name, xref={nameref}, decl=nameref }
    if special or name == "_ENV" then localinfo[id].is_special = true end
    local i = #ilocalinfo + 1
    ilocalinfo[i] = id; ilocalrefs[i] = locallist
  end
  local function adjustlocalvars(nvars)
    local sz = #ilocalinfo
    while nvars > 0 do
      nvars = nvars - 1
      local i = sz - nvars
      local id = ilocalinfo[i]
      local obj = localinfo[id]
      local name = obj.name
      obj.act = xref; ilocalinfo[i] = nil
      local locallist = ilocalrefs[i]; ilocalrefs[i] = nil
      local existing = locallist[name]
      if existing then obj = localinfo[existing]; obj.rem = -id end
      locallist[name] = id
    end
  end
  local function removevars()
    local bl = fs.bl
    local locallist = bl and bl.locallist or fs.locallist
    for _, id in pairs(locallist) do localinfo[id].rem = xref end
  end
  local function new_localvarliteral(name, special)
    if name:sub(1,1) == "(" then return end
    new_localvar(name, special)
  end
  local function searchvar(fs2, n)
    local bl = fs2.bl
    if bl then
      local locallist = bl.locallist
      while locallist do
        if locallist[n] then return locallist[n] end
        bl = bl.prev; locallist = bl and bl.locallist
      end
    end
    local locallist = fs2.locallist
    return locallist[n] or -1
  end
  local function singlevaraux(fs2, n, var)
    if fs2 == nil then var.k = "VGLOBAL"; return "VGLOBAL"
    else
      local v = searchvar(fs2, n)
      if v >= 0 then var.k = "VLOCAL"; var.id = v; return "VLOCAL"
      else
        if singlevaraux(fs2.prev, n, var) == "VGLOBAL" then return "VGLOBAL" end
        var.k = "VUPVAL"; return "VUPVAL"
      end
    end
  end
  local function singlevar(v)
    local name = str_checkname()
    singlevaraux(fs, name, v)
    if v.k == "VGLOBAL" then
      local id = globallookup[name]
      if not id then
        id = #globalinfo + 1
        globalinfo[id] = { name=name, xref={nameref} }
        globallookup[name] = id
      else
        local obj = globalinfo[id].xref; obj[#obj+1] = nameref
      end
    else
      local obj = localinfo[v.id].xref; obj[#obj+1] = nameref
    end
  end
  local function enterblock(isbreakable)
    local bl = { isbreakable=isbreakable, prev=fs.bl, locallist={} }
    fs.bl = bl
  end
  local function leaveblock() local bl = fs.bl; removevars(); fs.bl = bl.prev end
  local function open_func()
    local new_fs = (not fs) and top_fs or {}
    new_fs.prev = fs; new_fs.bl = nil; new_fs.locallist = {}; fs = new_fs
  end
  local function close_func() removevars(); fs = fs.prev end
  local function field(v) nextt(); str_checkname(); v.k = "VINDEXED" end
  local function yindex() nextt(); expr({}); checknext("]") end
  local function recfield()
    if tok == "<n>" then str_checkname() else yindex() end
    checknext("="); expr({})
  end
  local function listfield(cc) expr(cc.v) end
  local function constructor(t)
    local line2 = ln
    local cc = { v={ k="VVOID" } }
    t.k = "VRELOCABLE"; checknext("{")
    repeat
      if tok == "}" then break end
      local c = tok
      if c == "<n>" then
        if lookahead() ~= "=" then listfield(cc) else recfield() end
      elseif c == "[" then recfield()
      else listfield(cc) end
    until not testnext(",") and not testnext(";")
    check_match("}", "{", line2)
  end
  local function parlist()
    local nparams = 0
    if tok ~= ")" then
      repeat
        local c = tok
        if c == "<n>" then new_localvar(str_checkname()); nparams = nparams + 1
        elseif c == "..." then nextt(); fs.is_vararg = true
        else syntaxerror("<n> or '...' expected") end
      until fs.is_vararg or not testnext(",")
    end
    adjustlocalvars(nparams)
  end
  local function funcargs(f)
    local line2 = ln; local c = tok
    if c == "(" then
      if line2 ~= lastln then syntaxerror("ambiguous syntax (function call x new statement)") end
      nextt()
      if tok ~= ")" then explist1() end
      check_match(")", "(", line2)
    elseif c == "{" then constructor({})
    elseif c == "<string>" then nextt()
    else syntaxerror("function arguments expected"); return end
    f.k = "VCALL"
  end
  local function prefixexp(v)
    local c = tok
    if c == "(" then
      local line2 = ln; nextt(); expr(v); check_match(")", "(", line2)
    elseif c == "<n>" then singlevar(v)
    else syntaxerror("unexpected symbol") end
  end
  local function primaryexp(v)
    prefixexp(v)
    while true do
      local c = tok
      if c == "." then field(v)
      elseif c == "[" then v.k = "VLOCAL"; yindex()
      elseif c == ":" then nextt(); str_checkname(); funcargs(v)
      elseif c == "(" or c == "<string>" or c == "{" then funcargs(v)
      else return end
    end
  end
  local function simpleexp(v)
    local c = tok
    if c == "<number>" then v.k = "VKNUM"
    elseif c == "<string>" then v.k = "VK"
    elseif c == "nil" then v.k = "VNIL"
    elseif c == "true" then v.k = "VTRUE"
    elseif c == "false" then v.k = "VFALSE"
    elseif c == "..." then
      check_condition(fs.is_vararg == true, "cannot use '...' outside a vararg function")
      v.k = "VVARARG"
    elseif c == "{" then constructor(v); return
    elseif c == "function" then nextt(); body(false, ln); return
    else primaryexp(v); return end
    nextt()
  end
  local function subexpr(v, limit)
    local op = tok
    local uop = unopr[op]
    if uop then nextt(); subexpr(v, UNARY_PRIORITY) else simpleexp(v) end
    op = tok
    local binop = binopr_left[op]
    while binop and binop > limit do
      nextt(); op = subexpr({}, binopr_right[op]); binop = binopr_left[op]
    end
    return op
  end
  function expr(v) subexpr(v, 0) end
  local function assignment(v)
    local c = v.v.k
    check_condition(c=="VLOCAL" or c=="VUPVAL" or c=="VGLOBAL" or c=="VINDEXED", "syntax error")
    if testnext(",") then
      local nv = { v={} }; primaryexp(nv.v); assignment(nv)
    else
      local op = tok
      if op=="=" or op=="+=" or op=="-=" or op=="*=" or op=="/=" or op=="%=" then nextt()
      else error_expected("=") end
      explist1(); return
    end
  end
  local function forbody(nvars)
    checknext("do"); enterblock(false); adjustlocalvars(nvars); block(); leaveblock()
  end
  local function fornum(varname)
    new_localvarliteral("(for index)"); new_localvarliteral("(for limit)"); new_localvarliteral("(for step)")
    new_localvar(varname); checknext("="); exp1(); checknext(","); exp1()
    if testnext(",") then exp1() end
    forbody(1)
  end
  local function forlist(indexname)
    new_localvarliteral("(for generator)"); new_localvarliteral("(for state)"); new_localvarliteral("(for control)")
    new_localvar(indexname)
    local nvars = 1
    while testnext(",") do new_localvar(str_checkname()); nvars = nvars + 1 end
    checknext("in"); explist1(); forbody(nvars)
  end
  local function funcname(v)
    local needself = false; singlevar(v)
    while tok == "." do field(v) end
    if tok == ":" then needself = true; field(v) end
    return needself
  end
  function exp1() expr({}) end
  local function cond() expr({}) end
  local function test_then_block() nextt(); cond(); checknext("then"); block() end
  local function localfunc() new_localvar(str_checkname()); adjustlocalvars(1); body(false, ln) end
  local function localstat()
    local nvars = 0
    repeat new_localvar(str_checkname()); nvars = nvars + 1 until not testnext(",")
    if testnext("=") then explist1() end
    adjustlocalvars(nvars)
  end
  function explist1() local e = {}; expr(e); while testnext(",") do expr(e) end end
  function body(needself, line2)
    open_func(); checknext("(")
    if needself then new_localvarliteral("self", true); adjustlocalvars(1) end
    parlist(); checknext(")"); chunk()
    check_match("end", "function", line2); close_func()
  end
  function block() enterblock(false); chunk(); leaveblock() end
  local function for_stat()
    local line2 = line; enterblock(true); nextt()
    local varname = str_checkname(); local c = tok
    if c == "=" then fornum(varname)
    elseif c == "," or c == "in" then forlist(varname)
    else syntaxerror("'=' or 'in' expected") end
    check_match("end", "for", line2); leaveblock()
  end
  local function while_stat()
    local line2 = line; nextt(); cond(); enterblock(true)
    checknext("do"); block(); check_match("end", "while", line2); leaveblock()
  end
  local function repeat_stat()
    local line2 = line; enterblock(true); enterblock(false); nextt()
    chunk(); check_match("until", "repeat", line2); cond()
    leaveblock(); leaveblock()
  end
  local function if_stat()
    local line2 = line; test_then_block()
    while tok == "elseif" do test_then_block() end
    if tok == "else" then nextt(); block() end
    check_match("end", "if", line2)
  end
  local function return_stat()
    nextt(); local c = tok
    if not (block_follow[c] or c == ";") then explist1() end
  end
  local function break_stat()
    local bl = fs.bl; nextt()
    while bl and not bl.isbreakable do bl = bl.prev end
    if not bl then syntaxerror("no loop to break") end
  end
  local function continue_stat() nextt() end
  local function label_stat() nextt(); str_checkname(); checknext("::") end
  local function goto_stat() nextt(); str_checkname() end
  local function expr_stat()
    local id = tpos - 1; local v = { v={} }
    primaryexp(v.v)
    if v.v.k == "VCALL" then statinfo[id] = "call"
    else v.prev = nil; assignment(v); statinfo[id] = "assign" end
  end
  local function function_stat()
    local line2 = line; nextt(); local needself = funcname({}); body(needself, line2)
  end
  local function do_stat()
    local line2 = line; nextt(); block(); check_match("end", "do", line2)
  end
  local function local_stat()
    nextt()
    if testnext("function") then localfunc() else localstat() end
  end
  local stat_call = {
    ["if"]=if_stat, ["while"]=while_stat, ["do"]=do_stat,
    ["for"]=for_stat, ["repeat"]=repeat_stat, ["function"]=function_stat,
    ["local"]=local_stat, ["return"]=return_stat, ["break"]=break_stat,
    ["continue"]=continue_stat, ["goto"]=goto_stat, ["::"]=label_stat,
  }
  local function stat()
    line = ln; local c = tok; local fn = stat_call[c]
    if fn then
      statinfo[tpos-1] = c; fn()
      if c == "return" then return true end
    else expr_stat() end
    return false
  end
  function chunk()
    local islast = false
    while not islast and not block_follow[tok] do islast = stat(); testnext(";") end
  end
  local function init(tokorig, seminfoorig, toklnorig)
    tpos = 1; top_fs = {}
    local j = 1
    toklist, seminfolist, toklnlist, xreflist = {}, {}, {}, {}
    for i = 1, #tokorig do
      local t = tokorig[i]; local yep = true
      if t == "TK_KEYWORD" or t == "TK_OP" then t = seminfoorig[i]
      elseif t == "TK_NAME" then t = "<n>"; seminfolist[j] = seminfoorig[i]
      elseif t == "TK_NUMBER" then t = "<number>"; seminfolist[j] = 0
      elseif t == "TK_STRING" or t == "TK_LSTRING" then t = "<string>"; seminfolist[j] = ""
      elseif t == "TK_EOS" then t = "<eof>"
      else yep = false end
      if yep then toklist[j]=t; toklnlist[j]=toklnorig[i]; xreflist[j]=i; j=j+1 end
    end
    globalinfo, globallookup, localinfo = {}, {}, {}
    ilocalinfo, ilocalrefs = {}, {}
    statinfo = {}
  end
  function M.parse(tokens, seminfo2, tokens_ln)
    init(tokens, seminfo2, tokens_ln)
    open_func(); fs.is_vararg = true; nextt(); chunk(); check("<eof>"); close_func()
    return {
      globalinfo=globalinfo, localinfo=localinfo, statinfo=statinfo,
      toklist=toklist, seminfolist=seminfolist, toklnlist=toklnlist, xreflist=xreflist,
    }
  end
  return M
end)()

local optparser = (function()
  local byte = string.byte
  local char = string.char
  local concat = table.concat
  local fmt = string.format
  local pairs = pairs
  local rep = string.rep
  local sort = table.sort
  local sub = string.sub
  local M = {}
  local LETTERS = "etaoinshrdlucmfwypvbgkqjxz_ETAOINSHRDLUCMFWYPVBGKQJXZ"
  local ALPHANUM = "etaoinshrdlucmfwypvbgkqjxz_0123456789ETAOINSHRDLUCMFWYPVBGKQJXZ"
  local SKIP_NAME = {}
  for v in ([[and break continue do else elseif end false for function if in local nil not or repeat return then true until while self _ENV]]):gmatch("%S+") do
    SKIP_NAME[v] = true
  end
  local toklist, seminfolist, tokpar, seminfopar, xrefpar,
        globalinfo, localinfo, statinfo, globaluniq, localuniq, var_new, varlist

  local function preprocess(infotable)
    local uniqtable = {}
    for i = 1, #infotable do
      local obj = infotable[i]
      local name = obj.name
      if not uniqtable[name] then uniqtable[name] = { decl=0, token=0, size=0 } end
      local uniq = uniqtable[name]
      uniq.decl = uniq.decl + 1
      local xref = obj.xref
      local xcount = #xref
      uniq.token = uniq.token + xcount
      uniq.size = uniq.size + xcount * #name
      if obj.decl then
        obj.id = i
        obj.xcount = xcount
        if xcount > 1 then
          obj.first = xref[2]
          obj.last = xref[xcount]
        end
      else
        uniq.id = i
      end
    end
    return uniqtable
  end

  local function recalc_for_entropy(option)
    local ACCEPT = {
      TK_KEYWORD=true, TK_NAME=true, TK_NUMBER=true,
      TK_STRING=true, TK_LSTRING=true,
    }
    if not option["opt-comments"] then
      ACCEPT.TK_COMMENT = true
      ACCEPT.TK_LCOMMENT = true
    end
    local filtered = {}
    for i = 1, #toklist do filtered[i] = seminfolist[i] end
    for i = 1, #localinfo do
      local obj = localinfo[i]
      local xref = obj.xref
      for j = 1, obj.xcount do
        local p = xref[j]
        filtered[p] = ""
      end
    end
    local freq = {}
    for i = 0, 255 do freq[i] = 0 end
    for i = 1, #toklist do
      local tok2, info = toklist[i], filtered[i]
      if ACCEPT[tok2] then
        for j = 1, #info do
          local c = byte(info, j)
          freq[c] = freq[c] + 1
        end
      end
    end
    local function resort(symbols)
      local symlist = {}
      for i = 1, #symbols do
        local c = byte(symbols, i)
        symlist[i] = { c=c, freq=freq[c] }
      end
      sort(symlist, function(v1, v2) return v1.freq > v2.freq end)
      local charlist = {}
      for i = 1, #symlist do charlist[i] = char(symlist[i].c) end
      return concat(charlist)
    end
    LETTERS = resort(LETTERS)
    ALPHANUM = resort(ALPHANUM)
  end

  local function new_var_name()
    local var
    local cletters, calphanum = #LETTERS, #ALPHANUM
    local v = var_new
    if v < cletters then
      v = v + 1
      var = sub(LETTERS, v, v)
    else
      local range, sz = cletters, 1
      repeat
        v = v - range
        range = range * calphanum
        sz = sz + 1
      until range > v
      local n = v % cletters
      v = (v - n) / cletters
      n = n + 1
      var = sub(LETTERS, n, n)
      while sz > 1 do
        local m = v % calphanum
        v = (v - m) / calphanum
        m = m + 1
        var = var..sub(ALPHANUM, m, m)
        sz = sz - 1
      end
    end
    var_new = var_new + 1
    return var, globaluniq[var] ~= nil
  end

  local function optimize_locals(option)
    var_new = 0
    varlist = {}
    globaluniq = preprocess(globalinfo)
    localuniq = preprocess(localinfo)
    if option["opt-entropy"] then
      recalc_for_entropy(option)
    end
    local object = {}
    for i = 1, #localinfo do
      object[i] = localinfo[i]
    end
    sort(object, function(v1, v2) return v1.xcount > v2.xcount end)
    local temp, j, used_specials = {}, 1, {}
    for i = 1, #object do
      local obj = object[i]
      if not obj.is_special then
        temp[j] = obj; j = j + 1
      else
        used_specials[#used_specials+1] = obj.name
      end
    end
    object = temp
    local nobject = #object
    while nobject > 0 do
      local varname, gcollide
      repeat varname, gcollide = new_var_name() until not SKIP_NAME[varname]
      varlist[#varlist+1] = varname
      local oleft = nobject
      if gcollide then
        local gref = globalinfo[globaluniq[varname].id].xref
        local ngref = #gref
        for i = 1, nobject do
          local obj = object[i]
          local act, rem = obj.act, obj.rem
          while rem < 0 do rem = localinfo[-rem].rem end
          local drop
          for jj = 1, ngref do
            local p = gref[jj]
            if p >= act and p <= rem then drop = true end
          end
          if drop then obj.skip = true; oleft = oleft - 1 end
        end
      end
      while oleft > 0 do
        local i = 1
        while object[i].skip do i = i + 1 end
        oleft = oleft - 1
        local obja = object[i]; i = i + 1
        obja.newname = varname; obja.skip = true; obja.done = true
        local first, last = obja.first, obja.last
        local xref = obja.xref
        if first and oleft > 0 then
          local scanleft = oleft
          while scanleft > 0 do
            while object[i].skip do i = i + 1 end
            scanleft = scanleft - 1
            local objb = object[i]; i = i + 1
            local act, rem = objb.act, objb.rem
            while rem < 0 do rem = localinfo[-rem].rem end
            if not(last < act or first > rem) then
              if act >= obja.act then
                for jj = 1, obja.xcount do
                  local p = xref[jj]
                  if p >= act and p <= rem then oleft=oleft-1; objb.skip=true; break end
                end
              else
                if objb.last and objb.last >= obja.act then oleft=oleft-1; objb.skip=true end
              end
            end
            if oleft == 0 then break end
          end
        end
      end
      local temp2, jj = {}, 1
      for i = 1, nobject do
        local obj = object[i]
        if not obj.done then obj.skip=false; temp2[jj]=obj; jj=jj+1 end
      end
      object = temp2; nobject = #object
    end
    for i = 1, #localinfo do
      local obj = localinfo[i]; local xref = obj.xref
      if obj.newname then
        for jj = 1, obj.xcount do seminfolist[xref[jj]] = obj.newname end
        obj.name, obj.oldname = obj.newname, obj.name
      else obj.oldname = obj.name end
    end
    for _, name in ipairs(used_specials) do varlist[#varlist+1] = name end
  end

  function M.optimize(option, _toklist, _seminfolist, xinfo)
    toklist, seminfolist = _toklist, _seminfolist
    tokpar, seminfopar, xrefpar = xinfo.toklist, xinfo.seminfolist, xinfo.xreflist
    globalinfo, localinfo, statinfo = xinfo.globalinfo, xinfo.localinfo, xinfo.statinfo
    if option["opt-locals"] then optimize_locals(option) end
    if option["opt-experimental"] then
      -- optimize_func1 omitted (rarely used)
    end
  end
  return M
end)()

local optlex = (function()
  local find = string.find
  local match = string.match
  local rep = string.rep
  local sub = string.sub
  local tonumber = tonumber
  local tostring = tostring
  local char = string.char
  local M = {}
  M.error = error; M.warn = {}
  local stoks, sinfos, stoklns
  local is_realtoken = { TK_KEYWORD=true, TK_NAME=true, TK_NUMBER=true, TK_STRING=true, TK_LSTRING=true, TK_OP=true, TK_EOS=true }
  local is_faketoken = { TK_COMMENT=true, TK_LCOMMENT=true, TK_EOL=true, TK_SPACE=true }
  local opt_details
  local function atlinestart(i)
    local t = stoks[i-1]
    if i <= 1 or t == "TK_EOL" then return true
    elseif t == "" then return atlinestart(i-1) end
    return false
  end
  local function atlineend(i)
    local t = stoks[i+1]
    if i >= #stoks or t == "TK_EOL" or t == "TK_EOS" then return true
    elseif t == "" then return atlineend(i+1) end
    return false
  end
  local function commenteols(lcomment)
    local sep = #match(lcomment, "^%-%-%[=*%[")
    local z = sub(lcomment, sep+1, -(sep-1))
    local i, c = 1, 0
    while true do
      local p, _, r, s = find(z, "([\r\n])([\r\n]?)", i)
      if not p then break end
      i = p + 1; c = c + 1
      if #s > 0 and r ~= s then i = i + 1 end
    end
    return c
  end
  local function checkpair(i, j)
    local t1, t2 = stoks[i], stoks[j]
    if t1=="TK_STRING" or t1=="TK_LSTRING" or t2=="TK_STRING" or t2=="TK_LSTRING" then return "" end
    if t1=="TK_OP" or t2=="TK_OP" then
      if (t1=="TK_OP" and (t2=="TK_KEYWORD" or t2=="TK_NAME")) or
         (t2=="TK_OP" and (t1=="TK_KEYWORD" or t1=="TK_NAME")) then return "" end
      if t1=="TK_OP" and t2=="TK_OP" then
        local op, op2 = sinfos[i], sinfos[j]
        if (match(op,"^%.%.?$") and match(op2,"^%.")) or
           (match(op,"^[~=<>]$") and op2=="=") or
           (op=="[" and (op2=="[" or op2=="=")) then return " " end
        return ""
      end
      local op = sinfos[i]; if t2=="TK_OP" then op = sinfos[j] end
      if match(op,"^%.%.?%.?$") then return " " end
      return ""
    else return " " end
  end
  local function repack_tokens()
    local dtoks, dinfos, dtoklns = {}, {}, {}
    local j = 1
    for i = 1, #stoks do
      local t = stoks[i]
      if t ~= "" then dtoks[j]=t; dinfos[j]=sinfos[i]; dtoklns[j]=stoklns[i]; j=j+1 end
    end
    stoks, sinfos, stoklns = dtoks, dinfos, dtoklns
  end
  local function do_number(i)
    local z = sinfos[i]; local y
    if match(z,"^0[xX]") then
      local v = tostring(tonumber(z))
      if #v <= #z then z = v else return end
    end
    if match(z,"^%d+$") then
      if tonumber(z) > 0 then y = match(z,"^0*([1-9]%d*)$") else y = "0" end
    elseif not match(z,"[eE]") then
      local p, q = match(z,"^(%d*)%.(%d*)$")
      if p=="" then p="0" end; if q=="" then q="0" end
      if tonumber(q)==0 and p=="0" then y=".0"
      else
        local zc = #match(q,"0*$")
        if zc > 0 then q = sub(q,1,#q-zc) end
        if tonumber(p) > 0 then y = p.."."..q
        else
          y = "."..q
          local v = #match(q,"^0*"); local w = #q-v; local nv = tostring(#q)
          if w+2+#nv < 1+#q then y = sub(q,-w).."e-"..nv end
        end
      end
    else
      local sig, ex = match(z,"^([^eE]+)[eE]([%+%-]?%d+)$")
      ex = tonumber(ex)
      local p, q = match(sig,"^(%d*)%.(%d*)$")
      if p then ex=ex-#q; sig=p..q end
      if tonumber(sig)==0 then y=".0"
      else
        local v = #match(sig,"^0*"); sig=sub(sig,v+1)
        v = #match(sig,"0*$")
        if v>0 then sig=sub(sig,1,#sig-v); ex=ex+v end
        local nex = tostring(ex)
        if ex>=0 and ex<=1+#nex then y=sig..rep("0",ex).."."
        elseif ex<0 and ex>=-#sig then v=#sig+ex; y=sub(sig,1,v).."."..sub(sig,v+1)
        elseif ex<0 and #nex>=-ex-#sig then v=-ex-#sig; y="."..rep("0",v)..sig
        else y=sig.."e"..ex end
      end
    end
    if y and y ~= sinfos[i] then sinfos[i] = y end
  end
  local function do_string(I)
    local info = sinfos[I]; local delim = sub(info,1,1); local ndelim
    if delim=="'" then ndelim='"' elseif delim=='"' then ndelim="'" elseif delim=="`" then ndelim='"' end
    local z = sub(info,2,-2); local i=1; local c_delim,c_ndelim=0,0
    while i<=#z do
      local c=sub(z,i,i)
      if c=="\\" then
        local j=i+1; local d=sub(z,j,j)
        local p=find("abfnrtv\\\n\r\"'0123456789",d,1,true)
        if not p then z=sub(z,1,i-1)..sub(z,j); i=i+1
        elseif p<=8 then i=i+2
        elseif p<=10 then
          local eol=sub(z,j,j+1)
          if eol=="\r\n" or eol=="\n\r" then z=sub(z,1,i).."\n"..sub(z,j+2)
          elseif p==10 then z=sub(z,1,i).."\n"..sub(z,j+1) end
          i=i+2
        elseif p<=12 then
          if d==delim then c_delim=c_delim+1; i=i+2
          else c_ndelim=c_ndelim+1; z=sub(z,1,i-1)..sub(z,j); i=i+1 end
        else
          local s=match(z,"^(%d%d?%d?)",j); j=i+1+#s
          local cv=tonumber(s); local cc=char(cv)
          p=find("\a\b\f\n\r\t\v",cc,1,true)
          if p then s="\\"..sub("abfnrtv",p,p)
          elseif cv<32 then
            if match(sub(z,j,j),"%d") then s="\\"..s else s="\\"..cv end
          elseif cc==delim then s="\\"..cc; c_delim=c_delim+1
          elseif cc=="\\" then s="\\\\"
          else s=cc; if cc==ndelim then c_ndelim=c_ndelim+1 end end
          z=sub(z,1,i-1)..s..sub(z,j); i=i+#s
        end
      else i=i+1; if c==ndelim then c_ndelim=c_ndelim+1 end end
    end
    if c_delim>c_ndelim then
      i=1
      while i<=#z do
        local p,_,r=find(z,"(['\"`])",i)
        if not p then break end
        if r==delim then z=sub(z,1,p-2)..sub(z,p); i=p
        else z=sub(z,1,p-1).."\\"..sub(z,p); i=p+2 end
      end
      delim=ndelim
    end
    z=delim..z..delim
    if z~=sinfos[I] then sinfos[I]=z end
  end
  local function do_lstring(I)
    local info=sinfos[I]; local delim1=match(info,"^%[=*%[")
    local sep=#delim1; local delim2=sub(info,-sep,-1)
    local z=sub(info,sep+1,-(sep+1)); local y=""; local i=1
    while true do
      local p,_,r,s=find(z,"([\r\n])([\r\n]?)",i)
      local ln2
      if not p then ln2=sub(z,i) elseif p>=i then ln2=sub(z,i,p-1) end
      if ln2~="" then
        if match(ln2,"%s+$") then M.warn.LSTRING="trailing whitespace in long string near line "..stoklns[I] end
        y=y..ln2
      end
      if not p then break end
      i=p+1
      if #s>0 and r~=s then i=i+1 end
      if not(i==1 and i==p) then y=y.."\n" end
    end
    if sep>=3 then
      local chk,okay=sep-1
      while chk>=2 do
        local d="%]"..rep("=",chk-2).."%]"
        if not match(y.."]",d) then okay=chk end; chk=chk-1
      end
      if okay then sep=rep("=",okay-2); delim1,delim2="["..sep.."[","]"..sep.."]" end
    end
    sinfos[I]=delim1..y..delim2
  end
  local function do_lcomment(I)
    local info=sinfos[I]; local delim1=match(info,"^%-%-%[=*%[")
    local sep=#delim1; local delim2=sub(info,-(sep-2),-1)
    local z=sub(info,sep+1,-(sep-1)); local y=""; local i=1
    while true do
      local p,_,r,s=find(z,"([\r\n])([\r\n]?)",i)
      local ln2
      if not p then ln2=sub(z,i) elseif p>=i then ln2=sub(z,i,p-1) end
      if ln2~="" then
        local ws=match(ln2,"%s*$")
        if #ws>0 then ln2=sub(ln2,1,-(ws+1)) end
        y=y..ln2
      end
      if not p then break end
      i=p+1
      if #s>0 and r~=s then i=i+1 end
      y=y.."\n"
    end
    sep=sep-2
    if sep>=3 then
      local chk,okay=sep-1
      while chk>=2 do
        local d="%]"..rep("=",chk-2).."%]"
        if not match(y,d) then okay=chk end; chk=chk-1
      end
      if okay then sep=rep("=",okay-2); delim1,delim2="--["..sep.."[","]"..sep.."]" end
    end
    sinfos[I]=delim1..y..delim2
  end
  local function do_comment(i)
    local info=sinfos[i]; local ws=match(info,"%s*$")
    if #ws>0 then info=sub(info,1,-(ws+1)) end; sinfos[i]=info
  end
  local function keep_lcomment(opt_keep, info)
    if not opt_keep then return false end
    local delim1=match(info,"^%-%-%[=*%["); local sep=#delim1
    local z=sub(info,sep+1,-(sep-1))
    if find(z,opt_keep,1,true) then return true end
  end
  function M.optimize(option, toklist2, semlist, toklnlist2)
    local opt_comments=option["opt-comments"]
    local opt_whitespace=option["opt-whitespace"]
    local opt_emptylines=option["opt-emptylines"]
    local opt_eols=option["opt-eols"]
    local opt_strings=option["opt-strings"]
    local opt_numbers=option["opt-numbers"]
    local opt_x=option["opt-experimental"]
    local opt_keep=option.KEEP
    opt_details=option.DETAILS and 0
    if opt_eols then opt_comments=true; opt_whitespace=true; opt_emptylines=true
    elseif opt_x then opt_whitespace=true end
    stoks,sinfos,stoklns=toklist2,semlist,toklnlist2
    local i=1; local tok2,info2; local prev
    local function settoken(t,inf,I2)
      I2=I2 or i; stoks[I2]=t or ""; sinfos[I2]=inf or ""
    end
    if opt_x then
      while true do
        tok2,info2=stoks[i],sinfos[i]
        if tok2=="TK_EOS" then break end
        if tok2=="TK_OP" and info2==";" then settoken("TK_SPACE"," ") end
        i=i+1
      end
      repack_tokens()
    end
    i=1
    while true do
      tok2,info2=stoks[i],sinfos[i]
      local atstart=atlinestart(i)
      if atstart then prev=nil end
      if tok2=="TK_EOS" then break
      elseif tok2=="TK_KEYWORD" or tok2=="TK_NAME" or tok2=="TK_OP" then prev=i
      elseif tok2=="TK_NUMBER" then if opt_numbers then do_number(i) end; prev=i
      elseif tok2=="TK_STRING" or tok2=="TK_LSTRING" then
        if opt_strings then
          if tok2=="TK_STRING" then do_string(i) else do_lstring(i) end
        end
        prev=i
      elseif tok2=="TK_COMMENT" then
        if opt_comments then
          if i==1 and sub(info2,1,1)=="#" then do_comment(i) else settoken() end
        elseif opt_whitespace then do_comment(i) end
      elseif tok2=="TK_LCOMMENT" then
        if keep_lcomment(opt_keep,info2) then
          if opt_whitespace then do_lcomment(i) end; prev=i
        elseif opt_comments then
          local eols=commenteols(info2)
          if is_faketoken[stoks[i+1]] then settoken(); tok2=""
          else settoken("TK_SPACE"," ") end
          if not opt_emptylines and eols>0 then settoken("TK_EOL",rep("\n",eols)) end
          if opt_whitespace and tok2~="" then i=i-1 end
        else
          if opt_whitespace then do_lcomment(i) end; prev=i
        end
      elseif tok2=="TK_EOL" then
        if atstart and opt_emptylines then settoken()
        elseif info2=="\r\n" or info2=="\n\r" then settoken("TK_EOL","\n") end
      elseif tok2=="TK_SPACE" then
        if opt_whitespace then
          if atstart or atlineend(i) then settoken()
          else
            local ptok=stoks[prev]
            if ptok=="TK_LCOMMENT" then settoken()
            else
              local ntok=stoks[i+1]
              if is_faketoken[ntok] then
                if (ntok=="TK_COMMENT" or ntok=="TK_LCOMMENT") and ptok=="TK_OP" and sinfos[prev]=="-" then
                else settoken() end
              else
                local s=checkpair(prev,i+1)
                if s=="" then settoken() else settoken("TK_SPACE"," ") end
              end
            end
          end
        end
      else error("unidentified token encountered") end
      i=i+1
    end
    repack_tokens()
    if opt_eols then
      i=1
      if stoks[1]=="TK_COMMENT" then i=3 end
      while true do
        tok2=stoks[i]
        if tok2=="TK_EOS" then break
        elseif tok2=="TK_EOL" then
          local t1,t2=stoks[i-1],stoks[i+1]
          if is_realtoken[t1] and is_realtoken[t2] then
            local s=checkpair(i-1,i+1)
            if s=="" or t2=="TK_EOS" then settoken() end
          end
        end
        i=i+1
      end
      repack_tokens()
    end
    return stoks,sinfos,stoklns
  end
  return M
end)()

local equiv = (function()
  local dump = string.dump
  local load2 = loadstring or load
  local sub = string.sub
  local M = {}
  local is_realtoken = { TK_KEYWORD=true, TK_NAME=true, TK_NUMBER=true, TK_STRING=true, TK_LSTRING=true, TK_OP=true, TK_EOS=true }
  local option, llex2, warn
  function M.init(_option, _llex, _warn) option=_option; llex2=_llex; warn=_warn end
  local function build_stream(s)
    local stok, sseminfo = llex2.lex(s)
    local tok, seminfo = {}, {}
    for i = 1, #stok do
      local t = stok[i]
      if is_realtoken[t] then tok[#tok+1]=t; seminfo[#seminfo+1]=sseminfo[i] end
    end
    return tok, seminfo
  end
  function M.source(z, dat)
    local function dumpsem(s)
      local sf = load2("return "..s, "z")
      if sf then return dump(sf) end
    end
    local function bork(msg)
      if option.DETAILS then print("SRCEQUIV: "..msg) end
      warn.SRC_EQUIV = true
    end
    local tok1, seminfo1 = build_stream(z)
    local tok2, seminfo2 = build_stream(dat)
    local sh1 = z:match("^(#[^\r\n]*)")
    local sh2 = dat:match("^(#[^\r\n]*)")
    if sh1 or sh2 then
      if not sh1 or not sh2 or sh1~=sh2 then bork("shbang lines different") end
    end
    if #tok1~=#tok2 then bork("count "..(#tok1).." "..(#tok2)); return end
    for i = 1, #tok1 do
      local t1,t2=tok1[i],tok2[i]
      local s1,s2=seminfo1[i],seminfo2[i]
      if t1~=t2 then bork("type ["..i.."] "..t1.." "..t2); break end
      if t1=="TK_KEYWORD" or t1=="TK_NAME" or t1=="TK_OP" then
        if t1=="TK_NAME" and option["opt-locals"] then
        elseif s1~=s2 then bork("seminfo ["..i.."] "..t1.." "..s1.." "..s2); break end
      elseif t1=="TK_EOS" then
      else
        local s1b,s2b=dumpsem(s1),dumpsem(s2)
        if not s1b or not s2b or s1b~=s2b then
          bork("seminfo ["..i.."] "..t1.." "..s1.." "..s2); break
        end
      end
    end
  end
  return M
end)()

local M = {}
M.NONE_OPTS = {
  binequiv=false, comments=false, emptylines=false, entropy=false,
  eols=false, experimental=false, locals=false, numbers=false,
  srcequiv=false, strings=false, whitespace=false,
}
M.BASIC_OPTS = merge(M.NONE_OPTS, { comments=true, emptylines=true, srcequiv=true, whitespace=true })
M.DEFAULT_OPTS = merge(M.BASIC_OPTS, { locals=true, numbers=true })
M.MAXIMUM_OPTS = merge(M.DEFAULT_OPTS, { entropy=true, eols=true, strings=false, srcequiv=false })

local function noop() return end
local function opts_to_legacy(opts)
  local res = {}
  for key, val in pairs(opts) do res['opt-'..key] = val end
  return res
end

function M.optimize(opts, source)
  assert(source and type(source) == 'string', 'bad argument #2: expected string, got a '..type(source))
  opts = opts and merge(M.NONE_OPTS, opts) or M.DEFAULT_OPTS
  local legacy_opts = opts_to_legacy(opts)
  local toklist, seminfolist, toklnlist = llex.lex(source)
  local xinfo = lparser.parse(toklist, seminfolist, toklnlist)
  optparser.optimize(legacy_opts, toklist, seminfolist, xinfo)
  local warn = optlex.warn
  optlex.print = noop
  local _, seminfolist2 = optlex.optimize(legacy_opts, toklist, seminfolist, toklnlist)
  local optim_source = table.concat(seminfolist2)
  if opts.srcequiv and not opts.experimental then
    equiv.init(legacy_opts, llex, warn)
    equiv.source(source, optim_source)
    if warn.SRC_EQUIV then error('Source equivalence test failed!') end
  end
  return optim_source:gsub("\n", " ")
end

return M
end)()

return minifier
