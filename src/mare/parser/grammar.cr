require "pegmatite"

module Mare::Parser
  Grammar = Pegmatite::DSL.define do
    # Define what an end-of-line comment looks like.
    eol_comment = str("//") >> (~char('\n') >> any).repeat
    
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
      str("\\\"") | str("\\\\") | str("\\|") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    string = char('"') >> string_char.repeat.named(:string) >> char('"')
    
    # Define an atom to be a single term with no binary operators.
    parens = declare()
    prefixed = declare()
    decl = declare()
    atom = prefixed | parens | decl | string | float | integer | ident
    
    # Define a prefixed term to be preceded by a prefix operator.
    prefixop = (char('~') | str("--")).named(:op)
    prefixed.define (prefixop >> atom).named(:prefix)
    
    # Define a qualified term to be immediately followed by a parens group.
    qualified = (atom >> parens).named(:qualify)
    suffixed = qualified
    
    # Define what a capability looks like.
    cap = (
      str("iso") | str("trn") | str("val") |
      str("ref") | str("box") | str("tag") | str("non")
    ).named(:ident)
    capmod = str("alias").named(:ident)
    
    # Define groups of operators, in order of precedence,
    # from most tightly binding to most loosely binding.
    # Operators in the same group have the same level of precedence.
    opcap = (char('\'')).named(:op)
    op1 = (str("->") | str("+>")).named(:op)
    op2 = char('.').named(:op)
    op3 = (char('*') | char('/') | char('%')).named(:op)
    op4 = ((char('+') | char('-')) >> ~char('>')).named(:op)
    op5 = (str("..") | str("<>")).named(:op)
    op6 = (str("<|>") | str("<~>") | str("<<<") | str(">>>") |
            str("<<~") | str("~>>") | str("<<") | str(">>") |
            str("<~") | str("~>")).named(:op)
    op7 = ((str("<:") | str(">=") | str("<=") | char('<') | char('>')) >>
            ~(char('>') | char('<'))).named(:op)
    op8 = (str("===") | str("==") | str("!==") | str("!=") |
            str("=~")).named(:op)
    op9 = (str("&&") | str("||")).named(:op)
    opw = (char(' ') | char('\t'))
    ope = char('=').named(:op)
    
    # Construct the nested possible relations for each group of operators.
    t0 = suffixed | atom
    t1 = (t0 >> (opcap >> (cap | capmod)).repeat).named(:relate)
    t2 = (t1 >> (op1 >> t1).repeat).named(:relate)
    t3 = (t2 >> (sn >> op2 >> sn >> t2).repeat).named(:relate)
    t4 = (t3 >> (sn >> op3 >> sn >> t3).repeat).named(:relate)
    t5 = (t4 >> (sn >> op4 >> sn >> t4).repeat).named(:relate)
    t6 = (t5 >> (sn >> op5 >> sn >> t5).repeat).named(:relate)
    t7 = (t6 >> (sn >> op6 >> sn >> t6).repeat).named(:relate)
    t8 = (t7 >> (sn >> op7 >> sn >> t7).repeat).named(:relate)
    t9 = (t8 >> (sn >> op8 >> sn >> t8).repeat).named(:relate)
    tw = (t9 >> (sn >> op9 >> sn >> t9).repeat).named(:relate)
    te = (~decl >> tw >> (opw >> s >> ~decl >> tw).repeat(1) >> s).named(:group_w) | tw
    t = (te >> (sn >> ope >> sn >> te >> s).repeat).named(:relate_r)
    
    # Define what a comma/newline-separated sequence of terms looks like.
    termsl = t >> s >> (char(',') >> sn >> t >> s).repeat
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
      (char('[') >> sn >> ptermsp.maybe >> sn >> char(']')).named(:group)
    )
    
    # Define what a declaration looks like.
    declterm = t3
    decl.define(
      (char(':') >> ident >> (s >> declterm).repeat >> s).named(:decl) >>
      (char(':') | ~~newline)
    )
    
    # Define a total document to be a sequence of lines.
    doc = sn >> terms.named(:doc)
    
    # A valid parse is a single document followed by the end of the file.
    doc.then_eof
  end
end
