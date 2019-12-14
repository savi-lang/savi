require "json"

Fixtures::JSONGrammar = Pegmatite::DSL.define do
  # Forward-declare `array` and `object` to refer to them before defining them.
  array  = declare
  object = declare

  # Define what optional whitespace looks like.
  s = (char(' ') | char('\t') | char('\r') | char('\n')).repeat

  # Define what a number looks like.
  digit19 = range('1', '9')
  digit = range('0', '9')
  digits = digit.repeat(1)
  int =
    (char('-') >> digit19 >> digits) |
    (char('-') >> digit) |
    (digit19 >> digits) |
    digit
  frac = char('.') >> digits
  exp = (char('e') | char('E')) >> (char('+') | char('-')).maybe >> digits
  number = (int >> frac.maybe >> exp.maybe).named(:number)

  # Define what a string looks like.
  hex = digit | range('a', 'f') | range('A', 'F')
  string_char =
    str("\\\"") | str("\\\\") | str("\\|") |
    str("\\b") | str("\\f") | str("\\n") | str("\\r") | str("\\t") |
    (str("\\u") >> hex >> hex >> hex >> hex) |
    (~char('"') >> ~char('\\') >> range(' ', 0x10FFFF_u32))
  string = char('"') >> string_char.repeat.named(:string) >> char('"')

  # Define what constitutes a value.
  value =
    str("null").named(:null) |
    str("true").named(:true) |
    str("false").named(:false) |
    number | string | array | object

  # Define what an array is, in terms of zero or more values.
  values = value >> s >> (char(',') >> s >> value).repeat
  array.define \
    (char('[') >> s >> values.maybe >> s >> char(']')).named(:array)

  # Define what an object is, in terms of zero or more key/value pairs.
  pair = (string >> s >> char(':') >> s >> value).named(:pair)
  pairs = pair >> s >> (char(',') >> s >> pair).repeat
  object.define \
    (char('{') >> s >> pairs.maybe >> s >> char('}')).named(:object)

  # A JSON document is an array or object with optional surrounding whitespace.
  (s >> (array | object) >> s).then_eof
end

module Fixtures::JSONBuilder
  def self.build(tokens : Array(Pegmatite::Token), source : String)
    iter = Pegmatite::TokenIterator.new(tokens)
    main = iter.next
    build_value(main, iter, source)
  end

  private def self.build_value(main, iter, source)
    kind, start, finish = main

    # Build the value from the given main token and possibly further recursion.
    value =
      case kind
      when :null then JSON::Any.new(nil)
      when :true then JSON::Any.new(true)
      when :false then JSON::Any.new(false)
      when :string then JSON::Any.new(source[start...finish])
      when :number then JSON::Any.new(source[start...finish].to_i64)
      when :array then build_array(main, iter, source)
      when :object then build_object(main, iter, source)
      else raise NotImplementedError.new(kind)
      end

    # Assert that we have consumed all child tokens.
    iter.assert_next_not_child_of(main)

    value
  end

  private def self.build_array(main, iter, source)
    array = [] of JSON::Any

    # Gather children as values into the array.
    iter.while_next_is_child_of(main) do |child|
      array << build_value(child, iter, source)
    end

    JSON::Any.new(array)
  end

  private def self.build_object(main, iter, source)
    object = {} of String => JSON::Any

    # Gather children as pairs of key/values into the array.
    iter.while_next_is_child_of(main) do |pair|
      key = build_value(iter.next_as_child_of(pair), iter, source).as_s
      val = build_value(iter.next_as_child_of(pair), iter, source)
      iter.assert_next_not_child_of(pair)
      object[key] = val
    end

    JSON::Any.new(object)
  end
end
