@[Link("fswatch", pkg_config: "libfswatch")]
lib LibFSWatch
  alias Bool = LibC::Int
  INVALID_HANDLE = -1
  OK             =  0
  alias Session = Void
  @[Flags]
  enum EventFlag
    NoOp              =    0
    PlatformSpecific  =    1
    Created           =    2
    Updated           =    4
    Removed           =    8
    Renamed           =   16
    OwnerModified     =   32
    AttributeModified =   64
    MovedFrom         =  128
    MovedTo           =  256
    IsFile            =  512
    IsDir             = 1024
    IsSymLink         = 2048
    Link              = 4096
    Overflow          = 8192
  end
  fun get_event_flag_by_name = fsw_get_event_flag_by_name(name : LibC::Char*, flag : EventFlag*) : Status
  alias Status = LibC::Int
  fun get_event_flag_name = fsw_get_event_flag_name(flag : EventFlag) : LibC::Char*

  struct Cevent
    path : LibC::Char*
    evt_time : TimeT
    flags : EventFlag*
    flags_num : LibC::UInt
  end

  alias X__DarwinTimeT = LibC::Long
  alias TimeT = X__DarwinTimeT

  struct CmonitorFilter
    text : LibC::Char*
    type : FilterType
    case_sensitive : Bool
    extended : Bool
  end

  enum FilterType
    FilterInclude = 0
    FilterExclude = 1
  end

  struct EventTypeFilter
    flag : EventFlag
  end

  fun init_library = fsw_init_library : Status
  fun init_session = fsw_init_session(type : MonitorType) : Handle
  enum MonitorType
    SystemDefaultMonitorType = 0
    FseventsMonitorType      = 1
    KqueueMonitorType        = 2
    InotifyMonitorType       = 3
    WindowsMonitorType       = 4
    PollMonitorType          = 5
    FenMonitorType           = 6
  end
  type Handle = Void*
  fun add_path = fsw_add_path(handle : Handle, path : LibC::Char*) : Status
  fun add_property = fsw_add_property(handle : Handle, name : LibC::Char*, value : LibC::Char*) : Status
  fun set_allow_overflow = fsw_set_allow_overflow(handle : Handle, allow_overflow : Bool) : Status
  fun set_callback = fsw_set_callback(handle : Handle, callback : CeventCallback, data : Void*) : Status
  alias CeventCallback = (Cevent*, LibC::UInt, Void* -> Void)
  fun set_latency = fsw_set_latency(handle : Handle, latency : LibC::Double) : Status
  fun set_recursive = fsw_set_recursive(handle : Handle, recursive : Bool) : Status
  fun set_directory_only = fsw_set_directory_only(handle : Handle, directory_only : Bool) : Status
  fun set_follow_symlinks = fsw_set_follow_symlinks(handle : Handle, follow_symlinks : Bool) : Status
  fun add_event_type_filter = fsw_add_event_type_filter(handle : Handle, event_type : EventTypeFilter) : Status
  fun add_filter = fsw_add_filter(handle : Handle, filter : CmonitorFilter) : Status
  fun start_monitor = fsw_start_monitor(handle : Handle) : Status
  fun stop_monitor = fsw_stop_monitor(handle : Handle) : Status
  fun is_running = fsw_is_running(handle : Handle) : Bool
  fun destroy_session = fsw_destroy_session(handle : Handle) : Status
  fun last_error = fsw_last_error : Status
  fun is_verbose = fsw_is_verbose : Bool
  fun set_verbose = fsw_set_verbose(verbose : Bool)
  #  $ALL_EVENT_FLAGS : EventFlag[15]
end
