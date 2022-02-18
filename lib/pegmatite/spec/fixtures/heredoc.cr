Fixtures::HeredocGrammar = Pegmatite::DSL.define do
  # Define what optional whitespace looks like.
  s = (char(' ') | char('\t')).repeat
  newline = (char('\r').maybe >> char('\n'))
  snl = (s >> newline.maybe >> s).repeat

  # Define what a number looks like.
  digit19 = range('1', '9')
  digit = range('0', '9')
  digits = digit.repeat(1)
  int =
    (char('-') >> digit19 >> digits) |
      (char('-') >> digit) |
      (digit19 >> digits) |
      digit
  number = int.named(:number)

  # Define what a string looks like.
  hex = digit | range('a', 'f') | range('A', 'F')
  string_char =
    str("\\\"") | str("\\\\") | str("\\|") |
      str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
      (str("\\u") >> hex >> hex >> hex >> hex) |
      (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
  string = char('"') >> string_char.repeat.named(:string) >> char('"')

  identifier = (
    (range('a', 'z') | range('A', 'Z') | char('_')) >>
    (range('a', 'z') | range('A', 'Z') | digits | char('_') | char('-')).repeat
  ).named(:identifier)

  heredoc = (
    (str("<<-") | str("<<")) >> identifier.dynamic_push(:heredoc) >> s >> newline >>
    (~dynamic_match(:heredoc) >> string_char.repeat >> newline).repeat.named(:string) >>
    s >> identifier.dynamic_pop(:heredoc)
  ).named(:heredoc)

  # Define what constitutes a value.
  value =
    str("null").named(:null) |
      str("true").named(:true) |
      str("false").named(:false) |
      number | heredoc | string

  attribute =
    (identifier >> s >> char('=') >> s >> value >> s >> newline).named(:attribute)

  (snl >> attribute >> snl).repeat.then_eof
end
