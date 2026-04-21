local fmt = string.format
local gmatch = string.gmatch
local pairs = pairs

local M = {}

local toklist, seminfolist, toklnlist, xreflist, tpos,
      line, lastln, tok, seminfo, ln, xref, nameref,
      fs, top_fs,
      globalinfo, globallookup, localinfo,
      ilocalinfo, ilocalrefs, statinfo

local explist1, expr, block, exp1, body, chunk

local block_follow = {}
for v in gmatch("else elseif end until <eof>", "%S+") do block_follow[v] = true end

local binopr_left, binopr_right = {}, {}
for op, lt, rt in gmatch([[
{+ 6 6}{- 6 6}{* 7 7}{/ 7 7}{% 7 7}{// 7 7}
{^ 10 9}{.. 5 4}
{~= 3 3}{== 3 3}
{< 3 3}{<= 3 3}{> 3 3}{>= 3 3}
{and 2 2}{or 1 1}
]], "{(%S+)%s(%d+)%s(%d+)}") do
  binopr_left[op] = lt + 0; binopr_right[op] = rt + 0
end

local unopr = { ["not"]=true, ["-"]=true, ["#"]=true, ["~"]=true }
local UNARY_PRIORITY = 8

local function errorline(s, line)
  local e = M.error or error
  e(fmt("(source):%d: %s", line or ln, s))
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
    local id = ilocalinfo[i]; local obj = localinfo[id]
    local name = obj.name; obj.act = xref; ilocalinfo[i] = nil
    local locallist = ilocalrefs[i]; ilocalrefs[i] = nil
    local existing = locallist[name]
    if existing then localinfo[existing].rem = -id end
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

local function searchvar(fs, n)
  local bl = fs.bl; local locallist
  if bl then
    locallist = bl.locallist
    while locallist do
      if locallist[n] then return locallist[n] end
      bl = bl.prev; locallist = bl and bl.locallist
    end
  end
  locallist = fs.locallist; return locallist[n] or -1
end

local function singlevaraux(fs, n, var)
  if fs == nil then var.k = "VGLOBAL"; return "VGLOBAL"
  else
    local v = searchvar(fs, n)
    if v >= 0 then var.k = "VLOCAL"; var.id = v; return "VLOCAL"
    else
      if singlevaraux(fs.prev, n, var) == "VGLOBAL" then return "VGLOBAL" end
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
    else globalinfo[id].xref[#globalinfo[id].xref+1] = nameref end
  else localinfo[v.id].xref[#localinfo[v.id].xref+1] = nameref end
end

local function enterblock(isbreakable)
  fs.bl = { isbreakable=isbreakable, prev=fs.bl, locallist={} }
end

local function leaveblock() removevars(); fs.bl = fs.bl.prev end

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

local function constructor(t)
  local line = ln; local cc = { v = { k="VVOID" } }
  t.k = "VRELOCABLE"; checknext("{")
  repeat
    if tok == "}" then break end
    local c = tok
    if c == "<n>" then
      if lookahead() ~= "=" then expr(cc.v) else recfield() end
    elseif c == "[" then recfield()
    else expr(cc.v) end
  until not testnext(",") and not testnext(";")
  check_match("}", "{", line)
end

local function parlist()
  local nparams = 0
  if tok ~= ")" then
    repeat
      if tok == "<n>" then new_localvar(str_checkname()); nparams = nparams + 1
      elseif tok == "..." then nextt(); fs.is_vararg = true
      else syntaxerror("<n> or '...' expected") end
    until fs.is_vararg or not testnext(",")
  end
  adjustlocalvars(nparams)
end

local function funcargs(f)
  local line = ln; local c = tok
  if c == "(" then
    if line ~= lastln then syntaxerror("ambiguous syntax (function call x new statement)") end
    nextt()
    if tok ~= ")" then explist1() end
    check_match(")", "(", line)
  elseif c == "{" then constructor({})
  elseif c == "<string>" then nextt()
  else syntaxerror("function arguments expected"); return end
  f.k = "VCALL"
end

local function prefixexp(v)
  local c = tok
  if c == "(" then
    local line = ln; nextt(); expr(v); check_match(")", "(", line)
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
  if unopr[op] then nextt(); subexpr(v, UNARY_PRIORITY)
  else simpleexp(v) end
  op = tok
  local binop = binopr_left[op]
  while binop and binop > limit do
    nextt()
    op = subexpr({}, binopr_right[op])
    binop = binopr_left[op]
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
    -- Lua 5.1: =   Luau: +=  -=  *=  /=  %=  ^=  ..=  //=
    if op=="=" or op=="+=" or op=="-=" or op=="*=" or op=="/=" or
       op=="%=" or op=="^=" or op=="..=" or op=="//=" then nextt()
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
  new_localvar(indexname); local nvars = 1
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

local function test_then_block()
  nextt(); cond(); checknext("then"); block()
end

local function localfunc() new_localvar(str_checkname()); adjustlocalvars(1); body(false, ln) end

local function localstat()
  local nvars = 0
  repeat new_localvar(str_checkname()); nvars = nvars + 1 until not testnext(",")
  if testnext("=") then explist1() end
  adjustlocalvars(nvars)
end

function explist1() local e={}; expr(e); while testnext(",") do expr(e) end end

function body(needself, line)
  open_func(); checknext("(")
  if needself then new_localvarliteral("self", true); adjustlocalvars(1) end
  parlist(); checknext(")")
  chunk(); check_match("end", "function", line); close_func()
end

function block() enterblock(false); chunk(); leaveblock() end

local function for_stat()
  local line = line; enterblock(true); nextt()
  local varname = str_checkname(); local c = tok
  if c == "=" then fornum(varname)
  elseif c == "," or c == "in" then forlist(varname)
  else syntaxerror("'=' or 'in' expected") end
  check_match("end", "for", line); leaveblock()
end

local function while_stat()
  local line = line; nextt(); cond(); enterblock(true); checknext("do"); block()
  check_match("end", "while", line); leaveblock()
end

local function repeat_stat()
  local line = line; enterblock(true); enterblock(false); nextt(); chunk()
  check_match("until", "repeat", line); cond(); leaveblock(); leaveblock()
end

local function if_stat()
  local line = line; test_then_block()
  while tok == "elseif" do test_then_block() end
  if tok == "else" then nextt(); block() end
  check_match("end", "if", line)
end

local function return_stat()
  nextt(); local c = tok
  if not block_follow[c] and c ~= ";" then explist1() end
end

local function break_stat()
  local bl = fs.bl; nextt()
  while bl and not bl.isbreakable do bl = bl.prev end
  if not bl then syntaxerror("no loop to break") end
end

-- Luau: continue (valid inside loops)
local function continue_stat()
  local bl = fs.bl; nextt()
  while bl and not bl.isbreakable do bl = bl.prev end
  -- allow silently; real validation is runtime
end

local function label_stat() nextt(); str_checkname(); checknext("::") end
local function goto_stat() nextt(); str_checkname() end

local function expr_stat()
  local id = tpos - 1; local v = { v={} }; primaryexp(v.v)
  if v.v.k == "VCALL" then statinfo[id] = "call"
  else v.prev = nil; assignment(v); statinfo[id] = "assign" end
end

local function function_stat()
  local line = line; nextt(); local needself = funcname({}); body(needself, line)
end

local function do_stat()
  local line = line; nextt(); block(); check_match("end", "do", line)
end

local function local_stat()
  nextt()
  if testnext("function") then localfunc() else localstat() end
end

local stat_call = {
  ["if"]=if_stat, ["while"]=while_stat, ["do"]=do_stat,
  ["for"]=for_stat, ["repeat"]=repeat_stat, ["function"]=function_stat,
  ["local"]=local_stat, ["return"]=return_stat, ["break"]=break_stat,
  ["continue"]=continue_stat, ["goto"]=goto_stat, ["::"] = label_stat,
}

local function stat()
  line = ln; local c = tok; local fn = stat_call[c]
  if fn then
    statinfo[tpos - 1] = c; fn()
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
    local tok = tokorig[i]; local yep = true
    if tok == "TK_KEYWORD" or tok == "TK_OP" then tok = seminfoorig[i]
    elseif tok == "TK_NAME" then tok = "<n>"; seminfolist[j] = seminfoorig[i]
    elseif tok == "TK_NUMBER" then tok = "<number>"; seminfolist[j] = 0
    elseif tok == "TK_STRING" or tok == "TK_LSTRING" then tok = "<string>"; seminfolist[j] = ""
    elseif tok == "TK_EOS" then tok = "<eof>"
    else yep = false end
    if yep then toklist[j]=tok; toklnlist[j]=toklnorig[i]; xreflist[j]=i; j=j+1 end
  end
  globalinfo, globallookup, localinfo = {}, {}, {}
  ilocalinfo, ilocalrefs = {}, {}
  statinfo = {}
end

function M.parse(tokens, seminfo, tokens_ln)
  init(tokens, seminfo, tokens_ln)
  open_func(); fs.is_vararg = true; nextt(); chunk(); check("<eof>"); close_func()
  return {
    globalinfo=globalinfo, localinfo=localinfo, statinfo=statinfo,
    toklist=toklist, seminfolist=seminfolist, toklnlist=toklnlist, xreflist=xreflist,
  }
end

return M
