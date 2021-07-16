require "pegmatite"

module Savi::Parser
  Grammar = Pegmatite::DSL.define do
    # Define what an end-of-line comment/annotation looks like.
    eol_annotation = str("::") >> char(' ').maybe >> (~char('\n') >> any).repeat.named(:annotation)
    eol_comment = (str("//") >> (~char('\n') >> any).repeat) | eol_annotation

    # Define what whitespace looks like.
    whitespace =
      char(' ') | char('\t') | char('\r') | str("\\\n") | str("\\\r\n")
    s = whitespace.repeat
    newline = s >> eol_comment.maybe >> (char('\n') | s.then_eof)
    sn = (whitespace | newline).repeat

    # Define what a number looks like (integer and float).
    digit19 = range('1', '9')
    digit = range('0', '9')
    digithex = digit | range('a', 'f') | range('A', 'F')
    digitbin = range('0', '1')
    digits = digit.repeat(1) | char('_')
    int =
      (str("0x") >> (digithex | char('_')).repeat(1)) |
      (str("0b") >> (digitbin | char('_')).repeat(1)) |
      (char('-') >> digit19 >> digits) |
      (char('-') >> digit) |
      (digit19 >> digits) |
      digit
    frac = char('.') >> digits
    exp = (char('e') | char('E')) >> (char('+') | char('-')).maybe >> digits
    integer = int.named(:integer)
    float = (int >> ((frac >> exp.maybe) | exp)).named(:float)

    # Define what an identifier looks like.
    ident_letter =
      range('a', 'z') | range('A', 'Z') | range('0', '9') | char('_')
    ident = (
      (
        (char('@') >> ident_letter.repeat) |
        (char('^') >> digit19 >> digit.repeat) |
        ident_letter.repeat(1)
      ) >> char('!').maybe
    ).named(:ident)

    # Define what a string looks like.
    string_char =
      str("\\\"") | str("\\\\") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      str("\b")  | str("\f")  | str("\n")  | str("\r")  | str("\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      str("\\").maybe >> (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    string = (
      ident_letter.named(:ident).maybe >>
      char('"') >>
      string_char.repeat.named(:string) >>
      char('"')
    ).named(:string)

    # Define what a character string looks like.
    character_char =
      str("\\'") | str("\\\\") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      str("\b")  | str("\f")  | str("\n")  | str("\r")  | str("\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      (~char('\'') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    character = char('\'') >> character_char.repeat.named(:char) >> char('\'')

    # Define what a heredoc string looks like.
    heredoc_content = declare()
    heredoc = str("<<<") >> heredoc_content.named(:heredoc) >> str(">>>")
    heredoc_no_token = str("<<<") >> heredoc_content >> str(">>>")
    heredoc_content.define \
      (heredoc_no_token | (~str(">>>") >> any)).repeat

    # Define an atom to be a single term with no binary operators.
    parens = declare()
    decl = declare()
    anystring = string | character | heredoc
    atom = parens | anystring | float | integer | ident

    # Define a compound to be a closely bound chain of atoms.
    opcap = char('\'').named(:op)
    opdot = char('.').named(:op)
    oparrow = (str("->")).named(:op)
    compound_without_prefix = (atom >> (
      (opcap >> ident) | \
      (s >> oparrow >> s >> atom) | \
      (sn >> opdot >> sn >> atom) | \
      parens
    ).repeat >> (s >> eol_annotation).maybe).named(:compound)

    # A compound may be optionally preceded by a prefix operator.
    prefixop = (str("--") | char('!') | char('~')).named(:op)
    compound_with_prefix = (prefixop >> compound_without_prefix).named(:prefix)
    compound = compound_with_prefix | compound_without_prefix

    # Define groups of operators, in order of precedence,
    # from most tightly binding to most loosely binding.
    # Operators in the same group have the same level of precedence.
    opw = (char(' ') | char('\t'))
    op1 = (str("*!") | char('*') | char('/') | char('%')).named(:op)
    op2 = (str("+!") | str("-!") | char('+') | char('-')).named(:op)
    op3 = (str("<|>") | str("<~>") | str("<<~") | str("~>>") |
            str("<<") | str(">>") | str("<~") | str("~>") |
            str("<:") | str("!<:") |
            str(">=") | str("<=") | char('<') | char('>') |
            str("===") | str("==") | str("!==") | str("!=") |
            str("=~")).named(:op)
    op4 = (str("&&") | str("||")).named(:op)
    ope = (str("+=") | str("-=") | str("<<=") | char('=')).named(:op)

    # Construct the nested possible relations for each group of operators.
    tw = compound
    t1 = (tw >> (opw >> s >> tw).repeat(1) >> s).named(:group_w) | tw
    t2 = (t1 >> (sn >> op1 >> sn >> t1).repeat).named(:relate)
    t3 = (t2 >> (sn >> op2 >> sn >> t2).repeat).named(:relate)
    t4 = (t3 >> (sn >> op3 >> sn >> t3).repeat).named(:relate)
    te = (t4 >> (sn >> op4 >> sn >> t4).repeat).named(:relate)
    t = (te >> (sn >> ope >> sn >> te >> s).repeat).named(:relate_r)

    # Define what a comma/newline-separated sequence of terms looks like.
    term = decl | t
    termsl = term >> s >> (char(',') >> sn >> term >> s).repeat
    terms = (termsl >> sn).repeat

    # Define groups that are pipe-partitioned sequences of terms.
    pipesep = char('|').named(:op)
    ptermsp =
      pipesep.maybe >> sn >>
      (terms >> sn >> pipesep >> sn).repeat >>
      terms >> sn >>
      pipesep.maybe >> sn
    parens.define(
      (str("^(") >> sn >> ptermsp.maybe >> sn >> char(')')).named(:group) |
      (char('(') >> sn >> ptermsp.maybe >> sn >> char(')')).named(:group) |
      (char('[') >> sn >> ptermsp.maybe >> sn >> char(']') >> char('!').maybe).named(:group)
    )

    # Define what a declaration looks like.
    decl.define(
      (char(':') >> ident >> (s >> compound).repeat >> s).named(:decl) >>
      (char(':') | ~~newline)
    )

    # Define a total document to be a sequence of lines.
    doc = (sn >> terms).named(:doc)

    # A valid parse is a single document followed by the end of the file.
    doc.then_eof
  end
end
