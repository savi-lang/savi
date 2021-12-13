require "file"

# Patch File to add a new static function to construct a relative path.
#
# It will add as many ".." segments as it needs to find a common root,
# then remove the common root.
#
# We use this for showing source paths in error messages in ways that
# are not dependent on where on the filesystem the code is checked out,
# but still showing a fully navigable path to that given filename.

class File
  def self.make_relative_path(from_path : String, to_path : String)
    up_levels = 0

    # We can't make one path relative to another unless they are both
    # "normal" paths on a real file system (as opposed to things like
    # an "(eval)" string or "(compiler-spec)" pseudo-source).
    return to_path \
      unless from_path.starts_with?("/") && to_path.starts_with?("/")

    loop {
      # Try to produce a relative path result assuming that the to_path
      # is nested directly some number of layers within the current from_path.
      result_path = to_path.sub(from_path, ".")

      # If we've reached a relative path from the current from_path,
      # then we'll break out of the loop with an early return,
      # Returning the result path, possibly with a number of ".." segments
      # with each of those indicating a time we had to move up one level
      # before we reached a common prefix.
      # If there are any ".." segments, we strip out the unneeded "." segment.
      if result_path.starts_with?("./")
        return File.join(
          up_levels.times.map { ".." }.to_a + [
            result_path.sub(up_levels > 0 ? "./" : "", "")
          ]
        )
      end

      # Move our "from_path" up one level, and count each time we do this.
      # Then continue the loop and try to reach a relative path from there.
      from_path = File.expand_path("..", from_path)
      up_levels += 1

      raise "This is probably an infinite loop" if up_levels > 10_000
    }
  end
end
