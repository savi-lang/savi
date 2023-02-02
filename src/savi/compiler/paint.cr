##
# The purpose of the Paint pass is to pick a "color" for each function in the
# program, such that functions which have the same name are guaranteed to have
# the same color but no two functions in a single type have the same color.
# The color id is then used to generate virtual-table call indexes, such that
# calling a function on a trait (with a specific color) will result in the
# function of the same name on the underlying concrete type being called
# (because it has the same color). In the future, this pass may need to become
# more sophisticated, perhaps to deal with multiple-dispatch forms.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the program level.
# This pass produces output state at the per-function level.
#
class Savi::Compiler::Paint
  alias Color = Int32

  def initialize
    @defs_by_sig_compat = Hash(String, Set(Reach::Def)).new
    @defs_by_color      = Hash(Color, Set(Reach::Def)).new
    @next_color         = 0

    @results = Hash(Reach::Def, Hash(String, Color)).new
  end

  def run(ctx)
    # Collect a mapping of the types that implement each function name.
    ctx.reach.each_type_def.each do |reach_def|
      ctx.reach.abstractly_reached_funcs_for(reach_def).each do |reach_func|
        next if reach_func.link.is_hygienic?
        next if reach_func.reified.func(ctx).has_tag?(:ffi)

        observe_func(ctx, reach_def, reach_func)
      end
    end

    # Assign colors to function names, then clean up all other memory.
    assign_colors
    cleanup
  end

  # Public: return the color id for the given function,
  # assuming that this pass has already been run on the program.
  def [](ctx, reach_func, for_continue = false) : Color
    self[ctx, reach_func, for_continue].not_nil!
  end

  def []?(ctx, reach_func : Reach::Func, for_continue : Bool = false) : Color?
    name = reach_func.signature.codegen_compat_name(ctx)
    name = "#{name}.CONTINUE" if for_continue
    @results[reach_func.reach_def]?.try(&.[]?(name))
  end

  # Return the next color id to assign when we need a previously unused color.
  private def next_color
    color = @next_color
    @next_color += 1
    color
  end

  # Take notice of the given function, under the given type.
  private def observe_func(ctx, reach_def : Reach::Def, reach_func : Reach::Func)
    sig = reach_func.signature
    name = sig.codegen_compat_name(ctx)
    set = @defs_by_sig_compat[name] ||= Set(Reach::Def).new
    set.add(reach_def)

    # If this function yields, paint another selector for its continue function.
    if ctx.inventory[reach_func.reified.link].can_yield?
      name = "#{name}.CONTINUE"
      set = @defs_by_sig_compat[name] ||= Set(Reach::Def).new
      set.add(reach_def)
    end
  end

  # For all the function signatures we know about, assign "color" ids
  # such that no type will have multiple functions of the same color,
  # and as few as possible (well... as is practical) color ids are used.
  private def assign_colors
    @defs_by_sig_compat.each do |sig_compat, sig_defs|
      # Try to find an existing color that is unused in all of these sig_defs.
      pair =
        @defs_by_color.to_a.find { |_, c_types| (sig_defs & c_types).empty? }

      # Otherwise, generate a new color id and start to populate it.
      pair ||= (
        color = next_color
        color_defs = Set(Reach::Def).new
        @defs_by_color[color] = color_defs
        {color, color_defs}
      )

      # Insert these sig_defs into the color_defs set for this color,
      # and insert this name/color pair for each def into our result map.
      color, color_defs = pair
      color_defs.concat(sig_defs)
      sig_defs.each do |sig_def|
        colors_by_sig = @results[sig_def] ||= Hash(String, Color).new
        colors_by_sig[sig_compat] = color
      end
    end
  end

  # Delete unnecessary information from our memory (everything but the results).
  private def cleanup
    @defs_by_sig_compat.clear
    @defs_by_color.clear
  end
end
