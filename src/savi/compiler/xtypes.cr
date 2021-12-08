##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
# Also, experimentation is under way with a different approach to this pass.
# This pass has been named XTypes and the Types pass is for new experimentation.
#
module Savi::Compiler::XTypes
  struct Analysis
    @scope : TypeVariable::Scope

    def initialize(@scope)
      @constraint_summaries = {} of TypeVariable => AlgebraicType
      @assignment_summaries = {} of TypeVariable => AlgebraicType
      @resolved = {} of TypeVariable => AlgebraicType
    end

    def [](var)
      @resolved[var]
    end
    def []?(var)
      @resolved[var]?
    end

    protected def set_resolved(var, type)
      @resolved[var] = type
    end

    def calculate_constraint_summary(var)
      @resolved[var]? || begin
        @constraint_summaries[var] ||= begin
          raise "wrong scope" if var.scope != @scope
          yield
        end
      end
    end

    def calculate_assignment_summary(var)
      @resolved[var]? || begin
        @assignment_summaries[var] ||= begin
          raise "wrong scope" if var.scope != @scope
          yield
        end
      end
    end
  end

  struct Cursor
    @ctx : Context
    @pass : Pass
    property! current_pos : Source::Pos

    def initialize(@ctx, @pass)
      @reached_scopes = Set(TypeVariable::Scope).new
      @reached = Set(TypeVariable).new
      @facts = [] of {Source::Pos, AlgebraicType}
    end

    def start
      @current_pos = nil
      @reached_scopes.clear
      @reached.clear
      @facts.clear
      self
    end

    def reach(var)
      return if @reached.includes?(var)
      @reached_scopes.add(var.scope)
      @reached.add(var)
      yield
    end

    def add_fact(pos, type)
      @facts << {pos, type}
    end

    def add_fact_at_current_pos(type)
      @facts << {current_pos, type}
    end

    def each_fact
      @facts.each { |pos, type| yield ({pos, type}) }
    end

    private def current_facts_offset
      @facts.size
    end

    private def transform_facts_since(offset)
      @facts.map_with_index!(offset) { |fact, index|
        (yield fact).as({Source::Pos, AlgebraicType})
      }
    end

    private def consume_facts_as_union_since(offset)
      facts_union : AlgebraicType? = nil
      while current_facts_offset > offset
        if facts_union
          facts_union = facts_union.unite(@facts.pop.last)
        else
          facts_union = @facts.pop.last
        end
      end
      facts_union
    end

    private def consume_facts_as_intersection_since(offset)
      facts_intersection : AlgebraicType? = nil
      while current_facts_offset > offset
        if facts_intersection
          facts_intersection = facts_intersection.intersect(@facts.pop.last)
        else
          facts_intersection = @facts.pop.last
        end
      end
      facts_intersection
    end

    def trace_as_assignment_with_transform(type)
      pre_offset = current_facts_offset
      type.trace_as_assignment(self)
      transform_facts_since(pre_offset) { |pos, inner|
        {pos, yield inner}
      }
    end

    def trace_as_assignment_with_two_step_transform(type_1, type_2)
      pre_offset = current_facts_offset

      # Trace type_1 and consume its facts as a union.
      type_1.trace_as_assignment(self)
      type_1_facts_union = consume_facts_as_union_since(pre_offset)

      # If type_1 emitted no facts, don't even both tracing type_2.
      return unless type_1_facts_union

      # Trace type_2 and transform it using the facts union from type_1.
      type_2.trace_as_assignment(self)
      transform_facts_since(pre_offset) { |pos, inner|
        {pos, yield type_1_facts_union, inner}
      }
    end

    def trace_call_return_as_assignment(
      pos : Source::Pos,
      call : AST::Call,
      receiver : AlgebraicType,
    )
      pre_offset = current_facts_offset
      receiver.trace_as_assignment(self)
      receiver_union = consume_facts_as_union_since(pre_offset)
      return unless receiver_union
      receiver_union.trace_call_return_as_assignment(self, call)
    end

    def trace_var_upper_bound_call_return_as_assignment(
      pos : Source::Pos,
      call : AST::Call,
      var : TypeVariable,
    )
      pre_offset = current_facts_offset
      var.trace_as_constraint(self)
      receiver_intersection = consume_facts_as_intersection_since(pre_offset)
      return unless receiver_intersection
      receiver_intersection.trace_call_return_as_assignment(self, call)
    end

    def trace_call_return_as_assignment_with_transform(
      call : AST::Call,
      receiver : AlgebraicType,
    )
      pre_offset = current_facts_offset
      receiver.trace_call_return_as_assignment(self, call)
      transform_facts_since(pre_offset) { |pos, inner|
        {pos, yield inner}
      }
    end

    def trace_nominal_call_return_as_assignment(
      call : AST::Call,
      nominal_type : NominalType,
      nominal_cap : NominalCap,
    )
      @pass.trace_nominal_call_return_as_assignment(
        @ctx, self, nominal_type, nominal_cap, call.ident
      )
    end
  end

  class Pass
    def initialize
      @f_analyses = {} of Program::Function::Link => Analysis
    end

    def [](f_link : Program::Function::Link)
      @f_analyses[f_link]
    end
    def []?(f_link : Program::Function::Link)
      @f_analyses[f_link]?
    end

    def run(ctx : Context)
      run_for_types(ctx)
      run_for_func_edges(ctx)
    end

    def run_for_types(ctx : Context)
      cursor = Cursor.new(ctx, self)

      ctx.program.packages.each { |l|
        l_link = l.make_link
        l.types.each { |t|
          t_link = t.make_link(l_link)
          xtypes_graph = ctx.xtypes_graph[t_link]
          analysis = Analysis.new(t_link)

          xtypes_graph.field_type_vars.each { |name, var|
            resolved = var.calculate_assignment_summary(analysis, cursor.start)
            analysis.set_resolved(var, resolved)
          }
        }
      }
    end

    def run_for_func_edges(ctx : Context)
      cursor = Cursor.new(ctx, self)

      ctx.program.packages[2].tap { |l| # TODO: all packages
        l_link = l.make_link
        l.types.each { |t|
          t_link = t.make_link(l_link)
          t.functions.each { |f|
            f_link = f.make_link(t_link)
            xtypes_graph = ctx.xtypes_graph[f_link]
            analysis = @f_analyses[f_link] = Analysis.new(f_link)

            xtypes_graph.return_var.tap { |var|
              resolved = var.calculate_assignment_summary(analysis, cursor.start)
              analysis.set_resolved(var, resolved)
            }
          }
        }
      }
    end

    def trace_nominal_call_return_as_assignment(
      ctx, cursor, nominal_type, nominal_cap, f_ident,
    )
      t_link = nominal_type.link
      t = t_link.resolve(ctx)
      f = t.find_func?(f_ident.value)
      raise "function not found" unless f # TODO: nice error
      f_link = f.make_link(t_link)
      xtypes_graph = ctx.xtypes_graph[f_link]
      xtypes_graph_parent = xtypes_graph.parent.not_nil!

      # Take a fast path if we don't need to bind any variables.
      if f.cap.value != "box" && !nominal_type.args
        xtypes_graph.return_var.trace_as_assignment(cursor)
      end

      bind_variables = {} of TypeVariable => AlgebraicType

      # When calling a box function, we bind the specific receiver cap.
      if f.cap.value == "box"
        bind_variables[xtypes_graph.receiver_cap_var] = nominal_cap
      end

      # If the nominal type has type parameters, bind them.
      nominal_type_args = nominal_type.args
      if nominal_type_args
        xtypes_graph_parent.type_param_vars.each_with_index { |var, index|
          bind_variables[var] = nominal_type_args[index]
        }
      end

      # Trace with the specified bindings.
      cursor.trace_as_assignment_with_transform(xtypes_graph.return_var) { |type|
        type.bind_variables(bind_variables).first
      }
    end
  end
end
