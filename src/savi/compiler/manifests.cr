##
# The purpose of the Manifests pass is to analyze any package manifests found
# in the source directory, select a root manifest, and resolve the manifest
# objects for all of the dependencies referenced in the root manifest.
#
# This pass mutates the Program topology (particularly the manifests).
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the program level.
#
class Savi::Compiler::Manifests
  getter root : Packaging::Manifest? = nil
  getter manifests_by_name = {} of String => Packaging::Manifest

  def initialize
  end

  def run(ctx)
    return if ctx.options.skip_manifest

    # Select the appropriate root manifest (or fail to do so).
    @root = manifest = select_root_manifest(ctx)
    return unless manifest

    # If some manifests copy from other manifests, bring the data from those
    # copied manifests into the destination manifests, to fully extrapolate.
    ctx.program.manifests.each { |m|
      execute_copies_for_manifest(ctx, ctx.program.manifests, m)
    }

    # For each name provided by the root manifest, track it.
    manifest.provides_names.each { |provides_name|
      @manifests_by_name[provides_name.value] = manifest
    }

    # Add a dependency if it was requested that we do so.
    maybe_deps_add(ctx, manifest)

    # Update some or all dependencies, if it was requested that we do so.
    maybe_deps_update(ctx, manifest)

    # Resolve all the dependency manifests.
    manifest.dependencies.each { |dep|
      compile_and_resolve_dep_manifest(ctx, dep)
    }

    # Prove that all transitive dependencies are accounted for.
    manifest.dependencies.each { |dep|
      @manifests_by_name[dep.name.value]?.try { |dep_manifest|
        check_transitive_deps(ctx, manifest, dep, dep_manifest)
      }
    }

    basic_manifest_checks(ctx)
  end

  private def basic_manifest_checks(ctx)
    ctx.program.manifests.each { |manifest|
      if manifest.sources_paths.empty?
        ctx.error_at manifest.name,
          "This manifest has no `:sources` declaration; " \
          "please add at least one to specify where to find source files for it"
        next
      end
    }
  end

  private def select_root_manifest(ctx) : Packaging::Manifest?
    # There must be at least one manifest.
    manifests = ctx.program.manifests
    if manifests.empty?
      ctx.error_at Source::Pos.none,
        "No manifests found in the 'manifest.savi' files in this directory"
      return
    end

    # No two manifests can have the same name.
    return if !check_manifest_names(ctx, manifests)

    # If the user gave a specific manifest name, handle it here.
    manifest_name = ctx.options.manifest_name
    return get_specific_manifest(ctx, manifests, manifest_name) if manifest_name

    # If there is exactly one manifest in all, return it.
    return manifests.first if manifests.size == 1

    # If there is exactly one main manifest, return it.
    mains = manifests.select(&.is_main?)
    return mains.first if mains.size == 1

    # If there is more than one main manifest, complain.
    if mains.size > 1
      ctx.error_at Source::Pos.none,
        "There can't be more than one main manifest in this directory; " \
        "please mark some of these as `:manifest lib` or `:manifest bin`",
        mains.map { |m| {m.name.pos, "this is a main manifest"} }
      return
    end

    # If there is exactly one lib manifest, return it.
    libs = manifests.select(&.is_lib?)
    return libs.first if libs.size == 1

    # We have no more ways to select an appropriate root manifest; complain.
    ctx.error_at Source::Pos.none,
      "There is more than one manifest and it isn't clear which to use; " \
      "please specify one explicitly by name",
      manifests.map { |m| {m.name.pos, "this is an available manifest"} }
    nil
  end

  private def compile_and_resolve_dep_manifest(ctx, dep : Packaging::Dependency)
    manifests = ctx.program.manifests
    orig_manifests_size = manifests.size

    # Ensure the dependency has a `:from` declaration (or fail early).
    if dep.location_nodes.empty?
      ctx.error_at dep.name, "This dependency needs a `:from` declaration " +
        "to indicate where to fetch it from"
      # TODO: can we auto-fix here using the same mechanism as `savi add`?
      return
    end

    # Compile all manifests at the path where the dep is to be found.
    dep_path = if dep.is_location_relative_path?
      ctx.compiler.source_service.find_relative_dep(ctx, dep)
    else
      ctx.compiler.source_service.find_latest_in_deps(ctx, dep)
    end
    return unless dep_path
    ctx.compile_manifests_at_path(dep_path)

    # Limit the manifests we look at to just the set of newly added ones.
    manifests = manifests[orig_manifests_size..-1]

    # Ensure manifest names are acceptable (or fail early).
    return if !check_manifest_names(ctx, manifests)

    # Get the manifest specified by the dep name (or fail to do so).
    manifest = get_specific_manifest(ctx, manifests, dep.name)
    return unless manifest

    # The manifest must be a lib package for us to use it as a dependency.
    unless manifest.is_lib?
      ctx.error_at dep.name,
        "This needs to be a lib package to use it as a dependency", [
          {manifest.name.pos, "but the manifest found here is not"},
          {manifest.kind.pos, "it is a `#{manifest.kind.value}` package"},
        ]
      return
    end

    # If we've gotten to this point, we're ready to store the manifest by name.
    @manifests_by_name[dep.name.value] = manifest

    # We also store it by each of the names that it is said to provide.
    manifest.provides_names.each { |provides_name|
      @manifests_by_name[provides_name.value] = manifest
    }
  end

  private def check_manifest_names(ctx, manifests)
    manifests.each { |manifest|
      name = manifest.name
      next unless name.value == "Savi" || name.value.starts_with?("Savi.")

      ctx.error_at name, "This name is reserved for core Savi packages"
    }

    names = manifests.map(&.name.value)
    return true if names.uniq.size == names.size

    manifests.group_by(&.name.value).each { |name, dups|
      last = dups.pop
      next unless dups.any?

      ctx.error_at last.name, "This manifest needs a unique name",
        dups.map { |other| {other.name.pos, "a conflicting one is here"} }
    }
    return false
  end

  private def get_specific_manifest(ctx, manifests, manifest_name)
    name_value = manifest_name.is_a?(String) \
      ? manifest_name \
      : manifest_name.value

    # Find the manifest with that name and return that one.
    manifest = ctx.program.manifests.find(&.name.value.==(name_value))
    return manifest if manifest

    name_pos = manifest_name.is_a?(String) \
      ? Source::Pos.none \
      : manifest_name.pos

    # If we didn't find it, complain.
    ctx.error_at name_pos,
      "Failed to find a manifest with the specified name `#{name_value}`",
      manifests.map { |m| {m.name.pos, "this name doesn't match"} }
    nil
  end

  private def execute_copies_for_manifest(
    ctx,
    manifests,
    to_manifest,
    from_manifest_in = nil,
    seen_names = [] of AST::Identifier
  )
    from_manifest = from_manifest_in || to_manifest
    from_manifest.copies_names.each { |copies_name|
      # We don't allow a chain of copies declaration to be self-recursive.
      if seen_names.any?(&.value.==(copies_name.value))
        ctx.error_at copies_name,
          "A copies declaration cannot be self-recursive",
          seen_names.map { |seen| {seen.pos, "it recursed from here"} }
        next
      end

      # Find the specified manifest in the same directory (or fail and abort).
      next_from_manifest = manifests.find(&.name.value.==(copies_name.value))
      unless next_from_manifest
        # If we failed to find an identical matching name, try to find a
        # similar name, so we can print a more helpful error message.
        similar_name =
          maybe_find_similar_manifest(copies_name.value, manifests).try(&.name)
        if similar_name
          ctx.error_at copies_name,
            "There's no manifest named `#{copies_name.value}` in this directory",
            [{similar_name.pos, "maybe you meant `#{similar_name.value}`"}]
        else
          ctx.error_at copies_name,
            "There's no manifest named `#{copies_name.value}` in this directory"
        end

        # Don't try to do anything else with this `:copies` declaration.
        next
      end

      # Copy provides names, sources paths, and dependencies.
      next_from_manifest.provides_names.reverse_each { |path|
        to_manifest.provides_names.unshift(path)
      }
      next_from_manifest.sources_paths.reverse_each { |pair|
        to_manifest.sources_paths.unshift(pair)
      }
      next_from_manifest.dependencies.reverse_each { |path|
        to_manifest.dependencies.unshift(path)
      }

      # Recursively handle copies from within the found manifest.
      execute_copies_for_manifest(
        ctx,
        manifests,
        to_manifest,
        next_from_manifest,
        seen_names + [copies_name],
      )
    }
  end

  private def maybe_find_similar_manifest(name, manifests)
    finder = Levenshtein::Finder.new(name)
    manifests.each { |f| finder.test(f.name.value) }
    finder.best_match.try { |other_name|
      manifests.find(&.name.value.==(other_name))
    }
  end

  private def maybe_deps_add(ctx, manifest)
    deps_add = ctx.options.deps_add
    return unless deps_add

    # If no explicit fetch location was given by the user, try to find one.
    # If we fail, return early, making the assumption that the RemoteService
    # abstraction logged an appropriate error into the ctx.
    deps_add_location = ctx.options.deps_add_location
    deps_add_location ||= Packaging::RemoteService.find_location_for(ctx, deps_add)
    return unless deps_add_location

    # If we already have an existing dependency that matches the name and
    # location, it doesn't need to be added as a new dependency.
    existing_dependency = manifest.dependencies.find { |dep|
      dep.name.value == deps_add &&
      dep.location_nodes.any?(&.value.==(deps_add_location))
    }
    if existing_dependency
      # If the existing dependency is transitive, we'll issue a "fix error"
      # request to mark it as no longer transitive in its declaration
      dep = existing_dependency
      if dep.transitive?
        ctx.error_at dep.name, "This dependency is no longer transitive",
          [] of {Source::Pos, String},
          [{dep.ast.terms[0].pos.from_start_until_start_of(dep.ast.terms[1].pos), ""}]
      end

      # Then we return - nothing left to do to add the dependency.
      return
    end

    # Otherwise, we need to add it as a new dependency, via a "fix error".
    fix_lines = ["\n"]
    fix_lines << "  :dependency #{deps_add}"
    fix_lines << "    :from #{deps_add_location.inspect}"
    ctx.error_at manifest.name, "This manifest needs a new dependency",
      [] of {Source::Pos, String},
      [{manifest.append_pos, fix_lines.join("\n")}]
  end

  private def maybe_deps_update(ctx, root_manifest)
    deps_update = ctx.options.deps_update
    return unless deps_update

    # If the user named a specific manifest, we'll only update for that one.
    # Otherwise we'll update deps for all manifests.
    selected_manifests =
      ctx.options.manifest_name ? [root_manifest] : ctx.program.manifests

    # Determine which dependencies should be updated.
    deps_to_update = Set(Packaging::Dependency).new
    selected_manifests.each { |manifest|
      fetchable_deps = manifest.dependencies.select(&.location_nodes.any?)
      if deps_update.empty?
        # If no explicit dependency was specified, then we'll update everything
        # that is fetchable (that has a known location to fetch from).
        fetchable_deps.each { |dep| deps_to_update.add(dep) }
      else
        # If an explicit dependency was specified to update, then we'll only
        # update it and anything that it (directly or transitively) depends on.
        fetchable_deps.each { |dep|
          deps_to_update.add(dep) if dep.name.value == deps_update
        }
        previous_size = 0
        while deps_to_update.size > previous_size
          previous_size = deps_to_update.size
          deps_to_update.to_a.each { |dep|
            fetchable_deps.each { |dep_dep|
              deps_to_update.add(dep_dep) \
                if dep.depends_on_nodes.any?(&.value.==(dep_dep.name.value))
            }
          }
        end
      end
    }

    # Update the specified dependencies.
    Packaging::RemoteService.update_all(ctx, deps_to_update.to_a, root_manifest.deps_path)
  end

  private def check_transitive_deps(ctx, manifest, dep, dep_manifest)
    dep_manifest.dependencies.each { |dep_dep|
      # Check that the transitive dependency has been loaded.
      if !manifest.dependencies.any?(&.name.value.==(dep_dep.name.value))
        can_fix = dep_dep.location_nodes.any?
        fix_lines = ["\n"]
        fix_lines << "  :transitive dependency #{dep_dep.name.value} #{dep_dep.version.try(&.value)}"
        dep_dep.location_nodes.each { |location_node|
          fix_lines << "    :from #{location_node.value.inspect}"
        }

        ctx.error_at manifest.name,
          "A transitive dependency is missing from this manifest", [
            {dep_dep.name.pos, "this transitive dependency needs to be added"},
            {dep.name.pos, "it is required by this existing dependency"},
          ], can_fix ? [
            {manifest.append_pos, fix_lines.join("\n")}
          ] : nil
      end

      # Check that the transitive dependency is marked on the via dependency.
      if !dep.depends_on_nodes.any?(&.value.==(dep_dep.name.value))
        ctx.error_at dep.name,
          "A `:depends on` declaration is missing from this dependency", [
            {dep_dep.name.pos, "this transitive dependency needs to be added"},
          ], [
            {dep.append_pos, "\n    :depends on #{dep_dep.name.value}"}
          ]
      end
    }

    # Check that there aren't any unnecessary `:depends on` declarations.
    dep.depends_on_nodes.each { |depends_on_name|
      if !dep_manifest.dependencies.any?(&.name.value.==(depends_on_name.value))
        ctx.error_at depends_on_name,
          "This `:depends on` declaration is not necessary", [
            {dep_manifest.name.pos,
              "this manifest does not include it as a dependency"},
          ], [
            {depends_on_name.pos.whole_containing_lines_as_pos, ""}
          ]
      end
    }
  end
end
