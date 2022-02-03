require "./lib_fswatch"
require "./event"
require "./monitor"
require "./thread_portal"
require "./session"

module FSWatch
  VERSION = "0.1.0"

  class Error < ::Exception
  end

  def self.init
    check LibFSWatch.init_library, "Unable to init_library"
  end

  def self.verbose
    LibFSWatch.is_verbose != 0
  end

  def self.verbose=(value : Bool)
    LibFSWatch.set_verbose(value)
    value
  end

  def self.event_flag_by_name(name : String) : EventFlag
    check LibFSWatch.get_event_flag_by_name(name, out flag), "Unable to event_flag_by_name"
    flag
  end

  def self.event_flag_name(flag : EventFlag)
    String.new(LibFSWatch.get_event_flag_name(flag))
  end

  private def self.check(status, message)
    raise Error.new(message) unless status == LibFSWatch::OK
  end

  def self.watch(path : String | Path, *,
                 latency : Float64? = nil,
                 recursive : Bool? = nil,
                 directory_only : Bool? = nil,
                 follow_symlinks : Bool? = nil,
                 allow_overflow : Bool? = nil,
                 properties : Hash(String, String)? = nil,
                 event_type_filters : Array(EventTypeFilter)? = nil,
                 filters : Array(MonitorFilter)? = nil,
                 &block : Event ->)
    session = FSWatch::Session.build(
      latency: latency, recursive: recursive, directory_only: directory_only,
      follow_symlinks: follow_symlinks, allow_overflow: allow_overflow,
      properties: properties, event_type_filters: event_type_filters, filters: filters
    )

    session.on_change(&block)
    session.add_path path
    session.start_monitor
  end
end

FSWatch.init
