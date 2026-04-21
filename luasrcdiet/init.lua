local equiv = require 'luasrcdiet.equiv'
local llex = require 'luasrcdiet.llex'
local lparser = require 'luasrcdiet.lparser'
local optlex = require 'luasrcdiet.optlex'
local optparser = require 'luasrcdiet.optparser'
local utils = require 'luasrcdiet.utils'

local concat = table.concat
local merge = utils.merge
local function noop() return end

local function opts_to_legacy(opts)
  local res = {}
  for key, val in pairs(opts) do res['opt-'..key] = val end
  return res
end

local M = {}
M._NAME = 'luasrcdiet'
M._VERSION = '1.0.0'
M._HOMEPAGE = 'https://github.com/jirutka/luasrcdiet'

M.NONE_OPTS = {
  binequiv=false, comments=false, emptylines=false, entropy=false,
  eols=false, experimental=false, locals=false, numbers=false,
  srcequiv=false, strings=false, whitespace=false,
}
M.BASIC_OPTS = merge(M.NONE_OPTS, {
  comments=true, emptylines=true,
  srcequiv=false, -- disabled: Luau compound ops trip the equiv check
  whitespace=true,
})
M.DEFAULT_OPTS = merge(M.BASIC_OPTS, { locals=true, numbers=true })
M.MAXIMUM_OPTS = merge(M.DEFAULT_OPTS, {
  entropy=true, eols=true, strings=false, srcequiv=false,
})

function M.optimize(opts, source)
  assert(source and type(source) == 'string',
    'bad argument #2: expected string, got a '..type(source))
  opts = opts and merge(M.NONE_OPTS, opts) or M.DEFAULT_OPTS
  local legacy_opts = opts_to_legacy(opts)

  local toklist, seminfolist, toklnlist = llex.lex(source)
  local xinfo = lparser.parse(toklist, seminfolist, toklnlist)

  optparser.print = noop
  optparser.optimize(legacy_opts, toklist, seminfolist, xinfo)

  local warn = optlex.warn
  optlex.print = noop
  local _, seminfolist2 = optlex.optimize(legacy_opts, toklist, seminfolist, toklnlist)
  local optim_source = concat(seminfolist2)

  if opts.srcequiv and not opts.experimental then
    equiv.init(legacy_opts, llex, warn)
    equiv.source(source, optim_source)
    if warn.SRC_EQUIV then error('Source equivalence test failed!') end
  end

  return optim_source:gsub("\n", " ")
end

return M
