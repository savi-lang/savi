# -*- coding: utf-8 -*- #
# frozen_string_literal: true

module Rouge
  module Lexers
    class Mare < RegexLexer
      tag 'mare'
      filenames '*.mare'

      state :whitespace do
      end

      state :root do
        mixin :whitespace

        # Line Comment
        rule %r{//.*?$}, Comment::Single

        # Doc Comment
        rule %r{::.*?$}, Comment::Single

        # Capability Operator
        rule %r{(\')(\w+)(?=[^\'])} do
          groups Operator, Name
        end

        # Double-Quote String
        rule %r{\w?"}, Str::Double, :string_double

        # Single-Char String
        rule %r{'}, Str::Char, :string_char

        # Class (or other type)
        rule %r{([_A-Z]\w*)}, Name::Class

        # Declare
        rule %r{^(\s*)(:)(\w+)} do
          groups Text, Name::Tag, Name::Tag
          push :decl
        end

        # Error-Raising Calls/Names
        rule %r{((\w+|\+|\-|\*)\!)}, Generic::Deleted

        # Numeric Values
        rule %r{\b\d([\d_]*(\.[\d_]+)?)\b}, Num

        # Hex Numeric Values
        rule %r{\b0x([0-9a-fA-F_]+)\b}, Num::Hex

        # Binary Numeric Values
        rule %r{\b0b([01_]+)\b}, Num::Bin

        # Function Call (with braces)
        rule %r{(\w+(?:\?|\!)?)(?=\()}, Name::Function

        # Function Call (with receiver)
        rule %r{(?<=\.)(\w+(?:\?|\!)?)}, Name::Function

        # Function Call (with self receiver)
        rule %r{(?<=@)(\w+(?:\?|\!)?)}, Name::Function

        # Parenthesis
        rule %r{\(}, Punctuation, :root
        rule %r{\)}, Punctuation, :pop!

        # Brace
        rule %r{\{}, Punctuation, :root
        rule %r{\}}, Punctuation, :pop!

        # Bracket
        rule %r{\[}, Punctuation, :root
        rule %r{(\])(\!)} do
          groups Punctuation, Generic::Deleted
          pop!
        end
        rule %r{\]}, Punctuation, :pop!

        # Expression Separators
        rule %r{(,|;|:)}, Punctuation

        # Other "Punctuation"
        rule %r{(@|\.)}, Punctuation

        # Piping Operators
        rule %r{(\|\>)}, Operator

        # Branching Operators
        rule %r{(\&\&|\|\||\?\?|\&\?|\|\?|\.\?)}, Operator

        # Comparison Operators
        rule %r{(\<\=\>|\=\~|\=\=|\<\=|\>\=|\<|\>)}, Operator

        # Arithmetic Operators
        rule %r{(\+|\-|\/|\*|\%)}, Operator

        # Assignment Operators
        rule %r{(\=)}, Operator

        # Other Operators
        rule %r{(\!|\<\<|\<|\&|\|)}, Operator

        # Identifiers
        rule %r{\b\w+\b}, Name

        # Whitespace
        rule %r{[ \t\r]+}, Text
      end

      # Declare (nested rules)
      state :decl do
        rule %r{\b[a-z_]\w*\b(?!\!)}, Keyword::Declaration
        rule %r{:}, Punctuation, :pop!
        rule %r{\n}, Text, :pop!
        mixin :root
      end

      # Double-Quote String (nested rules)
      state :string_double do
        rule %r{\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]}, Str::Escape
        rule %r{\\x[0-9a-fA-F][0-9a-fA-F]}, Str::Escape
        rule %r{\\[bfnrt\\"]}, Str::Escape
        rule %r{"}, Str::Double, :pop!
        rule %r{.}, Str::Double
      end

      # Single-Char String (nested rules)
      state :string_char do
        rule %r{\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]}, Str::Escape
        rule %r{\\x[0-9a-fA-F][0-9a-fA-F]}, Str::Escape
        rule %r{\\[bfnrt\\"]}, Str::Escape
        rule %r{'}, Str::Char, :pop!
        rule %r{.}, Str::Char
      end
    end
  end
end
