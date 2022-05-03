##
# The purpose of the Namespace pass is to determine which type names are visible
# from which source files, and to raise an appropriate error in the event that
# two types visible from the same source file have the same identifier.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the source package level.
#
class Savi::Compiler::Namespace
  alias Analysis = Hash(String,
    Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
  )

  def initialize
    @packages_by_name = Hash(String, Program::Package::Link).new
    @types_by_package = Hash(Program::Package::Link, Analysis).new
    @accessible_types_by_package = Hash(Program::Package::Link, Analysis).new
  end

  def main_type!(ctx); main_type?(ctx).not_nil! end
  def main_type?(ctx): Program::Type::Link?
    @types_by_package[ctx.root_package_link]["Main"]?.as(Program::Type::Link?)
  end

  def run(ctx)
    # Take note of all packages and types within them.
    ctx.program.packages.each do |package|
      @packages_by_name[package.name] ||= package.make_link
      @types_by_package[package.make_link] = Analysis.new
      @accessible_types_by_package[package.make_link] = Analysis.new

      package.types.each do |t|
        check_valid_name(ctx, t)
        check_conflicting_functions(ctx, t, t.make_link(package))
        add_type_to_package(ctx, t, package)
        add_type_to_accessible_types(t, package)
      end
      package.aliases.each do |t|
        check_valid_name(ctx, t)
        add_type_to_package(ctx, t, package)
        add_type_to_accessible_types(t, package)
      end
      package.enum_members.each do |t|
        check_valid_name(ctx, t)
        add_type_to_package(ctx, t, package)
        add_type_to_accessible_types(t, package)
      end
    end

    # Every package implicitly has access to all core Savi types.
    @accessible_types_by_package.each do |package_link, analysis|
      add_core_savi_types_to_accessible_types(ctx, package_link, analysis)
    end

    # Every package has access to types loaded via its package manifest.
    unless ctx.options.skip_manifest
      ctx.program.packages.each { |package|
        manifest =
          ctx.manifests.manifests_by_name[package.source_package.name]? || \
          ctx.manifests.root.not_nil!

        add_dependencies_to_accessible_types(ctx, package, manifest)
      }
    end
  end

  # TODO: Can this be less hacky? It feels wrong to alter this state later.
  def add_lambda_type_later(ctx : Context, new_type : Program::Type, package : Program::Package)
    check_conflicting_functions(ctx, new_type, new_type.make_link(package))
    add_type_to_package(ctx, new_type, package)
    add_type_to_accessible_types(new_type, package)
  end

  # When given a package link, return the set of types accessible within it.
  def [](package : Program::Package::Link) : Analysis
    @accessible_types_by_package[package]
  end
  def []?(package : Program::Package::Link) : Analysis?
    @accessible_types_by_package[package]?
  end

  # When given a source package, return the set of types accessible within it.
  def [](source_package : Source::Package) : Analysis
    @accessible_types_by_package[Program::Package.link(source_package)]
  end
  def []?(source_package : Source::Package) : Analysis?
    @accessible_types_by_package[Program::Package.link(source_package)]?
  end

  def core_savi_package_link
    @packages_by_name["Savi"]
  end

  # When given a String name, try to find the type in the core_savi package.
  # This is a way to resolve a builtin type by name without more context.
  def core_savi_type(ctx, name : String) : Program::Type::Link
    @types_by_package[core_savi_package_link][name].as(Program::Type::Link)
  end

  # TODO: Remove this method?
  # This is only for use in testing.
  def find_func!(ctx, source, type_name, func_name)
    self[source.package][type_name].as(Program::Type::Link).resolve(ctx).find_func!(func_name)
  end

  private def check_valid_name(ctx, t)
    if t.ident.value.includes?("!")
      ctx.error_at t.ident, "A type name cannot contain an exclamation point"
    end
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

    types = @types_by_package[package.make_link]

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

  private def add_type_to_accessible_types(new_type, package)
    name = new_type.ident.value

    types = @accessible_types_by_package[package.make_link]

    types[name] = new_type.make_link(package)
  end

  private def add_core_savi_types_to_accessible_types(ctx, package_link, analysis)
    return if package_link.path == ctx.compiler.source_service.core_savi_package_path

    @types_by_package[core_savi_package_link].each do |name, new_type_link|
      new_type = new_type_link.resolve(ctx)
      next if new_type.ident.value.starts_with?("_") # skip private types

      already_type = analysis[name]?.try(&.resolve(ctx))
      if already_type
        ctx.error_at already_type.ident.pos,
          "This type's name conflicts with a mandatory built-in type", [
            {new_type.ident.pos, "the built-in type is defined here"},
          ]
        next
      end

      analysis[name] = new_type_link
    end
  end

  private def add_dependencies_to_accessible_types(ctx, package, manifest)
    analysis = @accessible_types_by_package[package.make_link]

    manifest.dependencies.each { |dep|
      next if dep.transitive?

      dep_manifest = ctx.manifests.manifests_by_name[dep.name.value]
      dep_package = @packages_by_name[dep.name.value]

      @types_by_package[dep_package].each { |name, new_type_link|
        new_type = new_type_link.resolve(ctx)
        next if new_type.ident.value.starts_with?("_") # skip private types

        already_type = analysis[name]?.try(&.resolve(ctx))
        if already_type
          ctx.error_at already_type.ident.pos,
            "This type's name conflicts with a type defined in another package", [
              {new_type.ident.pos, "the imported type is defined here"},
            ]
          next
        end

        analysis[name] = new_type_link
      }
    }
  end
end
