local byte = string.byte
local char = string.char
local concat = table.concat
local pairs = pairs
local rep = string.rep
local sort = table.sort
local sub = string.sub

local M = {}

local LETTERS = "etaoinshrdlucmfwypvbgkqjxz_ETAOINSHRDLUCMFWYPVBGKQJXZ"
local ALPHANUM = "etaoinshrdlucmfwypvbgkqjxz_0123456789ETAOINSHRDLUCMFWYPVBGKQJXZ"

-- Lua 5.1 + Luau reserved names (never rename to these)
local SKIP_NAME = {}
for v in ([[
and break continue do else elseif end false for function goto if in
local nil not or repeat return then true until while self _ENV]]):gmatch("%S+") do
  SKIP_NAME[v] = true
end

local toklist, seminfolist,
      tokpar, seminfopar, xrefpar,
      globalinfo, localinfo, statinfo,
      globaluniq, localuniq,
      var_new, varlist

local function preprocess(infotable)
  local uniqtable = {}
  for i = 1, #infotable do
    local obj = infotable[i]; local name = obj.name
    if not uniqtable[name] then uniqtable[name] = { decl=0, token=0, size=0 } end
    local uniq = uniqtable[name]
    uniq.decl = uniq.decl + 1
    local xref = obj.xref; local xcount = #xref
    uniq.token = uniq.token + xcount; uniq.size = uniq.size + xcount * #name
    if obj.decl then
      obj.id = i; obj.xcount = xcount
      if xcount > 1 then obj.first = xref[2]; obj.last = xref[xcount] end
    else uniq.id = i end
  end
  return uniqtable
end

local function recalc_for_entropy(option)
  local ACCEPT = { TK_KEYWORD=true, TK_NAME=true, TK_NUMBER=true, TK_STRING=true, TK_LSTRING=true }
  if not option["opt-comments"] then ACCEPT.TK_COMMENT=true; ACCEPT.TK_LCOMMENT=true end
  local filtered = {}
  for i = 1, #toklist do filtered[i] = seminfolist[i] end
  for i = 1, #localinfo do
    local obj = localinfo[i]; local xref = obj.xref
    for j = 1, obj.xcount do filtered[xref[j]] = "" end
  end
  local freq = {}; for i=0,255 do freq[i]=0 end
  for i = 1, #toklist do
    local tok2, info = toklist[i], filtered[i]
    if ACCEPT[tok2] then
      for j = 1, #info do local c = byte(info,j); freq[c] = freq[c]+1 end
    end
  end
  local function resort(symbols)
    local symlist = {}
    for i = 1, #symbols do local c = byte(symbols,i); symlist[i]={c=c,freq=freq[c]} end
    sort(symlist, function(a,b) return a.freq>b.freq or (a.freq==b.freq and a.c<b.c) end)
    local t={}; for i=1,#symlist do t[i]=char(symlist[i].c) end; return concat(t)
  end
  LETTERS = resort(LETTERS); ALPHANUM = resort(ALPHANUM)
end

local function new_var_name()
  local var_name; local gcollide = false
  while true do
    if var_new < #LETTERS then
      var_new = var_new + 1; var_name = sub(LETTERS, var_new, var_new)
    else
      local j = var_new - #LETTERS; var_new = var_new + 1
      local left = j % #ALPHANUM; local right = (j-left)/#ALPHANUM
      var_name = sub(LETTERS,right+1,right+1)..sub(ALPHANUM,left+1,left+1)
    end
    if globaluniq[var_name] then gcollide = true end
    break
  end
  return var_name, gcollide
end

