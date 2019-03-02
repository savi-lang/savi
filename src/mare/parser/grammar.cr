require "pegmatite"

module Mare::Parser
  Grammar = Pegmatite::DSL.define do
    # Define what an end-of-line comment looks like.
    eol_comment = str("//") >> (~char('\n') >> any).repeat
    
    # Define what whitespace looks like.
    whitespace =
      char(' ') | char('\t') | char('\r') | str("\\\n") | str("\\\r\n")
    s = whitespace.repeat
    sn = (whitespace | (eol_comment.maybe >> char('\n'))).repeat
    
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
      (char('@') >> ident_letter.repeat) |
      (char('^') >> digit19 >> digit.repeat) |
      ident_letter.repeat(1)
    ).named(:ident)
    
    # Define what a string looks like.
    string_char =
      str("\\\"") | str("\\\\") | str("\\|") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    string = char('"') >> string_char.repeat.named(:string) >> char('"')
    
    # Define an atom to be a single term with no binary operators.
    parens = declare
    prefixed = declare
    atom = prefixed | parens | string | float | integer | ident
    
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
    
    # Define groups of operators, in order of precedence,
    # from most tightly binding to most loosely binding.
    # Operators in the same group have the same level of precedence.
    opcap = (char('\'') | str("->") | str("+>")).named(:op)
    op2 = (char('.')).named(:op)
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
    t1 = suffixed | atom
    t2 = (t1 >> (opcap >> cap).repeat).named(:relate)
    t3 = (t2 >> (sn >> op2 >> sn >> t2).repeat).named(:relate)
    t4 = (t3 >> (sn >> op3 >> sn >> t3).repeat).named(:relate)
    t5 = (t4 >> (sn >> op4 >> sn >> t4).repeat).named(:relate)
    t6 = (t5 >> (sn >> op5 >> sn >> t5).repeat).named(:relate)
    t7 = (t6 >> (sn >> op6 >> sn >> t6).repeat).named(:relate)
    t8 = (t7 >> (sn >> op7 >> sn >> t7).repeat).named(:relate)
    t9 = (t8 >> (sn >> op8 >> sn >> t8).repeat).named(:relate)
    tw = (t9 >> (sn >> op9 >> sn >> t9).repeat).named(:relate)
    te = (tw >> (opw >> s >> tw).repeat(1) >> s).named(:group_w) | tw
    t = (te >> (sn >> ope >> sn >> te >> s).repeat).named(:relate)
    
    # Define groups that are pipe-partitioned lists of comma-separated terms.
    pipesep = char('|').named(:op)
    ptermsl = t >> s >> (char(',') >> sn >> t >> s).repeat
    ptermsn = (ptermsl >> sn).repeat
    ptermsp =
      pipesep.maybe >> sn >>
      (ptermsn >> sn >> pipesep >> sn).repeat >>
      ptermsn >> sn >>
      pipesep.maybe >> sn
    parens.define(
      (str("^(") >> sn >> ptermsp.maybe >> sn >> char(')')).named(:group) |
      (char('(') >> sn >> ptermsp.maybe >> sn >> char(')')).named(:group) |
      (char('[') >> sn >> ptermsp.maybe >> sn >> char(']')).named(:group)
    )
    
    # Define what a declaration head of terms looks like.
    dterm = atom
    dterms = dterm >> (s >> dterm).repeat >> s
    decl = (dterms >> s >> char(':') >> s).named(:decl)
    
    # Define what a line looks like.
    terms = t >> s >> (char(',') >> sn >> t >> s).repeat
    line_item = (decl >> terms.maybe) | terms
    line =
      s >>
      (s >> ~eol_comment >> line_item).repeat >>
      (s >> eol_comment.maybe) >>
      s
    
    # Define a total document to be a sequence of lines.
    doc = ((line >> char('\n')).repeat >> line >> sn).named(:doc)
    
    # A valid parse is a single document followed by the end of the file.
    doc.then_eof
  end
end
