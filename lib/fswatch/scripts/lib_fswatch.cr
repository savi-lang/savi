@[Include(
  "/usr/local/Cellar/fswatch/1.15.0/include/libfswatch/c/libfswatch.h",
  "/usr/local/Cellar/fswatch/1.15.0/include/libfswatch/c/libfswatch_types.h",
  prefix: %w(FSW_ fsw_))]
@[Link("fswatch", pkg_config: "libfswatch")]
lib LibFSWatch
end
