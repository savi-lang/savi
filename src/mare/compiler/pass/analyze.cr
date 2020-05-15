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
    library.types.each do |t|
      run_for_type(ctx, t, t.make_link(library))
    end
  end

  def run_for_type(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  )
    @for_type[t_link] = t_analysis = analyze_type(ctx, t, t_link)

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
    t_analysis = optional_t_analysis || @for_type[f_link.type]

    @for_func[f_link] = f_analysis = analyze_func(ctx, f, f_link, t_analysis)
  end

  abstract def analyze_type(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  ) : TypeAnalysis

  abstract def analyze_func(
    ctx : Context,
    f : Program::Function,
    f_link : Program::Function::Link,
    t_analysis : TypeAnalysis
  ) : FuncAnalysis
end
