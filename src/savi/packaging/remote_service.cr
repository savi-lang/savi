module Savi::Packaging::RemoteService
  def self.update_all(ctx, deps : Array(Dependency), into_dirname : String)
    deps.group_by(&.location_scheme).each { |scheme, scheme_deps|
      case scheme
      when "github"
        GitHub.update_all(ctx, scheme_deps, into_dirname)
      else
        scheme_deps.each { |dep|
          if scheme.empty?
            ctx.error_at dep.name, "This dependency couldn't be resolved", [
              {Source::Pos.none, "please use a `:from` declaration such as" +
                " `:from \"github:username/example\"`"}
            ]
          else
            ctx.error_at dep.name, "This dependency couldn't be resolved", [
              {dep.location_nodes.first.pos,
                "the #{scheme.inspect} scheme is not recognized"},
            ]
          end
        }
      end
    }
  end

  module GitHub
    def self.update_all(ctx, deps : Array(Dependency), into_dirname : String)
      versions = latest_version_of_each(ctx, deps)
      fetch_specified_versions_of_each(ctx, deps, versions, into_dirname)
    end

    COMMAND_GIT_REMOTE_SORTED_TAGS =
      %w{git -c versionsort.suffix=- ls-remote --tags --sort=-v:refname}

    def self.latest_version_of_each(ctx, deps : Array(Dependency))
      # Start a parallel sub-process for each repo we want to list versions of.
      list = deps.map { |dep|
        repo_name = dep.location_without_scheme
        output = IO::Memory.new
        args = COMMAND_GIT_REMOTE_SORTED_TAGS.dup
        args << "git@github.com:#{repo_name}.git"
        process = Process.new("/usr/bin/env", args, output: output)
        {dep, process, output}
      }

      # Wait for each of the parallel sub-processes to finish, and determine
      # the latest tag that is acceptable from the list of available tags.
      list.map { |dep, process, output|
        # Wait for the process to finish and check its status code for success.
        status = process.wait
        if !status.success?
          ctx.error_at dep.name,
            "Failed to list remote versions for this dependency", [
              {dep.location_nodes.first.pos,
                "please ensure this location is correct, or try again later"}
            ]
          next
        end

        # Get tag names from the sorted output of the process.
        sorted_tags = output.to_s.each_line.map(&.split("refs/tags/", 2).last).to_a
        if sorted_tags.empty?
          ctx.error_at dep.name,
            "No remote versions were found for this dependency", [
              {dep.location_nodes.first.pos,
                "this repository had no commits tagged in it"},
              {dep.version.pos,
                "please tag a commit with a version tag starting with " +
                  dep.version.value.inspect},
            ]
          next
        end

        # Find the first version in the sorted tags that meets the requirement.
        version = sorted_tags.find { |tag| dep.accepts_version?(tag) }
        if !version
          ctx.error_at dep.name,
            "No matching remote version was found for this dependency", [
              {dep.location_nodes.first.pos,
                "this repository had no matching commit tags in it"},
              {dep.version.pos,
                "please tag a commit with a version tag starting with " +
                  dep.version.value.inspect},
            ] + sorted_tags.map { |tag|
              {Source::Pos.none, "this tag was found, but didn't match: #{tag}"}
            }.to_a
          next
        end

        version
      }
    end

    def self.fetch_specified_versions_of_each(
      ctx,
      deps : Array(Dependency),
      versions : Array(String?),
      into_dirname : String
    )
      # Filter the list to exclude deps where we failed to get a valid version,
      # or where the subdir for that version already exists in the deps folder.
      download_list = deps.zip(versions).select { |dep, version|
        next unless version

        next if Dir.exists?(File.join(into_dirname, dep.location, version))

        true
      }

      # Fast exit if there's nothing new to be downloaded.
      return if download_list.empty?
      puts "Downloading new package versions from GitHub..."

      # Spawn the sub-processes to shallow-clone the specified versions.
      process_list = download_list.map { |dep, version|
        version = version.not_nil! # this was already proved above
        args = %w{git clone --quiet --depth 1}
        args << "--branch" << version.not_nil!
        args << "https://github.com/#{dep.location_without_scheme}"
        args << File.join(into_dirname, dep.location, version)
        process = Process.new("/usr/bin/env", args)

        {process, dep, version}
      }

      # Wait for the processes to complete and handle failure if encountered.
      process_list.each { |process, dep, version|
        status = process.wait
        if !status.success?
          ctx.error_at dep.name,
            "Failed to clone version #{version} of this dependency", [
              {dep.location_nodes.first.pos,
                "please ensure this location is correct, or try again later"}
            ]
          next
        end

        puts "Downloaded #{dep.name.value} #{version}"
      }
    end
  end
end
