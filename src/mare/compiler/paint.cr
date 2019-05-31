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
class Mare::Compiler::Paint
  alias Color = Int32
  
  def initialize
    @types_by_func_name = Hash(String, Set(Program::Type)).new
    @types_by_color = Hash(Color, Set(Program::Type)).new
    @color_by_func_name = Hash(String, Color).new
    @next_color = 0
  end
  
  def run(ctx)
    # Collect a mapping of the types that implement each function name.
    ctx.program.types.each do |t|
      t.functions.each do |f|
        next if f.has_tag?(:hygienic)
        next unless ctx.reach.reached_func?(f)
        
        ctx.infer.infers_for(f).each do |infer|
          observe_func(t, infer.reified)
        end
      end
    end
    
    # Assign colors to function names, then clean up all other memory.
    assign_colors
    cleanup
  end
  
  # Public: return the color id for the given function,
  # assuming that this pass has already been run on the program.
  def [](rf); color_of(rf) end
  def color_of(rf : Infer::ReifiedFunction) : Color
    @color_by_func_name[rf.name]
  end
  
  # Return the next color id to assign when we need a previously unused color.
  private def next_color
    color = @next_color
    @next_color += 1
    color
  end
  
  # Take notice of the given function, under the given type.
  private def observe_func(t, rf)
    name = rf.name
    set = @types_by_func_name[name] ||= Set(Program::Type).new
    set.add(t)
  end
  
  # For all the function names we know about, assign "color" ids
  # such that no type will have multiple functions of the same color,
  # and as few as possible (well... as is practical) color ids are used.
  # TODO: take into account other discriminators besides function names?
  private def assign_colors
    @types_by_func_name.each do |name, name_types|
      # Try to find an existing color that is unused in all of these name_types.
      result =
        @types_by_color.to_a.find { |_, c_types| (name_types & c_types).empty? }
      
      # Otherwise, generate a new color id and start to populate it.
      result ||= (
        color = next_color
        color_types = Set(Program::Type).new
        @types_by_color[color] = color_types
        {color, color_types}
      )
      
      # Insert these name_types into the color_types set for this color,
      # and insert this name/color pair into our result map.
      color, color_types = result
      color_types.concat(name_types)
      @color_by_func_name[name] = color
    end
  end
  
  # Delete unnecessary information from our memory (everything but the results).
  private def cleanup
    @types_by_func_name.clear
    @types_by_color.clear
  end
end
