class Mare::Compiler::Paint
  def self.run(ctx)
    instance = ctx.program.paint = new
    instance.run(ctx.program)
  end
  
  alias Color = Int32
  
  def initialize
    @types_by_func_name = Hash(String, Set(Program::Type)).new
    @types_by_color = Hash(Color, Set(Program::Type)).new
    @color_by_func_name = Hash(String, Color).new
    @next_color = 0
  end
  
  def run(program)
    # Collect a mapping of the types that implement each function name.
    program.types.each do |t|
      t.functions.each do |f|
        next if f.has_tag?(:hygienic)
        next unless program.reach.reached_func?(f)
        
        observe_func(t, f)
      end
    end
    
    # Assign colors to function names, then clean up all other memory.
    assign_colors
    cleanup
  end
  
  # Public: return the color id for the given function,
  # assuming that this pass has already been run on the program.
  def [](f); color_of(f) end
  def color_of(f : Program::Function) : Color
    @color_by_func_name[name_of(f)]
  end
  
  # Return the next color id to assign when we need a previously unused color.
  private def next_color
    color = @next_color
    @next_color += 1
    color
  end
  
  # Return the deterministic name to use for the given function.
  # It need not be globally unique - just unique within its owning type.
  private def name_of(f)
    f.ident.value # TODO: use a mangled name?
  end
  
  # Take notice of the given function, under the given type.
  private def observe_func(t, f)
    set = @types_by_func_name[name_of(f)] ||= Set(Program::Type).new
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