local function optimize_func1()
  local function is_strcall(j)
    return (tokpar[j+1]or"")=="(" and (tokpar[j+2]or"")=="<string>" and (tokpar[j+3]or"")==")";
  end
  local del_list = {}; local i = 1
  while i <= #tokpar do
    if statinfo[i]=="call" and is_strcall(i) then
      del_list[i+1]=true; del_list[i+3]=true; i=i+3
    end
    i=i+1
  end
  local del_list2={}
  do
    local i,dst,idend=1,1,#tokpar
    while dst<=idend do
      if del_list[i] then del_list2[xrefpar[i]]=true; i=i+1 end
      if i>dst then
        if i<=idend then
          tokpar[dst]=tokpar[i]; seminfopar[dst]=seminfopar[i]
          xrefpar[dst]=xrefpar[i]-(i-dst); statinfo[dst]=statinfo[i]
        else tokpar[dst]=nil; seminfopar[dst]=nil; xrefpar[dst]=nil; statinfo[dst]=nil end
      end
      i=i+1; dst=dst+1
    end
  end
  do
    local i,dst,idend=1,1,#toklist
    while dst<=idend do
      if del_list2[i] then i=i+1 end
      if i>dst then
        if i<=idend then toklist[dst]=toklist[i]; seminfolist[dst]=seminfolist[i]
        else toklist[dst]=nil; seminfolist[dst]=nil end
      end
      i=i+1; dst=dst+1
    end
  end
end

local function optimize_locals(option)
  var_new=0; varlist={}
  globaluniq=preprocess(globalinfo); localuniq=preprocess(localinfo)
  if option["opt-entropy"] then recalc_for_entropy(option) end

  local object={}
  for i=1,#localinfo do object[i]=localinfo[i] end
  sort(object, function(v1,v2) return v1.xcount>v2.xcount end)

  local temp,j,used_specials={},1,{}
  for i=1,#object do
    local obj=object[i]
    if not obj.is_special then temp[j]=obj; j=j+1
    else used_specials[#used_specials+1]=obj.name end
  end
  object=temp

  local nobject=#object
  while nobject>0 do
    local varname,gcollide
    repeat varname,gcollide=new_var_name() until not SKIP_NAME[varname]
    varlist[#varlist+1]=varname; local oleft=nobject

    if gcollide then
      local gref=globalinfo[globaluniq[varname].id].xref; local ngref=#gref
      for i=1,nobject do
        local obj=object[i]; local act,rem=obj.act,obj.rem
        while rem<0 do rem=localinfo[-rem].rem end
        local drop
        for j=1,ngref do local p=gref[j]; if p>=act and p<=rem then drop=true end end
        if drop then obj.skip=true; oleft=oleft-1 end
      end
    end

    while oleft>0 do
      local i=1; while object[i].skip do i=i+1 end
      oleft=oleft-1; local obja=object[i]; i=i+1
      obja.newname=varname; obja.skip=true; obja.done=true
      local first,last=obja.first,obja.last; local xref=obja.xref
      if first and oleft>0 then
        local scanleft=oleft
        while scanleft>0 do
          while object[i].skip do i=i+1 end
          scanleft=scanleft-1; local objb=object[i]; i=i+1
          local act,rem=objb.act,objb.rem
          while rem<0 do rem=localinfo[-rem].rem end
          if not(last<act or first>rem) then
            if act>=obja.act then
              for j=1,obja.xcount do
                local p=xref[j]
                if p>=act and p<=rem then oleft=oleft-1; objb.skip=true; break end
              end
            else
              if objb.last and objb.last>=obja.act then oleft=oleft-1; objb.skip=true end
            end
          end
          if oleft==0 then break end
        end
      end
    end

    local temp,j={},1
    for i=1,nobject do
      local obj=object[i]
      if not obj.done then obj.skip=false; temp[j]=obj; j=j+1 end
    end
    object=temp; nobject=#object
  end

  for i=1,#localinfo do
    local obj=localinfo[i]; local xref=obj.xref
    if obj.newname then
      for j=1,obj.xcount do seminfolist[xref[j]]=obj.newname end
      obj.name,obj.oldname=obj.newname,obj.name
    else obj.oldname=obj.name end
  end
  for _,name in ipairs(used_specials) do varlist[#varlist+1]=name end
end

function M.optimize(option, _toklist, _seminfolist, xinfo)
  toklist,seminfolist = _toklist,_seminfolist
  tokpar,seminfopar,xrefpar = xinfo.toklist,xinfo.seminfolist,xinfo.xreflist
  globalinfo,localinfo,statinfo = xinfo.globalinfo,xinfo.localinfo,xinfo.statinfo
  if option["opt-locals"] then optimize_locals(option) end
  if option["opt-experimental"] then optimize_func1() end
end

return M
