module Pegmatite
  # Pattern::Choice is used to specify an ordered choice of patterns.
  #
  # Returns the result of the first child pattern that matched.
  # Returns the longest-length failure of all child patterns fail.
  class Pattern::Choice < Pattern
    def initialize(@children = [] of Pattern)
    end

    # Override this DSL operator to accrue into the existing choice.
    def |(other)
      Pattern::Choice.new(@children.dup.push(other))
    end

    def inspect(io)
      io << "("
      @children.each_with_index do |child, index|
        io << " | " if index != 0
        child.inspect(io)
      end
      io << ")"
    end

    def dsl_name
      "(|)"
    end

    def description
      case @children.size
      when 0 then "(empty choice!)"
      when 1 then @children[0].description
      when 2 then "either #{@children.map(&.description).join(" or ")}"
      else        "either #{@children[0...-1].map(&.description).join(", ")}" \
           " or #{@children[-1].description}"
      end
    end

    # Explicitly memoize Choice patterns, which happens to have a significant
    # speedup on otherwise troublesome grammars with a lot of backtracking.
    # We don't do this for other patterns.
    def match(source, offset, state) : MatchResult
      memo = state.memos[{self, offset}]?
      return memo if memo

      result = _match(source, offset, state)

      state.memos[{self, offset}] = result

      result
    end

    def _match(source, offset, state) : MatchResult
      fail_length, fail_result = {0, self}

      # Try each child pattern in order, looking for the first successful match.
      @children.each do |child|
        length, result = child.match(source, offset, state)

        case result
        when MatchOK
          # On first success, return the result.
          return {length, result}
        else
          # On failure, record the info if this is the longest failure yet seen.
          fail_length, fail_result = {length, result} if length > fail_length
        end
      end

      state.observe_fail(offset + fail_length, fail_result)
      {fail_length, fail_result}
    end
  end
end
