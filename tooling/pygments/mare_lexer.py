from pygments.lexer import RegexLexer, bygroups
from pygments.token import *

__all__ = ['MareLexer']

class MareLexer(RegexLexer):
  """
  For `Mare <https://github.com/jemc/mare>`_ source code.
  """

  name = 'Mare'
  aliases = ['mare']
  filenames = ['*.mare']

  root_rules = [
    # Line Comment
    (r'//.*?$', Comment.Singleline),

    # Doc Comment
    (r'::.*?$', Comment.Singleline),

    # Capability Operator
    (r'(\')(\w+)(?=[^\'])', bygroups(Operator, Name)),

    # Double-Quote String
    (r'\w?"', String.Double, "string.double"),

    # Single-Char String
    (r"'", String.Char, "string.char"),

    # Class (or other type)
    (r'([_A-Z]\w*)', Name.Class),

    # Declare
    (r'^(\s*)(:)(\w+)',
      bygroups(Text, Name.Tag, Name.Tag),
      "decl"),

    # Error-Raising Calls/Names
    (r'((\w+|\+|\-|\*)\!)', Generic.Deleted),

    # Numeric Values
    (r'\b\d([\d_]*(\.[\d_]+)?)\b', Number),

    # Hex Numeric Values
    (r'\b0x([0-9a-fA-F_]+)\b', Number.Hex),

    # Binary Numeric Values
    (r'\b0b([01_]+)\b', Number.Bin),

    # Function Call (with braces)
    (r'(\w+(?:\?|\!)?)(?=\()', Name.Function),

    # Function Call (with receiver)
    (r'(?<=\.)(\w+(?:\?|\!)?)', Name.Function),

    # Function Call (with self receiver)
    (r'(?<=@)(\w+(?:\?|\!)?)', Name.Function),

    # Parenthesis
    (r'\(', Punctuation, "root"),
    (r'\)', Punctuation, "#pop"),

    # Brace
    (r'\{', Punctuation, "root"),
    (r'\}', Punctuation, "#pop"),

    # Bracket
    (r'\[', Punctuation, "root"),
    (r'(\])(\!)', bygroups(Punctuation, Generic.Deleted), "#pop"),
    (r'\]', Punctuation, "#pop"),

    # Expression Separators
    (r'(,|;|:)', Punctuation),

    # Other "Punctuation"
    (r'(@|\.)', Punctuation),

    # Piping Operators
    (r'(\|\>)', Operator),

    # Branching Operators
    (r'(\&\&|\|\||\?\?|\&\?|\|\?|\.\?)', Operator),

    # Comparison Operators
    (r'(\<\=\>|\=\~|\=\=|\<\=|\>\=|\<|\>)', Operator),

    # Arithmetic Operators
    (r'(\+|\-|\/|\*|\%)', Operator),

    # Assignment Operators
    (r'(\=)', Operator),

    # Other Operators
    (r'(\!|\<\<|\<|\&|\|)', Operator),

    # Identifiers
    (r'\b\w+\b', Name),

    # Whitespace
    (r'[ \t\r]+', Text),
  ]

  tokens = {
    "root": root_rules,

    # Declare (nested rules)
    "decl": [
      (r'\b[a-z_]\w*\b(?!\!)', Keyword.Declaration),
      (r':', Punctuation, "#pop"),
      (r'\n', Text, "#pop"),
    ] + root_rules,

    # Double-Quote String (nested rules)
    "string.double": [
      (r'\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]', String.Escape),
      (r'\\x[0-9a-fA-F][0-9a-fA-F]', String.Escape),
      (r'"', String.Double, "#pop"),
      (r'.', String.Double),
    ],

    # Single-Char String (nested rules)
    "string.char": [
      (r'\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]', String.Escape),
      (r'\\x[0-9a-fA-F][0-9a-fA-F]', String.Escape),
      (r'\\[bfnrt\\\']', String.Escape),
      (r"'", String.Char, "#pop"),
      (r'.', String.Char),
    ],
  }
