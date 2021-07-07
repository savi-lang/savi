require "./pass/analyze"

##
# The Flow pass is meant to clearly mark the order of expression evaluation,
# including the static order of expressions in the same sequential block,
# as well as the relative conditional branching among different blocks.
#
# The analysis lets us look up relationships between expressions where one
# "sometimes happens before" the other, "always happens before" the other,
# or "never happens before" the other. This allows us to do other checks
# later in the compiler which make use of this information to validate safety.
#
# This is similar to the purpose of LLVM's "dominator tree" data structure,
# which can be learned about in various video and text presentations on the web,
# though our own analysis doesn't take exactly the same data structure approach.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::Flow
  struct Location
    getter block_index : Int32
    getter sequence_number : Int32

    def initialize(@block_index, @sequence_number)
    end

    def show
      "(#{@block_index}, #{@sequence_number})"
    end
  end

  struct Block
    getter index : Int32
    getter containing_node : AST::Node

    def initialize(@index, @containing_node)
      @pre = [] of Block
      @pre_true = [] of Block
      @pre_false = [] of Block
      @flags = Set(Symbol).new
    end

    def cyclic_edge?
      @flags.includes?(:cyclic_edge)
    end
    def unreachable?
      @flags.includes?(:unreachable)
    end
    def reachable?
      !unreachable?
    end

    def no_predecessors?; !any_predecessors?; end
    def any_predecessors?
      @pre.any? ||
      @pre_true.any? ||
      @pre_false.any?
    end

    def any_predecessors_reachable?
      @pre.any?(&.reachable?) ||
      @pre_true.any?(&.reachable?) ||
      @pre_false.any?(&.reachable?)
    end

    def each_predecessor(&block : Block -> _)
      @pre.each(&block)
      @pre_true.each(&block)
      @pre_false.each(&block)
    end

    # These functions are used for easily visualizing and testing.
    def show : String
      "#{show_name}(#{show_predecessors})"
    end
    def show_name
      "#{index}#{
        cyclic_edge? ? "C" : ""
      }#{
        unreachable? ? "U" : ""
      }"
    end
    def show_predecessors : String
      if index == 0
        raise "entry block can't have predecessors!" \
          if @pre_true.any? || @pre_false.any? || @pre.any?
        "entry"
      else
        (
          @pre_true.map(&.show_name.+("T")) +
          @pre_false.map(&.show_name.+("F")) +
          @pre.map(&.show_name)
        ).join(" | ")
      end
    end

    protected def comes_after(block)
      @pre << block
    end
    protected def comes_after_if_true(block)
      @pre_true << block
    end
    protected def comes_after_if_false(block)
      @pre_false << block
    end
    protected def mark_as_unreachable
      @flags << :unreachable
    end
    protected def mark_as_cyclic_edge
      @flags << :cyclic_edge
    end
  end

  struct Analysis
    def initialize
      @blocks = [] of Block
      @locations = {} of AST::Node => Location
    end

    def location_of?(node : AST::Node) : Location?
      @locations[node]?
    end
    def block_at(index : Int32) : Block
      @blocks[index]
    end
    def block_at(node : AST::Node) : Block
      block_at(@locations[node].block_index)
    end

    # Convenience method for checking if the given node always jumps away,
    # which is true if it is a literal jump, or if it is assigned
    # to a flow block that is marked as unreachable.
    def jumps_away?(node)
      node.is_a?(AST::Jump) || block_at(node).unreachable?
    end

    ENTRY_BLOCK_INDEX = 0
    EXIT_BLOCK_INDEX = 1
    def entry_block; @blocks[ENTRY_BLOCK_INDEX]; end
    def exit_block; @blocks[EXIT_BLOCK_INDEX]; end

    def each_possible_order_of(
      locations : Array(Location),
      &yield_block : Array(Location) -> _
    )
      # Get each possible unique order of the blocks for these locations,
      # then yield the list of locations with those in the same block
      # ordered according to their sequence number, which is guaranteed to
      # be in the correct relative order for locations in the same block
      # (because within a block, execution has one possible sequential order).
      query_indices = locations.map(&.block_index).uniq
      all_possible_unique_orders_of_blocks(query_indices).each { |block_indices|
        result = [] of Location
        block_indices.each { |block_index|
          block_locations = locations.select(&.block_index.==(block_index))
          result.concat(block_locations.sort_by(&.sequence_number))
        }
        yield_block.call(result)
      }
    end

    private def all_possible_unique_orders_of_blocks(query : Array(Int32))
      result = [] of Array(Int32)
      each_possible_order_of_blocks(query, exit_block) { |list| result << list }
      result.uniq!
    end

    private def each_possible_order_of_blocks(
      query : Array(Int32),
      block : Block,
      crumbs = [] of Int32,
      &yield_block : Array(Int32) -> _
    )
      # If we've come into a block with no predecessors, we're done.
      # We reverse and filter to the relevant block indices for our result.
      if block.no_predecessors?
        yield_block.call(crumbs
          .reverse_each
          .select { |index| query.includes?(index) }
          .to_a
        )
        return
      end

      # Otherwise, we need to recurse to every possible predecessor block
      # of the current block under consideration. We catch every possible flow.
      block.each_predecessor { |pre_block|
        # Skip this predecessor block if we've already seen it twice.
        # This avoids us doing infinite loops when encountering cyclical flows,
        # such as legitimately looping control flow structures.
        # However, we must visit at least twice to get the effect of checking
        # that it's safe to visit that block more than once in downstream logic.
        next if crumbs.count(&.==(pre_block.index)) > 1

        # Recurse into this function again with the new block and added crumb.
        each_possible_order_of_blocks(
          query, pre_block, crumbs + [pre_block.index], &yield_block
        )
      }
    end

    protected def new_block(containing_node)
      block = Block.new(@blocks.size, containing_node)
      @blocks << block
      block
    end

    protected def observe_node(node : AST::Node, block : Block)
      @locations[node] = Location.new(block.index, @locations.size)
    end

    protected def propagate_unreachable_statuses
      # Pass over all the blocks looking for ones we can mark as unreachable,
      # until we run out of blocks to mark and can call it done.
      keep_going = true
      while keep_going
        keep_going = false
        @blocks.each do |block|
          next if block.index == 0
          next if block.unreachable?
          next if block.any_predecessors_reachable?

          # We found an unreachable block that wasn't marked as such.
          # Mark it, and keep our iteration going to keep propagating
          # until we have marked all of them that can be marked.
          keep_going = true
          block.mark_as_unreachable
        end
      end
    end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis

    def initialize(func : Program::Function, @analysis)
      @jump_target_stacks = {} of AST::Jump::Kind => Array(Block)

      # Every function starts with an entry block as the current block,
      # as well as an exit block that we hold until to follow the final block.
      @current_block = @analysis.new_block(func.ast).as(Block)
      raise "not the entry block!" if @current_block != @analysis.entry_block
      @exit_block = @analysis.new_block(func.ast).as(Block)
      raise "not the exit block!" if @exit_block != @analysis.exit_block

      # The exit block is the baseline jump target for these jump kinds:
      push_jump_target(AST::Jump::Kind::Return, @exit_block)
      push_jump_target(AST::Jump::Kind::Error, @exit_block)
    end

    def finish_analysis
      # Whatever block is at the end of the function is a natural return value,
      # so we mark it as a predecessor of the implicit exit block.
      @exit_block.comes_after(@current_block)

      # Do remaining analysis over the set of all blocks.
      @analysis.propagate_unreachable_statuses

      @analysis
    end

    # We track a stack of jump targets for each kind of jump,
    # so that when such a jump is encountered, we can mark it as a predecessor
    # for the given jump target block, tracking that relationship.
    def current_jump_target_for(kind : AST::Jump::Kind)
      @jump_target_stacks[kind]?.try(&.last?)
    end
    def with_jump_target(kind : AST::Jump::Kind, block : Block)
      push_jump_target(kind, block)
      yield
    ensure
      pop_jump_target(kind)
    end
    def push_jump_target(kind : AST::Jump::Kind, block : Block)
      (@jump_target_stacks[kind] ||= [] of Block) << block
      block
    end
    def pop_jump_target(kind : AST::Jump::Kind)
      @jump_target_stacks[kind].pop
    end

    # This visitor never replaces nodes, it just observes them and returns them.
    # If we observe a Jump node, we also take some special control flow action.
    def visit(ctx, node)
      @analysis.observe_node(node, @current_block)

      case node
      when AST::Jump then visit_jump(ctx, node)
      when AST::Call then visit_call(ctx, node)
      else nil
      end

      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def visit_children?(ctx, node : AST::Node)
      # Defer natural visiting of children for certain node types that have
      # control flow logic within them; we will visit those in a special way.
      case node
      when AST::Choice
        deep_visit_choice(ctx, node)
        false # don't visit children naturally; we visited them just above
      when AST::Loop
        deep_visit_loop(ctx, node)
        false # don't visit children naturally; we visited them just above
      when AST::Try
        deep_visit_try(ctx, node)
        false # don't visit children naturally; we visited them just above
      when AST::Call
        visited = deep_visit_call(ctx, node)
        !visited # only visit children if we didn't visit them already
      else
        true # visit the children of all other node types as normal
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def visit_deferred_child(ctx, node, block)
      # When we visit a deferred child, we go in with a current block and
      # we come out with a possibly different current block following it.
      # The new current block will be different if there happens to be
      # control flow logic inside of the child we are visiting.
      @current_block = block
      node.accept(ctx, self)
      @current_block
    end

    def deep_visit_choice(ctx, node : AST::Choice)
      before_block = @current_block
      after_block = @analysis.new_block(@current_block.containing_node)

      prior_cond_block = nil
      node.list.each { |cond, body|
        # A choice condition comes after either the prior failed condition,
        # or the before block if this is the first condition in the choice.
        cond_block = @analysis.new_block(cond)
        if prior_cond_block
          cond_block.comes_after_if_false(prior_cond_block)
        else
          cond_block.comes_after(before_block)
        end
        cond_block = visit_deferred_child(ctx, cond, cond_block)
        prior_cond_block = cond_block

        # A choice body comes after the condition if the condition was true.
        body_block = @analysis.new_block(body)
        body_block.comes_after_if_true(cond_block)
        body_block = visit_deferred_child(ctx, body, body_block)

        # After we execute a choice body, the code after the choice comes next.
        after_block.comes_after(body_block)
      }

      @current_block = after_block
    end

    def deep_visit_loop(ctx, node : AST::Loop)
      before_block = @current_block
      after_block = @analysis.new_block(@current_block.containing_node)

      initial_cond_block = @analysis.new_block(node.initial_cond)
      body_block = start_of_body_block = @analysis.new_block(node.body)
      repeat_cond_block = @analysis.new_block(node.repeat_cond)
      else_block = @analysis.new_block(node.else_body)

      # The initial condition comes first.
      initial_cond_block.comes_after(before_block)
      initial_cond_block = visit_deferred_child(ctx, node.initial_cond, initial_cond_block)

      # The loop body comes after the initial condition if it's true.
      # If we see a break jump in the body, it jumps to the after block.
      # If we see a next jump in the body, it jumps to the repeat condition.
      start_of_body_block = body_block
      body_block.comes_after_if_true(initial_cond_block)
      with_jump_target(AST::Jump::Kind::Break, after_block) {
        with_jump_target(AST::Jump::Kind::Next, repeat_cond_block) {
          body_block = visit_deferred_child(ctx, node.body, body_block)
        }
      }

      # The repeat condition comes after the body.
      repeat_cond_block.comes_after(body_block)
      repeat_cond_block = visit_deferred_child(ctx, node.repeat_cond, repeat_cond_block)

      # We return to the start of the body if the repeat condition is true.
      # Note that the body_block variable is not used here because it points
      # to the block used for the end of the body, which won't be the same as
      # the block that started the body if the body contains other control flow.
      repeat_cond_block.mark_as_cyclic_edge
      start_of_body_block.comes_after_if_true(repeat_cond_block)

      # The else block comes after the initial condition if it's false.
      else_block.comes_after_if_false(initial_cond_block)
      else_block = visit_deferred_child(ctx, node.else_body, else_block)

      # After executing the else block or failing the repeat condition,
      # the block representing the code after the loop construct comes next.
      after_block.comes_after(else_block)
      after_block.comes_after_if_false(repeat_cond_block)

      @current_block = after_block
    end

    def deep_visit_try(ctx, node : AST::Try)
      before_block = @current_block
      after_block = @analysis.new_block(@current_block.containing_node)

      body_block = @analysis.new_block(node.body)
      else_block = @analysis.new_block(node.else_body)

      # We execute the body, using the else block as a jump target for errors.
      body_block.comes_after(before_block)
      with_jump_target(AST::Jump::Kind::Error, else_block) {
        body_block = visit_deferred_child(ctx, node.body, body_block)
      }

      # Any errors in the body will jump to this else block.
      else_block = visit_deferred_child(ctx, node.else_body, else_block)

      # Both the body block and else block lead into the after block.
      after_block.comes_after(body_block)
      after_block.comes_after(else_block)

      @current_block = after_block
    end

    def deep_visit_call(ctx, node : AST::Call) : Bool
      # In this part of the visitor, we deal with yield blocks at call sites.
      yield_params = node.yield_params
      yield_block_node = node.yield_block
      return false unless yield_block_node

      # Before doing anything else, we need to visit the children which were
      # deferred from being visited, but do not actually require from us any
      # special handling here. We visit them prior to the special handling.
      node.receiver.accept(ctx, self)
      node.ident.accept(ctx, self)
      node.args.try(&.accept(ctx, self))

      # Now we set up the control flow blocks we need to model the yield block.
      before_block = @current_block
      after_block = @analysis.new_block(@current_block.containing_node)
      yield_block = @analysis.new_block(yield_block_node)
      yield_exit_block = @analysis.new_block(yield_block_node)

      # The first possibility is that the function never yields,
      # in which case the after block comes immediately after the before block.
      after_block.comes_after(before_block)

      # It's also possible that the yield block executes, in which case
      # it comes after the before block (with unknown function code in between).
      # We also set up jump targets so that `break` will jump to the after block
      # and `next` will jump to the exit of the yield block.
      start_of_yield_block = yield_block
      yield_block.comes_after(before_block)
      with_jump_target(AST::Jump::Kind::Break, after_block) {
        with_jump_target(AST::Jump::Kind::Next, yield_exit_block) {
          yield_block = visit_deferred_child(ctx, yield_params, yield_block) if yield_params
          yield_block = visit_deferred_child(ctx, yield_block_node, yield_block)
        }
      }

      # The exit of the yield block comes after the yield block itself,
      # when reached naturally at the end of it rather than via `next`.
      yield_exit_block.comes_after(yield_block)

      # From the exit block, it is possible that we again run the yield block,
      # or we may be finished yielding, moving finally to the after block.
      start_of_yield_block.mark_as_cyclic_edge
      start_of_yield_block.comes_after(yield_exit_block)
      after_block.comes_after(yield_exit_block)

      @current_block = after_block

      true
    end

    def visit_jump(ctx, node : AST::Jump)
      target_block = current_jump_target_for(node.kind)
      if target_block
        target_block.comes_after(@current_block)
      else
        case node.kind
        when AST::Jump::Kind::Break
          ctx.error_at node,
            "A break can only be used inside a loop or yield block"
        when AST::Jump::Kind::Next
          ctx.error_at node,
            "A next can only be used inside a loop or yield block"
        else
          raise NotImplementedError.new("No target for Jump::#{node.kind}")
        end
      end

      # Directly following any jump is a block which is technically unreachable,
      # yet we mark the prior block as a predecessor for it because this will
      # allow flow-sensitive code (like type refinements) to still succeed.
      #
      # Some may argue that it is bad practice for us to allow unreachable code
      # to compile in a program, yet in practice it is quite convenient for a
      # programmer to briefly add an error or early return or similar while
      # iterating on their code, and we don't want to create friction in that
      # workflow unnecessarily - we can just allow the code to never be reached.
      #
      # To prevent bugs in production programs due to the programmer not knowing
      # a particular piece of code is unreachable, we can provide linting in
      # a separate pass of the compiler to show problems like that.
      # That linting pass can use the unreachability analysis we gather here.
      unreachable_block = @analysis.new_block(@current_block.containing_node)
      unreachable_block.mark_as_unreachable
      unreachable_block.comes_after(@current_block)
      @current_block = unreachable_block
    end

    def visit_call(ctx, node : AST::Call)
      return unless node.ident.value.ends_with?("!")

      target_block = current_jump_target_for(AST::Jump::Kind::Error).not_nil!
      target_block.comes_after(@current_block)

      after_block = @analysis.new_block(@current_block.containing_node)
      after_block.comes_after(@current_block)
      @current_block = after_block
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
      deps = {nil}
      prev = ctx.prev_ctx.try(&.flow)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(f, Analysis.new)

        f.params.try(&.accept(ctx, visitor))
        f.body.try(&.accept(ctx, visitor))

        visitor.finish_analysis
      end
    end
  end
end
