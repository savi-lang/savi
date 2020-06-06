require "pegmatite"

module Mare::Parser
  GrammarPony = Pegmatite::DSL.define do
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
    ident = ident_letter.repeat(1).named(:ident)

    # Define what a string looks like.
    string_char =
      str("\\\"") | str("\\\\") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      str("\b")  | str("\f")  | str("\n")  | str("\r")  | str("\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    string = char('"') >> string_char.repeat.named(:string) >> char('"')

    # Define what a character string looks like.
    character_char =
      str("\\'") | str("\\\\") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      str("\b")  | str("\f")  | str("\n")  | str("\r")  | str("\t") |
      (str("\\u") >> digithex >> digithex >> digithex >> digithex) |
      (~char('\'') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
    character = char('\'') >> character_char.repeat.named(:char) >> char('\'')

    # Define what a triple-quote string looks like.
    string3_content = declare()
    string3 = str("\"\"\"") >> string3_content.named(:string3) >> str("\"\"\"")
    string3_no_token = str("<<<") >> string3_content >> str("\"\"\"")
    string3_content.define \
      (string3_no_token | (~str("\"\"\"") >> any)).repeat

    # Define an atom to be a single term with no binary operators.
    parens = declare()
    prefixed = declare()
    decl = declare()
    anystring = string | character
    atom = prefixed | parens | anystring | float | integer | ident

    # Define a prefixed term to be preceded by a prefix operator.
    prefixop = (char('~') | str("--")).named(:op)
    prefixed.define (prefixop >> atom).named(:prefix)

    # Define what a capability looks like.
    cap = (
      str("iso") | str("trn") | str("val") |
      str("ref") | str("box") | str("tag") | str("non") |
      str("any") | str("alias") | str("send") | str("share") |
      str("read") | str("mutable") | str("mutableplus")
    ).named(:ident)
    capmod = str("aliased").named(:ident)

    # Define a compound to be a closely bound chain of atoms.
    opcap = char('\'').named(:op)
    opdot = char('.').named(:op)
    oparrow = (str("->") | str("->>")).named(:op)
    compound = (atom >> (
      (opcap >> (capmod | cap)) | \
      (s >> oparrow >> s >> atom) | \
      (sn >> opdot >> sn >> atom) | \
      parens
    ).repeat).named(:compound)

    # Define groups of operators, in order of precedence,
    # from most tightly binding to most loosely binding.
    # Operators in the same group have the same level of precedence.
    opw = (char(' ') | char('\t'))
    op1 = (char('*') | char('/') | char('%')).named(:op)
    op2 = (char('+') | char('-')).named(:op)
    op3 = (str("<|>") | str("<~>") | str("<<~") | str("~>>") |
            str("<<") | str(">>") | str("<~") | str("~>") |
            str("<:") | str(">=") | str("<=") | char('<') | char('>') |
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

    # Define what a semicolon/newline-separated sequence of terms looks like.
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

    colon_type = char(':') >> sn >> compound

    method_decl_start = (str("fun") | str("be") | str("new")).named(:ident)
    method_param = (ident >> sn >> colon_type).named(:group_w)
    method_params = (
      char('(') >> sn >>
      (
        method_param >> sn >>
        (char(',') >> sn >> method_param >> sn).repeat
      ).maybe >> sn >>
      char(')')
    ).named(:group)
    method_decl_head = (
      method_decl_start >> sn >> (cap >> sn).maybe >> ident >> sn >>
      method_params >> sn >> (colon_type >> sn).maybe
    ).named(:decl)
    method_decl = method_decl_head >> (str("=>") >> sn >> termsl).maybe

    field_decl_start = (
      str("var") | str("let") | str("embed")
    ).named(:ident)
    field_decl_head = (
      field_decl_start >> sn >> ident >> sn >> colon_type >> sn
    ).named(:pony_prop_decl)
    field_decl = field_decl_head >> (char('=') >> sn >> t >> sn).maybe

    member_decl = field_decl | method_decl

    type_decl_start = (
      str("primitive") | str("struct") | str("class") | str("actor") |
      str("interface") | str("trait") | str("type")
    ).named(:ident)
    type_decl = (
      (type_decl_start >> sn >> ident >> sn).named(:decl) >>
      (member_decl >> sn).repeat
    )

    use_decl = str("TODO: use_decl")

    # Define a total document to be use_decls followed by type_decls.
    doc = (sn >>
      (use_decl >> sn).repeat >>
      (type_decl >> sn).repeat >>
    sn).named(:doc)

    # A valid parse is a single document followed by the end of the file.
    doc.then_eof
  end
end
