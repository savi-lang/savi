require "./pass/analyze"

##
# The Local pass is meant to mark all usage of local variables,
# and to validate that they are not used before being assigned a value,
# or after having their binding destroyed by a consume expression.
#
# We rely on the ReferType pass to let us know which identifiers are types,
# so that we know they are not local variables.
#
# We rely on the Flow pass for control flow analysis to let us know what
# possible orders of execution we might see for a variable's use sites.
#
# We rely on the Classify pass for knowing when an assignment's value is used,
# and for avoiding treating identifiers in non-imperative contexts as variables.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::Local
  struct UseSite
    getter pos : Source::Pos
    getter local_name : String
    getter flow_location : Flow::Location
    getter reads_existing_value : Bool = false
    getter writes_new_value : Bool = false
    getter consumes_existing_value : Bool = false

    def initialize(@pos, @local_name, @flow_location,
      reads = false,
      writes = false,
      consumes = false
    )
      @reads_existing_value = reads
      @writes_new_value = writes
      @consumes_existing_value = consumes

      @errors_without_prior_write = Set(Bool).new
      @sometimes_after_writes = Set(UseSite).new
      @errors_after_consumes = Set(UseSite).new
    end

    def show
      "#{
        @local_name
      }:#{
        @reads_existing_value ? "R" : ""
      }#{
        @writes_new_value ? "W" : ""
      }#{
        @consumes_existing_value ? "C" : ""
      }:#{
        @flow_location.show
      }"
    end

    protected def observe_error_without_prior_write
      @errors_without_prior_write.add(true)
    end
    protected def observe_sometimes_after_write(write_site : UseSite)
      @sometimes_after_writes.add(write_site)
    end
    protected def observe_error_after_consume(consume_site : UseSite)
      @errors_after_consumes.add(consume_site)
    end

    protected def emit_errors(ctx)
      if @errors_without_prior_write.any?
        message = if @sometimes_after_writes.any?
          "This local variable isn't guaranteed to have a value yet"
        else
          "This local variable has no assigned value yet"
        end

        ctx.error_at self, message, @sometimes_after_writes.map { |write_site|
          {write_site.pos, "this assignment is not guaranteed to precede that usage"}
        }
      end

      if @errors_after_consumes.any?
        message = if @consumes_existing_value
          "This local variable can't be consumed again"
        else
          "This local variable has no value anymore"
        end
        ctx.error_at self, message, @errors_after_consumes.map { |consume_site|
          {consume_site.pos, "it is consumed in a preceding place here"}
        }
      end
    end
  end

  struct Analysis
    def initialize
      @use_sites = {} of AST::Node => UseSite
      @by_name_and_location = {} of String => Hash(Flow::Location, UseSite)
    end

    def []?(node : AST::Node)
      @use_sites[node]?
    end

    protected def each_use_site
      @use_sites.each_value
    end

    protected def by_name_and_location
      @by_name_and_location
    end

    protected def expect_local_name(local_name : String)
      @by_name_and_location[local_name] ||= {} of Flow::Location => UseSite
    end

    protected def observe_use_site(node : AST::Node, use_site : UseSite)
      @use_sites[node] = use_site
      (@by_name_and_location[use_site.local_name] ||=
        {} of Flow::Location => UseSite)[use_site.flow_location] = use_site
      use_site
    end

    protected def remove_use_site_at(node : AST::Node)
      use_site = @use_sites.delete(node)
      return unless use_site
      @by_name_and_location[use_site.local_name].delete(use_site.flow_location)
      use_site
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter refer_type : ReferType::Analysis
    getter flow : Flow::Analysis
    getter classify : Classify::Analysis

    def initialize(@analysis, @refer_type, @flow, @classify)
      @analysis.expect_local_name("@") # prime us to see this special-case local
    end

    def visit(ctx, node)
      observe(ctx, node)
      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    # Handle reading from a local variable.
    def observe(ctx, node : AST::Identifier)
      # Don't observe an identifier that is a type identifier,
      # unless it is one that we already have some local analysis for.
      return if @refer_type[node]? && !@analysis.by_name_and_location.has_key?(node.value)

      # Don't observe an identifier that is not part of a value expression,
      # or that is part of a known type expression.
      return if @classify.no_value?(node) || @classify.type_expr?(node)

      flow_location = @flow.location_of?(node)
      @analysis.observe_use_site(node, UseSite.new(
        node.pos,
        node.value,
        flow_location,
        reads: true,
      )) if flow_location
    end

    # Handle assigning to or displacing a local variable.
    def observe(ctx, node : AST::Relate)
      reads =
        case node.op.value
        when "=" then false
        when "<<=" then true
        when "." then return observe_call(ctx, node)
        else return
        end

      ident = AST::Extract.param(node.lhs).first

      @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      @analysis.observe_use_site(node, UseSite.new(
        ident.pos,
        ident.value,
        flow_location,
        reads: reads,
        writes: true,
      )) if flow_location
    end

    # Handle consuming a local variable.
    def observe(ctx, node : AST::Prefix)
      ident = node.term
      return unless node.op.value == "--" && ident.is_a?(AST::Identifier)

      @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      @analysis.observe_use_site(node, UseSite.new(
        ident.pos,
        ident.value,
        flow_location,
        consumes: true,
      )) if flow_location
    end

    # All other node types have no special logic.
    def observe(ctx, node)
    end

    # Observing a parameter definition has its own logic.
    def observe_param(ctx, node)
      ident = AST::Extract.param(node).first

      @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      @analysis.observe_use_site(node, UseSite.new(
        ident.pos,
        ident.value,
        flow_location,
        writes: true,
      )) if flow_location
    end

    # Observing a call site entails observing any yield parameters.
    def observe_call(ctx, node)
      ident, args, yield_params, yield_block = AST::Extract.call(node)

      if yield_params
        yield_params.terms.each { |param| observe_param(ctx, param) }
      end
    end

    # Check reference integrity of all local variables, for all possible
    # sequences of execution for their use sites.
    def observe_reference_integrity(ctx)
      @analysis.by_name_and_location.each { |local_name, by_location|
        @flow.each_possible_order_of(by_location.keys) { |ordered_locations|
          use_sites = ordered_locations.map { |loc| by_location[loc] }
          observe_reference_integrity_of_order(ctx, use_sites)
        }
      }
    end

    # Pretend to execute the given use sites in the given order,
    # checking that reference integrity invariants are successfully preserved.
    def observe_reference_integrity_of_order(ctx, use_sites)
      observed_write_index : Int32? = nil
      observed_consume_index : Int32? = nil

      use_sites.each_with_index { |use_site, index|
        if use_site.reads_existing_value || use_site.consumes_existing_value
          if observed_consume_index
            consume_site = use_sites[observed_consume_index]
            use_site.observe_error_after_consume(consume_site)
          end

          if observed_write_index
            write_site = use_sites[observed_write_index]
            use_site.observe_sometimes_after_write(write_site)
          else
            use_site.observe_error_without_prior_write unless use_site.local_name == "@"
          end
        end

        if use_site.consumes_existing_value
          observed_consume_index = index
        end

        if use_site.writes_new_value
          observed_write_index = index
          observed_consume_index = nil
        end
      }
    end

    # Emit all errors gathered during previous analysis.
    def emit_errors(ctx)
      @analysis.each_use_site.each(&.emit_errors(ctx))
    end
  end

  class Pass < Mare::Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      refer_type = ctx.refer_type[f_link]
      flow = ctx.flow[f_link]
      classify = ctx.classify[f_link]
      deps = {refer_type, flow, classify}
      prev = ctx.prev_ctx.try(&.local)

      # TODO: Re-enable cache when it doesn't crash:
      # maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, *deps)

        f.params.try(&.terms.each { |param| visitor.observe_param(ctx, param) })
        f.body.try(&.accept(ctx, visitor))

        visitor.observe_reference_integrity(ctx)
        visitor.emit_errors(ctx)

        visitor.analysis
      # end
    end
  end
end
