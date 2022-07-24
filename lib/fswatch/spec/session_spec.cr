require "./spec_helper"

private def wait
  sleep 0.5 # wait so the creation of files does not trigger an event
end

private def _it(description = "assert", options = NamedTuple.new, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus = false,
                &block : FSWatch::Session, Channel(FSWatch::Event), String ->)
  it(description, file, line, end_line, focus: focus) do
    Log.debug { "Starting #{file}:#{line}" }
    with_tempdir do |path|
      wait
      session = FSWatch::Session.build(**options)
      events = Channel(FSWatch::Event).new
      session.on_change do |event|
        Log.debug { event.inspect }
        events.send(event)
      end
      session.add_path path
      block.call(session, events, path)

      no_return { events.receive } # there are no pending events
      session.stop_monitor
    end
  end
end

def on_darwin
  {% if flag?(:darwin) %}
    yield
  {% end %}
end

def on_linux
  {% if flag?(:linux) %}
    yield
  {% end %}
end

describe FSWatch::Session do
  _it "reacts to new files" do |session, events, path|
    session.start_monitor

    File.write(File.join(path, "a_new_file.txt"), "")
    e = with_timeout { events.receive }

    e.path.should eq(File.join(path, "a_new_file.txt"))
    e.created?.should be_truthy
  end

  _it "reacts to updated files" do |session, events, path|
    File.write(File.join(path, "file_to_update.txt"), "foo")
    wait
    session.start_monitor

    File.write(File.join(path, "file_to_update.txt"), "bar", mode: "a")
    e = with_timeout { events.receive }

    e.path.should eq(File.join(path, "file_to_update.txt"))
    on_darwin { e.created?.should be_truthy }
    on_linux { e.platform_specific?.should be_truthy }
  end

  _it "reacts to new deleted files" do |session, events, path|
    File.write(File.join(path, "file_to_update.txt"), "foo")
    wait
    session.start_monitor

    File.delete(File.join(path, "file_to_update.txt"))
    e = with_timeout { events.receive }

    e.path.should eq(File.join(path, "file_to_update.txt"))

    on_darwin { e.created?.should be_truthy } # WARNING: different behaviour
    on_linux { e.removed?.should be_truthy }
  end

  _it "reacts to new directories" do |session, events, path|
    session.start_monitor

    Dir.mkdir(File.join(path, "a_new_dir"))
    e = with_timeout { events.receive }

    on_darwin {
      e.path.should eq(File.join(path, "a_new_dir"))
      e.created?.should be_truthy
    }
    on_linux {
      e.path.should eq(path)
      e.is_dir?.should be_truthy
    }
  end

  _it "reacts to many updated files" do |session, events, path|
    10.times do |i|
      File.write(File.join(path, "file_to_update_#{i}.txt"), "foo")
    end
    wait
    session.start_monitor

    10.times do |i|
      File.write(File.join(path, "file_to_update_#{i}.txt"), "bar", mode: "a")
    end
    10.times do |i|
      e = with_timeout { events.receive }
      File.match?(File.join(path, "file_to_update_*.txt"), e.path).should eq(true)
      on_darwin { e.created?.should be_truthy }
      on_linux { e.platform_specific?.should be_truthy }
    end
  end

  context "when recursive" do
    _it "reacts to new nested files", options: {recursive: true} do |session, events, path|
      Dir.mkdir(File.join(path, "existing_dir"))
      wait
      session.start_monitor

      File.write(File.join(path, "existing_dir", "a_new_file.txt"), "foo")
      e = with_timeout { events.receive }

      on_darwin {
        e.path.should eq(File.join(path, "existing_dir", "a_new_file.txt"))
        e.created?.should be_truthy
      }
      on_linux {
        e.path.should eq(path)
        e.is_dir?.should be_truthy
      }
    end

    _it "reacts to new nested directories", options: {recursive: true} do |session, events, path|
      Dir.mkdir(File.join(path, "existing_dir"))
      wait
      session.start_monitor

      Dir.mkdir(File.join(path, "existing_dir", "a_new_dir"))
      e = with_timeout { events.receive }

      on_darwin {
        e.path.should eq(File.join(path, "existing_dir", "a_new_dir"))
        e.created?.should be_truthy
      }
      on_linux {
        e.path.should eq(path)
        e.is_dir?.should be_truthy
      }
    end
  end

  context "when non-recursive" do
    _it "does not react to new nested files", options: {recursive: false} do |session, events, path|
      Dir.mkdir(File.join(path, "existing_dir"))
      wait
      session.start_monitor

      File.write(File.join(path, "existing_dir", "a_new_file.txt"), "foo")

      on_darwin {
        # On darwin it seems that the monitoring is always recursive
        e = with_timeout { events.receive }
        e.path.should eq(File.join(path, "existing_dir", "a_new_file.txt"))
        e.created?.should be_truthy
      }

      # no assertions: use the implicit no more pending events
    end

    _it "does not react to new nested directories", options: {recursive: false} do |session, events, path|
      Dir.mkdir(File.join(path, "existing_dir"))
      wait
      session.start_monitor

      Dir.mkdir(File.join(path, "existing_dir", "a_new_dir"))

      on_darwin {
        # On darwin it seems that the monitoring is always recursive
        e = with_timeout { events.receive }
        e.path.should eq(File.join(path, "existing_dir", "a_new_dir"))
        e.created?.should be_truthy
      }

      # no assertions: use the implicit no more pending events
    end
  end
end
