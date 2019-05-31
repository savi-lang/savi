# The Pegmatite::DSL allows you to tersely define a deeply composed Pattern
# by providing convenience methods for creating new Pattern instances.
#
# See spec/fixtures/json.cr for a detailed real-world example of using the DSL.
class Pegmatite::DSL
  def self.define
    with new yield
  end
  
  def declare; Pattern::Forward.new end
  def str(text); Pattern::Literal.new(text) end
  def any; Pattern::UnicodeAny::INSTANCE end
  def char(c)
    c = c.ord if c.is_a?(Char)
    Pattern::UnicodeChar.new(c.to_u32)
  end
  def range(min, max)
    min = min.ord if min.is_a?(Char)
    max = max.ord if max.is_a?(Char)
    Pattern::UnicodeRange.new(min.to_u32, max.to_u32)
  end
  
  # These Methods are defined to be included in all Pattern instances,
  # for ease of combining and composing new Patterns.
  module Methods
    def >>(other); Pattern::Sequence.new([self, other] of Pattern) end
    def |(other); Pattern::Choice.new([self, other] of Pattern) end
    def ~; Pattern::Not.new(self) end
    def repeat(min = 0); Pattern::Repeat.new(self, min) end
    def maybe; Pattern::Optional.new(self) end
    def then_eof; Pattern::EOF.new(self) end
    def named(label, tokenize = true)
      Pattern::Label.new(self, label, tokenize)
    end
  end
end
