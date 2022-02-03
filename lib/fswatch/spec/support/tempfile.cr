require "file_utils"

def with_tempdir
  tempdir = File.join(Dir.tempdir, "spec-#{Random.new.hex(4)}")
  FileUtils.mkdir_p(tempdir)
  tempdir = File.real_path(tempdir)

  begin
    yield tempdir
  ensure
    FileUtils.rm_rf(tempdir) if File.exists?(tempdir)
  end
end
