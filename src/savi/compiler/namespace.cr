##
# The purpose of the Namespace pass is to determine which type names are visible
# from which source files, and to raise an appropriate error in the event that
# two types visible from the same source file have the same identifier.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the source and source package level.
#
class Savi::Compiler::Namespace
  struct SourceAnalysis
    protected getter types

    def initialize(@source : Source)
      @types = {} of String => (
        Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link \
      )
    end

    def [](name : String); @types[name]; end
    def []?(name : String); @types[name]?; end
  end

  def initialize
    @types_by_package_name = Hash(String, Hash(String,
      Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
    )).new
    @source_analyses = Hash(Source, SourceAnalysis).new
  end

  def main_type!(ctx); main_type?(ctx).not_nil! end
  def main_type?(ctx): Program::Type::Link?
    @types_by_package_name[ctx.root_package_link.name]["Main"]?.as(Program::Type::Link?)
  end

  def run(ctx)
    # Take note of the package and source file in which each type occurs.
    ctx.program.packages.each do |package|
      package.types.each do |t|
        check_conflicting_functions(ctx, t, t.make_link(package))
        add_type_to_package(ctx, t, package)
        add_type_to_source(t, package)
      end
      package.aliases.each do |t|
        add_type_to_package(ctx, t, package)
        add_type_to_source(t, package)
      end
      package.enum_members.each do |t|
        add_type_to_package(ctx, t, package)
        add_type_to_source(t, package)
      end
    end

    # Every source file implicitly has access to all core Savi types.
    @source_analyses.each do |source, source_analysis|
      add_core_savi_types_to_source(ctx, source, source_analysis)
    end

    # Every source file implicitly has access to all types in the same package.
    ctx.program.packages.each do |package|
      @source_analyses.each do |source, source_analysis|
        next unless source.package == package.source_package

        types_map = @types_by_package_name[package.name]?
        next unless types_map

        source_analysis.types.merge!(types_map)
      end
    end

    # Every source file has access to types loaded via its package manifest.
    unless ctx.options.skip_manifest
      @source_analyses.each { |source, source_analysis|
        manifest = ctx.manifests.manifests_by_name[source.package.name]? || \
          ctx.manifests.root.not_nil!

        add_dependencies_to_source(ctx, source, source_analysis, manifest)
      }
    end
  end

  # TODO: Can this be less hacky? It feels wrong to alter this state later.
  def add_lambda_type_later(ctx : Context, new_type : Program::Type, package : Program::Package)
    check_conflicting_functions(ctx, new_type, new_type.make_link(package))
    add_type_to_package(ctx, new_type, package)
    add_type_to_source(new_type, package)
  end

  # When given a Source, return the set of analysis for that source.
  # TODO: Get rid of other forms of [] here in favor of this one.
  def [](source : Source) : SourceAnalysis
    @source_analyses[source]
  end

  # When given a String name, try to find the type in the core_savi package.
  # This is a way to resolve a builtin type by name without more context.
  def core_savi_type(ctx, name : String) : Program::Type::Link
    @types_by_package_name["Savi"][name].as(Program::Type::Link)
  end

  # TODO: Remove this method?
  # This is only for use in testing.
  def find_func!(ctx, source, type_name, func_name)
    self[source][type_name].as(Program::Type::Link).resolve(ctx).find_func!(func_name)
  end

  private def check_conflicting_functions(ctx, t, t_link : Program::Type::Link)
    # Find any functions that would resolve to the same link - not allowed.
    t.functions.group_by(&.make_link(t_link)).each do |f_link, fs|
      next if fs.size <= 1

      f_first = fs.shift
      ctx.error_at f_first.ident.pos,
        "This name conflicts with others declared in the same type",
        fs.map { |f| {f.ident.pos, "a conflicting declaration is here"} }
    end
  end

  private def add_type_to_package(ctx, new_type, package)
    name = new_type.ident.value

    package_name = package.source_package.name
    return unless package_name

    types = @types_by_package_name[package_name] ||= Hash(String,
      Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
    ).new

    already_type_link = types[name]?
    if already_type_link
      already_type = already_type_link.resolve(ctx)
      ctx.error_at new_type.ident.pos,
        "This type conflicts with another declared type in the same package", [
          {already_type.ident.pos, "the other type with the same name is here"}
        ]
      return
    end

    types[name] = new_type.make_link(package)
  end

  private def add_type_to_source(new_type, package)
    source = new_type.ident.pos.source
    name = new_type.ident.value

    source_analysis = @source_analyses[source] ||= SourceAnalysis.new(source)

    source_analysis.types[name] = new_type.make_link(package)
  end

  private def add_core_savi_types_to_source(ctx, source, source_analysis)
    return if source.package.path == ctx.compiler.source_service.core_savi_package_path

    @types_by_package_name["Savi"].each do |name, new_type_link|
      new_type = new_type_link.resolve(ctx)
      next if new_type.has_tag?(:private)

      already_type = source_analysis.types[name]?.try(&.resolve(ctx))
      if already_type
        ctx.error_at already_type.ident.pos,
          "This type's name conflicts with a mandatory built-in type", [
            {new_type.ident.pos, "the built-in type is defined here"},
          ]
        next
      end

      source_analysis.types[name] = new_type_link
    end
  end

  private def add_dependencies_to_source(ctx, source, source_analysis, manifest)
    manifest.dependencies.each { |dep|
      next if dep.transitive?

      dep_manifest = ctx.manifests.manifests_by_name[dep.name.value]

      @types_by_package_name[dep_manifest.name.value].each { |name, new_type_link|
        new_type = new_type_link.resolve(ctx)
        next if new_type.has_tag?(:private)

        already_type = source_analysis.types[name]?.try(&.resolve(ctx))
        if already_type
          ctx.error_at already_type.ident.pos,
            "This type's name conflicts with a type defined in another package", [
              {new_type.ident.pos, "the imported type is defined here"},
            ]
          next
        end

        source_analysis.types[name] = new_type_link
      }
    }
  end
end
