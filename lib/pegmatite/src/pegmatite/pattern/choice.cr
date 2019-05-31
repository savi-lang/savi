module Pegmatite
  # Pattern::Choice is used to specify an ordered choice of patterns.
  #
  # Returns the result of the first child pattern that matched.
  # Returns the longest-length failure of all child patterns fail.
  class Pattern::Choice < Pattern
    def initialize(@children = [] of Pattern)
    end
    
    # Override this DSL operator to accrue into the existing choice.
    def |(other); Pattern::Choice.new(@children.dup.push(other)) end
    
    def description
      case @children.size
      when 0 then "(empty choice!)"
      when 1 then @children[0].description
      when 2 then "either #{@children.map(&.description).join(" or ")}"
      else        "either #{@children[0...-1].map(&.description).join(", ")}" \
                  " or #{@children[-1].description}"
      end
    end
    
    def match(source, offset, state) : MatchResult
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
