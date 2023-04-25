abstract class Savi::Program::Declarator::TermAcceptor
  abstract def name : String
  abstract def try_accept(term : AST::Term) : AST::Term?

  abstract def describe : String
  def describe_post : String
    ""
  end

  property! pos : Source::Pos
  property optional : Bool = false
  property default : AST::Term?
  def try_default : AST::Term?
    @default
  end

  class Keyword < TermAcceptor
    getter keyword : String

    def initialize(@pos, @keyword)
    end

    def name : String
      "_" # we don't care about where we save the term
    end

    def try_accept(term : AST::Term) : AST::Term?
      term if term.is_a?(AST::Identifier) && term.value == @keyword
    end

    def describe : String
      "the keyword `#{keyword}`"
    end
  end

  class Enum < TermAcceptor
    getter name : String
    getter possible : Array(String)

    def initialize(@pos, @name, @possible)
    end

    def try_accept(term : AST::Term) : AST::Term?
      return unless term.is_a?(AST::Identifier)

      term if @possible.includes?(term.value)
    end

    def describe : String
      "any of these"
    end
    def describe_post : String
      ": `#{@possible.join("`, `")}`"
    end
  end

  class Typed < TermAcceptor
    getter name : String
    getter type : String

    def initialize(@pos, @name, @type)
    end

    def self.try_accept(term : AST::Term, type : String) : AST::Term?
      case type
      when "Term"
        term
      when "String"
        term if term.is_a?(AST::LiteralString)
      when "Integer"
        case term
        when AST::LiteralInteger
          term
        when AST::LiteralCharacter
          AST::LiteralInteger.new(term.value.to_u128).from(term)
        end
      when "Name"
        case term
        when AST::Identifier
          term
        when AST::LiteralString
          AST::Identifier.new(term.value).from(term)
        when AST::Relate
          if term.op.value == "." &&
            (lhs = try_accept(term.lhs, type).as(AST::Identifier)) &&
            (rhs = try_accept(term.rhs, type).as(AST::Identifier))
            AST::Identifier.new("#{lhs.value}.#{rhs.value}").from(term)
          end
        end
      when "Param"
        return term if term.is_a?(AST::Identifier)

        if term.is_a?(AST::Relate) && term.op.value == "="
          lhs = try_accept(term.lhs, "Param")
          return unless lhs
          rhs = term.rhs
          op = AST::Operator.new("DEFAULTPARAM").from(term.op)
          return AST::Relate.new(lhs, op, rhs).from(term)
        end

        if term.is_a?(AST::Group) && term.style == " " && term.terms.size == 2
          lhs = term.terms[0]
          return unless lhs.is_a?(AST::Identifier)
          rhs = term.terms[1]
          op = AST::Operator.new("EXPLICITTYPE").from(term)
          return AST::Relate.new(lhs, op, rhs).from(term)
        end
      when "Type"
        case term
        when AST::Identifier
          term
        when AST::Qualify
          if (
            (term_term = try_accept(term.term, type)) &&
            (group_terms = term.group.terms.map { |term2| try_accept(term2.not_nil!, type) }).all?
          )
            if term_term != term.term || group_terms != term.group.terms
              AST::Qualify.new(
                term_term,
                AST::Group.new(
                  term.group.style,
                  group_terms.not_nil!.map(&.as(AST::Term)),
                ).from(term.group),
              ).from(term)
            else
              term
            end
          end
        when AST::Relate
          if (
            ["'", "->"].includes?(term.op.value) &&
            (lhs = try_accept(term.lhs, type)) &&
            (rhs = try_accept(term.rhs, type))
          )
            if lhs != term.lhs || rhs != term.rhs
              AST::Relate.new(lhs, term.op, rhs).from(term)
            else
              term
            end
          else
            try_accept(term, "Name")
          end
        when AST::Group
          if (
            (term.style == "(" && term.terms.size == 1) ||
            (term.style == "|")
          )
            group_terms = term.terms.map { |term2| try_accept(term2.not_nil!, type).as(AST::Term?) }
            if group_terms && group_terms.all?
              if group_terms != term.terms
                AST::Group.new(
                  term.style,
                  group_terms.not_nil!.map(&.as(AST::Term)),
                ).from(term)
              else
                term
              end
            end
          end
        else
          nil
        end
      when "NameList"
        if term.is_a?(AST::Group) && term.style == "("
          group = AST::Group.new("(").from(term)
          term.terms.each { |term2|
            term2 = try_accept(term2, "Name")
            return unless term2
            group.terms << term2
          }
          group
        end
      when "TypeOrTypeList"
        try_accept(term, "Type") || begin
          if term.is_a?(AST::Group) && term.style == "("
            group = AST::Group.new("(").from(term)
            term.terms.each { |term2|
              term2 = try_accept(term2, "Type")
              return unless term2
              group.terms << term2
            }
            group
          end
        end
      when "Params"
        if term.is_a?(AST::Group) && term.style == "("
          group = AST::Group.new("(").from(term)
          term.terms.each { |term2|
            term2 = try_accept(term2, "Param")
            return unless term2
            group.terms << term2
          }
          group
        end
      when "NameMaybeWithParams"
        try_accept(term, "Name") || begin
          if term.is_a?(AST::Qualify)
            AST::Qualify.new(
              try_accept(term.term, "Name") || return,
              try_accept(term.group, "Params").as(AST::Group?) || return,
            ).from(term)
          end
        end
      else
        raise NotImplementedError.new(type)
      end
    end

    def try_accept(term : AST::Term) : AST::Term?
      self.class.try_accept(term, @type)
    end

    def describe : String
      case type
      when "Term"
        "any term"
      when "String"
        "a string literal"
      when "Integer"
        "an integer literal"
      when "Name"
        "an identifier or string literal"
      when "Type"
        "an algebraic type expression"
      when "NameList"
        "a parenthesized group of identifiers or string literals"
      when "TypeOrTypeList"
        "an algebraic type or parenthesized group of algebraic types"
      when "Params"
        "a parenthesized list of parameter specifiers " +
        "(each parameter having at least a name and possibly a type and/or default argument)"
      when "NameMaybeWithParams"
        "a name with an optional parenthesized list of parameter specifiers " +
        "(each parameter having at least a name and possibly a type and/or default argument)"
      else
        raise NotImplementedError.new(type)
      end
    end
  end
end
