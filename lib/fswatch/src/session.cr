module FSWatch
  class Session
    @on_change : Event ->

    @portal : ThreadPortal(Slice(Event))

    @_running : Bool

    def initialize(monitor_type : MonitorType = MonitorType::SystemDefault)
      @handle = LibFSWatch.init_session(monitor_type)
      @on_change = ->(e : Event) {}
      @portal = ThreadPortal(Slice(Event)).new
      @_running = false
      setup_handle_callback
    end

    def to_unsafe
      @handle
    end

    def finalize
      LibFSWatch.destroy_session(@handle)
    end

    # :nodoc:
    protected def portal
      @portal
    end

    # :nodoc:
    protected def _running : Bool
      @_running
    end

    # :nodoc:
    protected def setup_handle_callback
      status = LibFSWatch.set_callback(@handle, ->(events, event_num, data) {
        session = Box(Session).unbox(data)
        if session._running
          # fswatch is calling the callback even after the stop_monitoring is called
          session.portal.send events.to_slice(event_num).map { |ev|
            Event.new(
              path: String.new(ev.path),
              event_flag: ev.flags.value
            )
          }
        end
      }, Box.box(self))

      check status, "Unable to set_callback"

      spawn do
        loop do
          @portal.receive.each do |ev|
            @on_change.call(ev)
          end
        end
      end
    end

    def add_path(path : String | Path)
      check LibFSWatch.add_path(@handle, path.to_s), "Unable to add_path"
    end

    def on_change(&on_change : Event ->)
      @on_change = on_change
    end

    def start_monitor
      Thread.new do
        check LibFSWatch.start_monitor(@handle), "Unable to start_monitor"
      end
      @_running = true
    end

    def stop_monitor
      check LibFSWatch.stop_monitor(@handle), "Unable to stop_monitor"
      @_running = false
    end

    def is_running
      check LibFSWatch.is_running(@handle), "Unable to is_running"
    end

    def latency=(value : Float64)
      check LibFSWatch.set_latency(@handle, value), "Unable to set_latency"
    end

    def recursive=(value : Bool)
      check LibFSWatch.set_recursive(@handle, value), "Unable to set_recursive"
    end

    def directory_only=(value : Bool)
      check LibFSWatch.set_directory_only(@handle, value), "Unable to set_directory_only"
    end

    def follow_symlinks=(value : Bool)
      check LibFSWatch.set_follow_symlinks(@handle, value), "Unable to set_follow_symlinks"
    end

    def add_property(name : String, value : String)
      check LibFSWatch.add_property(@handle, name, value), "Unable to add_property"
    end

    def allow_overflow=(value : Bool)
      check LibFSWatch.set_allow_overflow(@handle, value), "Unable to set_allow_overflow"
    end

    def add_event_type_filter(event_type : EventTypeFilter)
      etv = LibFSWatch::EventTypeFilter.new
      etv.flag = event_type.flag
      check LibFSWatch.add_event_type_filter(@handle, etv), "Unable to add_event_type_filter"
    end

    def add_filter(monitor_filter : MonitorFilter)
      cmf = LibFSWatch::CmonitorFilter.new
      cmf.text = monitor_filter.text.to_unsafe
      cmf.type = monitor_filter.type
      cmf.case_sensitive = monitor_filter.case_sensitive
      cmf.extended = monitor_filter.extended
      check LibFSWatch.add_filter(@handle, cmf), "Unable to add_filter"
    end

    private def check(status, message)
      raise Error.new(message) unless status == LibFSWatch::OK
    end

    def self.build(*,
                   latency : Float64? = nil,
                   recursive : Bool? = nil,
                   directory_only : Bool? = nil,
                   follow_symlinks : Bool? = nil,
                   allow_overflow : Bool? = nil,
                   properties : Hash(String, String)? = nil,
                   event_type_filters : Array(EventTypeFilter)? = nil,
                   filters : Array(MonitorFilter)? = nil)
      session = FSWatch::Session.new
      session.latency = latency unless latency.nil?
      session.recursive = recursive unless recursive.nil?
      session.directory_only = directory_only unless directory_only.nil?
      session.follow_symlinks = follow_symlinks unless follow_symlinks.nil?
      session.allow_overflow = allow_overflow unless allow_overflow.nil?
      if properties
        properties.each { |k, v| session.add_property(k, v) }
      end
      if event_type_filters
        event_type_filters.each { |etv| session.add_event_type_filter(etv) }
      end
      if filters
        filters.each { |f| session.filters(etv) }
      end

      session
    end
  end
end
