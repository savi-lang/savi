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
  class UseSite
    getter node : AST::Identifier
    getter ref : (Refer::Local | Refer::Self)
    getter flow_location : Flow::Location
    getter reads_existing_value : Bool = false
    getter writes_new_value : Bool = false
    getter consumes_existing_value : Bool = false
    getter is_unreachable : Bool = false
    getter is_first_lexical_appearance : Bool = false

    def pos; @node.pos; end

    def initialize(@node, @ref, @flow_location,
      reads = false,
      writes = false,
      consumes = false,
      unreachable = false
    )
      @reads_existing_value = reads
      @writes_new_value = writes
      @consumes_existing_value = consumes
      @is_unreachable = unreachable

      # This state will be populated later within the pass, after all use sites
      # have been observed and can be related to one another in a graph.
      @predecessors = Set(UseSite).new
      @sometimes_no_predecessor = false
    end

    def is_initial_site
      @sometimes_no_predecessor
    end

    def show
      "#{
        @ref.name
      }:#{
        @reads_existing_value ? "R" : ""
      }#{
        @writes_new_value ? "W" : ""
      }#{
        @consumes_existing_value ? "C" : ""
      }#{
        @is_unreachable ? "U" : ""
      }:#{
        @flow_location.show
      }"
    end

    protected def observe_is_first_lexical_appearance
      @is_first_lexical_appearance = true
    end

    protected def observe_predecessor(other)
      if other
        @predecessors << other
      else
        @sometimes_no_predecessor = true
      end
    end

    protected def emit_errors(ctx)
      # Don't bother showing errors for unreachable use sites.
      # They're likely to be based on inaccurate information anyway.
      return if @is_unreachable

      needs_value = (@reads_existing_value || @consumes_existing_value) && ref.name != "@"
      if needs_value
        # If nil is a predecessor, that means this is the first occurrence
        # of the local variable along at least one flow path. In such a case,
        # it has no value assigned to it yet, so it's not safe to read/consume.
        if @sometimes_no_predecessor
          predecessor_writes = @predecessors.select(&.writes_new_value)

          message = if predecessor_writes.any?
            "This local variable isn't guaranteed to have a value yet"
          else
            "This local variable has no assigned value yet"
          end

          ctx.error_at self, message, predecessor_writes.map { |write_site|
            {write_site.pos, "this assignment is not guaranteed to precede that usage"}
          }
        end

        # If a consume is a predecessor, this means that the value that was
        # has been consumed, so on this flow path is not safe to read/consume.
        predecessor_consumes = @predecessors.select(&.consumes_existing_value)
        if needs_value && predecessor_consumes.any?
          message = if @consumes_existing_value
            "This local variable can't be consumed again"
          else
            "This local variable has no value anymore"
          end

          ctx.error_at self, message, predecessor_consumes.map { |consume_site|
            {consume_site.pos, "it is consumed in a preceding place here"}
          }
        end
      end
    end
  end

  struct Analysis
    def initialize
      @use_sites = {} of AST::Node => UseSite
      @by_ref_and_location = {} of Refer::Info => Hash(Int32, Array(UseSite))
    end

    def [](node : AST::Node); @use_sites[node]; end
    def []?(node : AST::Node); @use_sites[node]?; end

    protected def each_use_site
      @use_sites.each_value
    end

    protected def by_ref_and_location
      @by_ref_and_location
    end

    def each_use_site_for(ref)
      @by_ref_and_location[ref].try(&.each_value { |block_use_sites|
        block_use_sites.each { |use_site| yield use_site }
      })
    end

    def each_initial_site_for(ref)
      each_use_site_for(ref) { |use_site|
        yield use_site if use_site.is_initial_site
      }
    end

    def any_initial_site_for(ref)
      each_initial_site_for(ref) { |use_site|
        return use_site
      }
      raise "unreachable: unknown local"
    end

    protected def observe_use_site(node : AST::Node, use_site : UseSite)
      @use_sites[node] = use_site

      block_index = use_site.flow_location.block_index
      if @by_ref_and_location.has_key?(use_site.ref)
        by_location = @by_ref_and_location[use_site.ref]
        if by_location.has_key?(block_index)
          block_use_sites = by_location[block_index]

          # Do a sorted insert by sequence number within the block.
          sequence_number = use_site.flow_location.sequence_number
          insert_after_index = block_use_sites.rindex { |other|
            sequence_number > other.flow_location.sequence_number
          }
          block_use_sites.insert(insert_after_index.try(&.+(1)) || 0, use_site)
        else
          by_location[block_index] = [use_site]
        end
      else
        use_site.observe_is_first_lexical_appearance
        @by_ref_and_location[use_site.ref] =
          { use_site.flow_location.block_index => [use_site] }
      end

      use_site
    end

    protected def remove_use_site_at(node : AST::Node)
      use_site = @use_sites.delete(node)
      return unless use_site

      block_index = use_site.flow_location.block_index
      by_location = @by_ref_and_location[use_site.ref]
      block_use_sites = by_location[block_index]
      block_use_sites.delete(use_site)
      by_location.delete(block_index) if block_use_sites.empty?

      use_site
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter refer : Refer::Analysis
    getter flow : Flow::Analysis

    def initialize(@analysis, @refer, @flow)
    end

    def visit(ctx, node)
      observe(ctx, node)
      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    # Handle reading from a local variable.
    def observe(ctx, node : AST::Identifier)
      ref = @refer[node]?
      return unless ref.is_a?(Refer::Local) || ref.is_a?(Refer::Self)

      flow_location = @flow.location_of?(node)
      return unless flow_location

      is_unreachable = @flow.block_at(flow_location.block_index).unreachable?
      @analysis.observe_use_site(node, UseSite.new(
        node,
        ref,
        flow_location,
        reads: true,
        unreachable: is_unreachable,
      ))
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

      old_use_site = @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      return unless flow_location

      is_unreachable = @flow.block_at(flow_location.block_index).unreachable?
      use_site = @analysis.observe_use_site(node, UseSite.new(
        ident,
        refer[ident]?.as(Refer::Local | Refer::Self),
        flow_location,
        reads: reads,
        writes: true,
        unreachable: is_unreachable,
      ))
      use_site.observe_is_first_lexical_appearance \
        if old_use_site.try(&.is_first_lexical_appearance)
    end

    # Handle consuming a local variable.
    def observe(ctx, node : AST::Prefix)
      ident = node.term
      return unless node.op.value == "--" && ident.is_a?(AST::Identifier)

      old_use_site = @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      return unless flow_location

      is_unreachable = @flow.block_at(flow_location.block_index).unreachable?
      use_site = @analysis.observe_use_site(node, UseSite.new(
        ident,
        refer[ident]?.as(Refer::Local | Refer::Self),
        flow_location,
        consumes: true,
        unreachable: is_unreachable,
      ))
      use_site.observe_is_first_lexical_appearance \
        if old_use_site.try(&.is_first_lexical_appearance)
    end

    # All other node types have no special logic.
    def observe(ctx, node)
    end

    # Observing a parameter definition has its own logic.
    def observe_param(ctx, node)
      ident = AST::Extract.param(node).first

      old_use_site = @analysis.remove_use_site_at(ident)

      flow_location = @flow.location_of?(node)
      return unless flow_location

      is_unreachable = @flow.block_at(flow_location.block_index).unreachable?
      use_site = @analysis.observe_use_site(node, UseSite.new(
        ident,
        refer[ident]?.as(Refer::Local | Refer::Self),
        flow_location,
        writes: true,
        unreachable: is_unreachable,
      ))
      use_site.observe_is_first_lexical_appearance \
        if old_use_site.try(&.is_first_lexical_appearance)
    end

    # Observing a call site entails observing any yield parameters.
    def observe_call(ctx, node)
      ident, args, yield_params, yield_block = AST::Extract.call(node)

      if yield_params
        yield_params.terms.each { |param| observe_param(ctx, param) }
      end
    end

    def each_possible_predecessor_of(use_site : UseSite, &yield_block : UseSite? -> _)
      block_index = use_site.flow_location.block_index
      by_location = @analysis.by_ref_and_location[use_site.ref]
      block_use_sites = by_location[block_index]

      # If we have is a predecessor use site in the same block, yield it
      # and then return - we're done, as this is the only direct predecessor.
      saw_this_use_site = false
      block_use_sites.reverse_each { |that_use_site|
        if saw_this_use_site
          yield_block.call(that_use_site)
          return
        elsif that_use_site == use_site
          saw_this_use_site = true
        end
      }

      # If this is the first lexical appearance of the given local variable,
      # we treat it as if it had no predecessors, as an optimization.
      if use_site.is_first_lexical_appearance
        yield_block.call(nil)
        return
      end

      # Otherwise, we need to look at the blocks that precede this block,
      # digging recursively through those blocks finding possible predecessors.
      block = @flow.block_at(block_index)
      each_possible_predecessor_recurse(use_site, by_location, block, [] of Int32, &yield_block)
    end
    def each_possible_predecessor_recurse(
      orig_use_site,
      by_location,
      from_block : Flow::Block,
      seen_cyclic_edges : Array(Int32),
      &yield_block : UseSite? -> _
    )
      no_predecessors = true
      from_block.each_predecessor { |block|
        next if block.unreachable?

        no_predecessors = false

        # If this block has any use sites in it, the final one is our nearest.
        # Yield it and then go to the next path without recursing further.
        block_use_sites = by_location[block.index]?
        if block_use_sites
          yield_block.call(block_use_sites.last)
          next
        end

        # If this is a cyclic edge block that we've already seen,
        # we will gain no new information by recursing into it again.
        if block.cyclic_edge?
          next if seen_cyclic_edges.includes?(block.index)
          seen_cyclic_edges << block.index
        end

        # Otherwise, we need to recurse into that block.
        each_possible_predecessor_recurse(
          orig_use_site,
          by_location,
          block,
          seen_cyclic_edges,
          &yield_block
        )
      }

      # If we didn't have any predecessors, we need to yield nil,
      # because we've reached an entry block that indicates a path
      # with no predecessors to write the local we're trying to read.
      yield_block.call(nil) if no_predecessors
    end

    def observe_predecessors(ctx)
      @analysis.each_use_site.each { |use_site|
        each_possible_predecessor_of(use_site) { |other|
          use_site.observe_predecessor(other)
        }
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
      refer = ctx.refer[f_link]
      flow = ctx.flow[f_link]
      deps = {refer, flow}
      prev = ctx.prev_ctx.try(&.local)

      # TODO: Re-enable cache when it doesn't crash:
      # maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, *deps)
        f.params.try(&.terms.each { |param| visitor.observe_param(ctx, param) })
        f.body.try(&.accept(ctx, visitor))

        visitor.observe_predecessors(ctx)
        visitor.emit_errors(ctx)

        visitor.analysis
      # end
    end
  end
end
