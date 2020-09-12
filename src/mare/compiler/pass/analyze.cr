abstract class Mare::Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
  getter cache_info_for_alias
  getter cache_info_for_type
  getter cache_info_for_func

  def initialize
    @for_alias = {} of Program::TypeAlias::Link => TypeAliasAnalysis
    @for_type = {} of Program::Type::Link => TypeAnalysis
    @for_func = {} of Program::Function::Link => FuncAnalysis
    @cache_info_for_alias = {} of Program::TypeAlias::Link => UInt64
    @cache_info_for_type = {} of Program::Type::Link => UInt64
    @cache_info_for_func = {} of Program::Function::Link => UInt64
  end

  def [](t_link : Program::TypeAlias::Link); @for_alias[t_link] end
  def []?(t_link : Program::TypeAlias::Link); @for_alias[t_link]? end
  def [](t_link : Program::Type::Link); @for_type[t_link] end
  def []?(t_link : Program::Type::Link); @for_type[t_link]? end
  def [](f_link : Program::Function::Link); @for_func[f_link] end
  def []?(f_link : Program::Function::Link); @for_func[f_link]? end

  def run(ctx : Context, library : Program::Library)
    # Run for each of the type aliases in the library.
    library.aliases.each do |t|
      run_for_type_alias(ctx, t, t.make_link(library))
    end

    # Run for each of the types in the library.
    library.types.each do |t|
      t_analysis = run_for_type(ctx, t, t_link = t.make_link(library))

      # Run for each of the functions in the type.
      t.functions.each do |f|
        run_for_func(ctx, f, f.make_link(t_link), t_analysis)
      end
    end
  end

  def run_for_type_alias(
    ctx : Context,
    t : Program::TypeAlias,
    t_link : Program::TypeAlias::Link
  ) : TypeAliasAnalysis
    # If we already have an analysis completed for the type, return it.
    already_analysis = @for_alias[t_link]?
    return already_analysis if already_analysis

    # Generate the analysis for the type and save it to our map.
    @for_alias[t_link] = analyze_type_alias(ctx, t, t_link)
  end

  def run_for_type(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  ) : TypeAnalysis
    # If we already have an analysis completed for the type, return it.
    already_analysis = @for_type[t_link]?
    return already_analysis if already_analysis

    # Generate the analysis for the type and save it to our map.
    @for_type[t_link] = t_analysis = analyze_type(ctx, t, t_link)
  end

  def run_for_func(
    ctx : Context,
    f : Program::Function,
    f_link : Program::Function::Link,
    optional_t_analysis : TypeAnalysis? = nil
  ) : FuncAnalysis
    # If we already have an analysis completed for the function, return it.
    already_analysis = @for_func[f_link]?
    return already_analysis if already_analysis

    # If the caller didn't supply the analysis for the type, we look it up.
    t_link = f_link.type
    t_analysis = optional_t_analysis || @for_type[t_link]? \
      || run_for_type(ctx, t_link.resolve(ctx), t_link)

    # Generate the analysis for the function and save it to our map.
    @for_func[f_link] = analyze_func(ctx, f, f_link, t_analysis)
  end

  # Optionally, the analyze_type_alias method of the subclass can use this function
  # to cache the analysis from the previous compiler run into this one,
  # based on whether the type alias itself or the list of deps has changed.
  private def maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) : FuncAnalysis
    hashable = {t, deps}
    if prev \
    && (prev_hash = prev.cache_info_for_alias[t_link]?; prev_hash) \
    && (prev_hash == hashable.hash)
      cache_info_for_alias[t_link] = prev_hash
      prev[t_link]
    else
      puts "    RERUN . #{self.class} #{t_link.show}" if prev && ctx.options.print_perf
      cache_info_for_alias[t_link] = hashable.hash
      yield
    end
  end

  # Optionally, the analyze_type method of the subclass can use this function
  # to cache the analysis from the previous compiler run into this one,
  # based on whether the type itself or the list of deps has changed.
  private def maybe_from_type_cache(ctx, prev, t, t_link, deps) : FuncAnalysis
    hashable = {t.head_hash, deps}
    if prev \
    && (prev_hash = prev.cache_info_for_type[t_link]?; prev_hash) \
    && (prev_hash == hashable.hash)
      cache_info_for_type[t_link] = prev_hash
      prev[t_link]
    else
      puts "    RERUN . #{self.class} #{t_link.show}" if prev && ctx.options.print_perf
      cache_info_for_type[t_link] = hashable.hash
      yield
    end
  end

  # Optionally, the analyze_func method of the subclass can use this function
  # to cache the analysis from the previous compiler run into this one,
  # based on whether the function itself or the list of deps has changed.
  private def maybe_from_func_cache(ctx, prev, f, f_link, deps) : FuncAnalysis
    hashable = {f, deps}
    if prev \
    && (prev_hash = prev.cache_info_for_func[f_link]?; prev_hash) \
    && (prev_hash == hashable.hash)
      cache_info_for_func[f_link] = prev_hash
      prev[f_link]
    else
      puts "    RERUN . #{self.class} #{f_link.show}" if prev && ctx.options.print_perf
      cache_info_for_func[f_link] = hashable.hash
      yield
    end
  end

  # Required hook to make the pass create an analysis for the given type alias.
  abstract def analyze_type_alias(
    ctx : Context,
    t : Program::Type,
    t_link : Program::Type::Link
  ) : TypeAnalysis

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
