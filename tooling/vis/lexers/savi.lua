-- Savi LPeg lexer

local l = require('lexer')
local token, word_match = l.token, l.word_match
local P, R, S = lpeg.P, lpeg.R, lpeg.S

local M = {_NAME = 'Savi'}

-- Whitespace
local ws = token(l.WHITESPACE, l.space^1)

-- Comments
local eol_comment = '//' * l.nonnewline^0
local eol_annotation = '::' * l.nonnewline^0

local comment = token(l.COMMENT, eol_comment + eol_annotation)

-- Numbers (integer and float).
local digit19 = R('19')
local digit = R('09')
local digithex = digit + R('af') + R('AF')
local digitbin = R('01')
local digits = digit^1 + P('_')
local int = (P('0x') * (digithex + P('_'))^1) +
  (P('0b') * (digitbin + P('_'))^1) +
  (P('-') * digit19 * digits) +
  (P('-') * digit) +
  (digit19 * digits) +
  digit
local frac = P('.') * digits
local exp = (P('e') + P('E')) * (P('+') + P('-'))^-1 * digits 
local float = (int * ((frac * exp^-1) + exp))

local number = token(l.NUMBER, int + float)

-- Identifier
local ident_letter = R('az') + R('AZ') + R('09') + P('_')
local ident = (
  (
    (P('^') * digit19 * digit^0) +
    ident_letter^1
  ) * P('!')^-1
)

local identifier = token(l.IDENTIFIER, ident)

-- String
local string = token(l.STRING, (
  ident_letter^-1 * l.delimited_range('"') + 
  P("'") * P(1) * P("'") +
  P("'") * (P("\\") * ident) * P("'")
))

-- Keywords
local keyword = token(l.KEYWORD, (
  (
    P(':') * ident +
    P('|') +
    P('(') + P(')') +
    P('[') + P(']') +
    P('{') + P('}')
  )
))

-- Reference Capabilities and @
local ref_cap_at = token(l.LABEL, (
  word_match{'iso', 'val', 'ref', 'box', 'tag', 'non'} +
  P('@')
))

-- Bang methods, like `as!`
local bang = token(l.ERROR, ident_letter^1 * P('!'))

-- Operators
local operators = token(l.OPERATOR, (
  P('*') + P('/') + P('%') +
  P('+') + P('-') + P('=') + 
  P('<') + P('>') +
  word_match{
    '*!', '+!', '-!', '<+', '<~', '<<', '~>', '<<', '>>', '<~', '~>',
    '<:', '!<', '>=', '<=', '==', '==', '!=', '!=', '=~', '&&', '||',
    '+=', '-=', '<<',
  }
))

-- Rules
M._rules = {
  {'whitespace', ws},
  {'comment', comment},
  {'number', number},
  {'string', string},
  {'keyword', keyword},
  {'label', ref_cap_at},
  {'error', bang},
  {'operator', operators},
  {'identifier', identifier},
}

return M