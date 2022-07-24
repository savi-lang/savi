module FSWatch
  alias EventFlag = LibFSWatch::EventFlag

  record EventTypeFilter, flag : EventFlag

  record Event, path : String, event_flag : EventFlag do
    def no_op?
      (event_flag & EventFlag::NoOp) == EventFlag::NoOp
    end

    def platform_specific?
      (event_flag & EventFlag::PlatformSpecific) == EventFlag::PlatformSpecific
    end

    def created?
      (event_flag & EventFlag::Created) == EventFlag::Created
    end

    def updated?
      (event_flag & EventFlag::Updated) == EventFlag::Updated
    end

    def removed?
      (event_flag & EventFlag::Removed) == EventFlag::Removed
    end

    def renamed?
      (event_flag & EventFlag::Renamed) == EventFlag::Renamed
    end

    def owner_modified?
      (event_flag & EventFlag::OwnerModified) == EventFlag::OwnerModified
    end

    def attribute_modified?
      (event_flag & EventFlag::AttributeModified) == EventFlag::AttributeModified
    end

    def moved_from?
      (event_flag & EventFlag::MovedFrom) == EventFlag::MovedFrom
    end

    def moved_to?
      (event_flag & EventFlag::MovedTo) == EventFlag::MovedTo
    end

    def is_file?
      (event_flag & EventFlag::IsFile) == EventFlag::IsFile
    end

    def is_dir?
      (event_flag & EventFlag::IsDir) == EventFlag::IsDir
    end

    def is_sym_link?
      (event_flag & EventFlag::IsSymLink) == EventFlag::IsSymLink
    end

    def link?
      (event_flag & EventFlag::Link) == EventFlag::Link
    end

    def overflow?
      (event_flag & EventFlag::Overflow) == EventFlag::Overflow
    end
  end
end
