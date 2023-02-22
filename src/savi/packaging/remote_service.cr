require "file_utils"

module Savi::Packaging::RemoteService
  def self.find_location_for(ctx, dep_name : String) : String?
    GitHub.find_location_for(ctx, dep_name)
  end

  GITHUB_LIBRARY_INDEX_REPO_BASE_URL =
    "https://raw.githubusercontent.com/savi-lang/library-index"

  def self.update_all(ctx, deps : Array(Dependency), into_dirname : String)
    deps.group_by(&.location_scheme).each { |scheme, scheme_deps|
      case scheme
      when "relative"
        # do nothing - expect the directory to be user-provided
      when "github"
        GitHub.update_all(ctx, scheme_deps, into_dirname)
      else
        scheme_deps.each { |dep|
          if scheme.empty?
            ctx.error_at dep.name, "This dependency couldn't be resolved", [
              {Source::Pos.none, "please use a `:from` declaration such as" +
                                 " `:from \"github:username/example\"`"},
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

    PROCESS_CONCURRENCY            = 1
    COMMAND_GIT_REMOTE_SORTED_TAGS =
      %w{git -c versionsort.suffix=- ls-remote --tags --sort=-v:refname}

    def self.latest_version_of_each(ctx, deps : Array(Dependency)) : Array(String)
      versions = [] of String

      # Start a parallel sub-process for each repo we want to list versions of,
      # but no more than `PROCESS_CONCURRENCY` processes concurrently.
      deps.each_slice(PROCESS_CONCURRENCY) { |group|
        list = group.map { |dep|
          repo_name = dep.location_without_scheme
          output = IO::Memory.new
          args = COMMAND_GIT_REMOTE_SORTED_TAGS.dup
          args << "https://github.com/#{repo_name}.git"
          process = Process.new("/usr/bin/env", args, output: output)
          {dep, process, output}
        }

        # Wait for each of the parallel sub-processes to finish, and determine
        # the latest tag that is acceptable from the list of available tags.
        list.each { |dep, process, output|
          # Wait for the process to finish and check its status code for success.
          status = process.wait
          if !status.success?
            ctx.error_at dep.name,
              "Failed to list remote versions for this dependency", [
              {dep.location_nodes.first.pos,
               "please ensure this location is correct, or try again later"},
            ]
            next
          end

          # Get tag names from the sorted output of the process.
          sorted_tags = output.to_s.each_line.map(&.split("refs/tags/", 2).last).to_a
          if sorted_tags.empty?
            hints = [
              {dep.location_nodes.first.pos,
               "this repository had no commits tagged in it"},
            ]
            dep.version.try { |version_node|
              hints << {version_node.pos,
                        "please tag a commit with a version tag starting with " +
                        version_node.value.inspect}
            }

            ctx.error_at dep.name,
              "No remote versions were found for this dependency", hints
            next
          end

          # Find the first version in the sorted tags that meets the requirement.
          version = sorted_tags.find { |tag| dep.accepts_version?(tag) }
          if !version
            hints = [
              {dep.location_nodes.first.pos,
               "this repository had no matching commit tags in it"},
            ]
            dep.version.try { |version_node|
              hints << {version_node.pos,
                        "please tag a commit with a version tag starting with " +
                        version_node.value.inspect}
            }
            sorted_tags.each { |tag|
              hints << {Source::Pos.none, "this tag was found, but didn't match: #{tag}"}
            }

            ctx.error_at dep.name,
              "No matching remote version was found for this dependency", hints
            next
          end

          versions << version
        }
      }
      versions
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
      STDERR.puts "Downloading new library versions from GitHub..."

      # Spawn the sub-processes to shallow-clone the specified versions,
      # but no more than PROCESS_CONCURRENCY concurrently.
      download_list.each_slice(PROCESS_CONCURRENCY) { |group|
        process_list = group.map { |dep, version|
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
               "please ensure this location is correct, or try again later"},
            ]
            next
          end

          STDERR.puts "Downloaded #{dep.name.value} #{version}"
        }
      }
    end

    COMMAND_GIT_CLONE_MINIMAL =
      %w{git clone --depth=1 --bare --filter=blob:none}

    @@location_cache = {} of String => String

    def self.find_location_for(ctx, dep_name : String) : String?
      # If we already have a cached location in this same compiler invocation,
      # we should not look up the location again. We may run this several
      # times in a loop when iterating through auto-fix cycles.
      cached_location = @@location_cache[dep_name]?
      return cached_location if cached_location

      STDERR.puts "Finding a remote location for the #{dep_name} library..."

      # Choose a random temporary directory name.
      tmp_dir = File.join(Dir.tempdir, "savi-library-index-#{Random::Secure.hex}")

      # Clone the git repo minimally into the temporary directory, without
      # actually downloading the full history or the full set of files.
      # In the next step we'll get only the one file we care about.
      clone_args = COMMAND_GIT_CLONE_MINIMAL.dup
      clone_args << "https://github.com/savi-lang/library-index.git"
      clone_args << tmp_dir
      clone_process = Process.new("/usr/bin/env", clone_args)
      if !clone_process.wait.success?
        ctx.error_at Source::Pos.none, "Failed to reach the remote library index", [
          {Source::Pos.none, "please check your internet connectivity, or try again later"},
        ]
        return
      end

      # Use the bare repo to show the one file we care about - the text file
      # that indicates the known location(s) of the given library name.
      show_output = IO::Memory.new
      show_args = ["git"]
      show_args << "--git-dir=#{tmp_dir}"
      show_args << "show"
      show_args << "HEAD:by-lib-name/#{dep_name}.txt"
      show_process = Process.new("/usr/bin/env", show_args, output: show_output)
      if !show_process.wait.success?
        ctx.error_at Source::Pos.none, "The library #{dep_name.inspect} isn't known in the remote library index", [
          {Source::Pos.none, "please check your spelling, or specify an " + \
            "explicit location using an option like the following:"},
          {Source::Pos.none, "--from github:some-user/some-repo"},
        ]
        return
      end

      # Read the location list from the file.
      # If there is just one location name, use it (and save it in the cache).
      # Otherwise print an error asking for an explicit location.
      locations = show_output.to_s.each_line.to_a.reject(&.empty?)
      case locations.size
      when 1
        location = locations.first
        STDERR.puts "Found a known location: #{location}"
        @@location_cache[dep_name] = location
        return location
      when 0
        ctx.error_at Source::Pos.none, "The library #{dep_name.inspect} isn't known in the remote library index", [
          {Source::Pos.none, "please check your spelling, or specify an " + \
            "explicit location using an option like the following:"},
          {Source::Pos.none, "--from github:some-user/some-repo"},
        ]
      else
        ctx.error_at Source::Pos.none, "The library #{dep_name.inspect} has multiple known locations", [
          {Source::Pos.none, "please use one of the following explicit locations:"},
        ] + locations.map { |location|
          {Source::Pos.none, "--from #{location}"}
        }
      end
    ensure
      # Clean up after ourselves.
      # Ensure that the temporary directory gets deleted, if it exists.
      FileUtils.rm_rf(tmp_dir) if tmp_dir
    end
  end
end
