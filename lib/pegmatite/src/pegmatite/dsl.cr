# The Pegmatite::DSL allows you to tersely define a deeply composed Pattern
# by providing convenience methods for creating new Pattern instances.
#
# See spec/fixtures/json.cr for a detailed real-world example of using the DSL.
class Pegmatite::DSL
  def self.define
    with new yield
  ensure
    clear_class_variables_state
  end

  def declare
    Pattern::Forward.new
  end

  def dynamic_match(label)
    Pattern::DynamicMatch.new(label)
  end

  def str(text)
    Pattern::Literal.new(text)
  end

  def any
    Pattern::UnicodeAny::INSTANCE
  end

  def char(c)
    c = c.ord if c.is_a?(Char)
    Pattern::UnicodeChar.new(c.to_u32)
  end

  def range(min, max)
    min = min.ord if min.is_a?(Char)
    max = max.ord if max.is_a?(Char)
    Pattern::UnicodeRange.new(min.to_u32, max.to_u32)
  end

  def l(lit)
    case lit
    when Char
      char(lit)
    when String
      str(lit)
    when Range
      range(lit.begin, lit.end)
    else
      raise "Invalid type `#{typeof(lit)}` for `l`. Must be Char, String, or Range."
    end
  end

  # Define a DSL method for setting the pattern to use for whitespace in the
  # ^ operator, which allows optional whitespace between concatenated patterns.
  # Using class variables here is not ideal, but it's acceptable for a DSL.
  def whitespace_pattern(pattern : Pattern)
    @@last_defined_whitespace_pattern = pattern
  end

  def self.last_defined_whitespace_pattern
    @@last_defined_whitespace_pattern.not_nil!
  end

  def self.clear_class_variables_state
    @@last_defined_whitespace_pattern = nil
  end

  # These Methods are defined to be included in all Pattern instances,
  # for ease of combining and composing new Patterns.
  module Methods
    def >>(other)
      Pattern::Sequence.new([self, other] of Pattern)
    end

    def |(other)
      Pattern::Choice.new([self, other] of Pattern)
    end

    def ~
      Pattern::Not.new(self)
    end

    def repeat(min = 0)
      Pattern::Repeat.new(self, min)
    end

    def maybe
      Pattern::Optional.new(self)
    end

    def then_eof
      Pattern::EOF.new(self)
    end

    def dynamic_push(label)
      Pattern::DynamicPush.new(self, label)
    end

    def dynamic_pop(label)
      Pattern::DynamicPop.new(self, label)
    end

    def named(label, tokenize = true)
      Pattern::Label.new(self, label, tokenize)
    end

    def ^(other)
      self >> DSL.last_defined_whitespace_pattern.maybe >> other
    end
  end
end
