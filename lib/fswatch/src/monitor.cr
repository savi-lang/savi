module FSWatch
  enum MonitorType
    SystemDefault
    Fsevents
    Kqueue
    Inotify
    Windows
    Poll
    Fen

    def to_unsafe
      case self
      in SystemDefault then LibFSWatch::MonitorType::SystemDefaultMonitorType
      in Fsevents      then LibFSWatch::MonitorType::FseventsMonitorType
      in Kqueue        then LibFSWatch::MonitorType::KqueueMonitorType
      in Inotify       then LibFSWatch::MonitorType::InotifyMonitorType
      in Windows       then LibFSWatch::MonitorType::WindowsMonitorType
      in Poll          then LibFSWatch::MonitorType::PollMonitorType
      in Fen           then LibFSWatch::MonitorType::FenMonitorType
      end
    end
  end

  alias FilterType = LibFSWatch::FilterType

  record MonitorFilter, text : String, type : FilterType, case_sensitive : Bool, extended : Bool
end
