class Savi::Program::Declarator
  property name : AST::Identifier
  property intrinsic : Bool
  property context : AST::Identifier
  property begins : Array(String)
  property terms : Array(Declarator::TermAcceptor)
  property body_allowed : Bool
  property body_required : Bool

  def initialize(
    @name,
    @intrinsic = false,
    @context = AST::Identifier.new("top").with_pos(Source::Pos.none),
    @begins = [] of String,
    @terms = [] of Declarator::TermAcceptor,
    @body_allowed = false,
    @body_required = false,
  )
  end

  # This is a convenience constructor that will create fake AST nodes
  # for those fields which expect an AST node. This is used in bootstrapping,
  # because in bootstrapping they are not coming from Savi source code,
  # and thus there is no true AST node with a real source position.
  # However, all of these bootstrap instances will be replaced with ones
  # defined in Savi source code before user code is run, so all of these
  # fake AST nodes and will not plague our presentation of user errors.
  def self.new_bootstrap(
    name,
    intrinsic = false,
    context = "top",
    begins = [] of String,
    terms = [] of Declarator::TermAcceptor,
    body_allowed = false,
    body_required = false,
  )
    new(
      name: AST::Identifier.new(name).with_pos(Source::Pos.none),
      intrinsic: intrinsic,
      context: AST::Identifier.new(context).with_pos(Source::Pos.none),
      begins: begins,
      terms: terms,
      body_allowed: body_allowed,
      body_required: body_required,
    )
  end

  def matches_name?(name)
    @name.value == name
  end

  def matches_head?(head, errors : Array(Error::Info)? = nil)
    accepted_terms = {} of String => AST::Term?
    acceptor_index = 0

    # Each term in the head must be accepted for us to have a match overall.
    head.each_with_index { |term, index|
      if index == 0
        # The first term in the head must match the declarator name.
        return unless @name.value == term.as(AST::Identifier).value
      else
        accept_info = [] of Error::Info if errors

        # Try to find a term acceptor that matches this term.
        # We consider each term acceptor in order until one accepts the term.
        # Term acceptors that fail to match must have a default available, or
        # their lack of acceptance of this term will cause us to fail overall.
        was_accepted = false
        until was_accepted
          acceptor = @terms[acceptor_index]?
          return unless acceptor

          # Gather info about what terms would be acceptable, for error info.
          if accept_info
            accept_info << {
              acceptor.pos,
              "#{acceptor.describe} would be accepted#{acceptor.describe_post}",
            }
          end

          if (accepted = acceptor.try_accept(term))
            was_accepted = true
            accepted_terms[acceptor.name] = accepted
          elsif (defaulted = acceptor.try_default)
            accepted_terms[acceptor.name] = defaulted
          elsif acceptor.optional
            nil
          else
            if errors && accept_info
              errors << {term.pos, "this term was not acceptable"}
              errors.concat(accept_info)
            end
            return
          end

          acceptor_index += 1
        end
      end
    }

    # Then, we finish evaluating term acceptors that didn't accept anything.
    # If they don't have defaults we will fail the match overall,
    # because there are no terms remaining for them to accept.
    loop do
      acceptor = @terms[acceptor_index]?
      break unless acceptor

      if (defaulted = acceptor.try_default)
        accepted_terms[acceptor.name] = defaulted
      elsif acceptor.optional
        nil
      else
        return
      end

      acceptor_index += 1
    end

    accepted_terms
  end

  def run(ctx, scope, declare, terms)
    raise NotImplementedError.new "custom declarators:\n#{declare.pos.show}" \
      unless intrinsic

    Intrinsic.run(ctx, scope, self, declare, terms)

    scope.push_context(self) if @begins.any?
  end

  def finish(ctx, scope, declarators)
    raise NotImplementedError.new "custom declarators" unless intrinsic

    Intrinsic.finish(ctx, scope, declarators, self)
  end
end
