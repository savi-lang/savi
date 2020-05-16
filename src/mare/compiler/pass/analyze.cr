abstract class Mare::Compiler::Pass::Analyze(TypeAnalysis, FuncAnalysis)
  def initialize
    @for_type = {} of Program::Type::Link => TypeAnalysis
    @for_func = {} of Program::Function::Link => FuncAnalysis
  end

  def [](t_link : Program::Type::Link); @for_type[t_link] end
  def []?(t_link : Program::Type::Link); @for_type[t_link]? end
  def [](f_link : Program::Function::Link); @for_func[f_link] end
  def []?(f_link : Program::Function::Link); @for_func[f_link]? end

  def run(ctx : Context, library : Program::Library)
    # Run for each of the types in the library.
    library.types.each do |t|
      run_for_type(ctx, t, t.make_link(library))
    end
  end

  def run_for_type(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  )
    # If we already have an analysis completed for the type, return it.
    already_analysis = @for_func[t_link]?
    return already_analysis if already_analysis

    # Generate the analysis for the type and save it to our map.
    @for_type[t_link] = t_analysis = analyze_type(ctx, t, t_link)

    # Run for each of the functions in the type.
    t.functions.each do |f|
      run_for_func(ctx, f, f.make_link(t_link), t_analysis)
    end
  end

  def run_for_func(
    ctx : Context,
    f : Program::Function,
    f_link : Program::Function::Link,
    optional_t_analysis : TypeAnalysis? = nil
  )
    # If we already have an analysis completed for the function, return it.
    already_analysis = @for_func[f_link]?
    return already_analysis if already_analysis

    # If the caller didn't supply the analysis for the type, we look it up.
    t_analysis = optional_t_analysis || @for_type[f_link.type]

    # Generate the analysis for the function and save it to our map.
    @for_func[f_link] = analyze_func(ctx, f, f_link, t_analysis)
  end

  # Required hook to make the pass create an analysis for the given type.
  abstract def analyze_type(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  ) : TypeAnalysis

  # Required hook to make the pass create an analysis for the given function.
  abstract def analyze_func(
    ctx : Context,
    f : Program::Function,
    f_link : Program::Function::Link,
    t_analysis : TypeAnalysis
  ) : FuncAnalysis
end
