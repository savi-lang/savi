class Mare::Witness
  alias Plan = Hash(String, String | Bool)

  def initialize(@plans = [] of Plan)
  end

  # Parse the head of the given declare statement according to the plan,
  # coercing and extracting terms into an output map to return to the caller.
  # If the declare statement doesn't match the plan, an error will be raised.
  def run(decl : AST::Declare)
    list = decl.head
    list_index = 0
    plan_index = 0

    output = {} of String => AST::Term

    # Iterate over each term in the list, populating the output map.
    while list_index < list.size
      term = list[list_index]
      plan =
        begin
          @plans[plan_index]
        rescue IndexError
          Error.at term, "Unexpected extra term"
        end

      # We have to set these to nil explicitly, otherwise Crystal's "feature"
      # leaking variables from inner scopes into outer ones will keep them
      # around between iterations of the loop and cause weird bugs here.
      consumed = nil
      defaulted = nil

      # Consume the term if possible, and insert into the output accordingly.
      consumed = try_consume(term, plan, output)
      output[plan["name"].as(String)] = consumed if consumed

      # If we didn't consume it, try to maybe apply a default.
      defaulted = try_default(plan, output) unless consumed
      output[plan["name"].as(String)] = defaulted if defaulted

      # If we consumed the term, move the list cursor forward.
      # Move the plan cursor forward in all cases.
      list_index += 1 if consumed
      plan_index += 1
    end

    # Check that no more terms are required by the plan.
    while plan_index < @plans.size
      plan = @plans[plan_index]

      # We're only allowed to have more plans here if they are optional.
      Error.at decl, "Expected more terms in this declaration" \
        unless plan["optional"]? == true

      # If this plan was optional, try to apply a default.
      defaulted = try_default(plan, output)
      output[plan["name"].as(String)] = defaulted if defaulted

      plan_index += 1
    end

    output
  end

  # Check if the given term matches the given plan, maybe transforming it.
  # The previous_terms parameter is used for terms that depend on previous ones.
  # On success, the matched/transformed term is returned, and is to be treated
  # by the caller as if it had been consumed by the process.
  # On failure to match, an Error is raised or nil is returned,
  # depending on whether the given plan was optional.
  def try_consume(term : AST::Term, plan : Plan, previous_terms) : AST::Term?
    case plan["kind"]
    when "keyword"
      values = plan["value"].as(String).split("|")

      # A keyword must be an identifier that exactly matches the given name.
      Error.at term, "Expected keyword '#{plan["value"]}'" \
        unless term.is_a?(AST::Identifier) && values.includes?(term.value)
    when "term"
      if plan["exclude_keyword"]? \
      && term.is_a?(AST::Identifier) && term.value == plan["exclude_keyword"]
        Error.at term,
          "Expected not to see keyword '#{plan["exclude_keyword"]}'"
      end

      # If a type requirement is specified, check the type first.
      # We can check multiple types here if given (pipe-delimited).
      if plan["type"]?
        types = plan["type"].as(String).split("|")

        unless types.any? { |t| check_type(term, t) }
          extra = [] of {Source::Pos, String}

          if term.is_a?(AST::Qualify) \
          && types.any? { |t| check_type(term.term, t) }
            extra << {term.group.pos, "you probably need to add a space " \
              "to separate it from this next term"}
          end

          Error.at term, "Expected a term of type: #{show_or(types)}", extra
        end
      end

      # Convert LiteralString to Identifier if requested.
      if plan["convert_string_to_ident"]? && term.is_a?(AST::LiteralString)
        term = AST::Identifier.new(term.value).from(term)
      end
    else
      raise NotImplementedError.new(plan)
    end

    # Finally, return the term that was matched and consumed.
    term
  rescue ex : Error
    # Swallow the error if the plan was optional - the term is not consumed.
    return nil if plan["optional"]?

    # Otherwise, this plan was mandatory and we'll continue raising the error.
    raise ex
  end

  # Try to pull a default value out of this plan if possible.
  # The previous_terms parameter is used for terms that depend on previous ones.
  def try_default(plan : Plan, previous_terms) : AST::Term?
    term = nil

    term ||= previous_terms[plan["default_copy_term"]?]? \
      if plan["default_copy_term"]?

    term
  end

  # Check if the given term matches the type indicated by the given string.
  def check_type(term : AST::Term?, t : String) : Bool
    case t
    when "ident" then term.is_a?(AST::Identifier)
    when "string" then term.is_a?(AST::LiteralString)
    when "type"
      case term
      when AST::Identifier then true # TODO: maybe disallow lowercase?
      when AST::Qualify
        check_type(term.term, t) &&
        term.group.style == "(" &&
        term.group.terms.all? { |term2| check_type(term2, t) }
      when AST::Relate
        ["'", "->", "->>"].includes?(term.op.value) &&
        check_type(term.lhs, t) &&
        check_type(term.rhs, t)
      when AST::Group
        (
          (term.style == "(" && term.terms.size == 1) ||
          (term.style == "|")
        ) &&
        term.terms.all? { |term2| check_type(term2, t) }
      else false
      end
    when "params"
      # TODO: more specific requirements here
      term.is_a?(AST::Group)
    else raise NotImplementedError.new(t)
    end
  end

  # Convenience method for showing the given list of strings in English syntax,
  # delimited by commas as necessary, indicating an "or" semantic.
  def show_or(list : Array(String))
    return "(empty)" if list.size == 0
    return list[0] if list.size == 1
    "#{list[0...-1].join(", ")} or #{list[-1]}" if list.size == 2
  end
end
