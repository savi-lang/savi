# Add a timestamp property to all FSWatch events, so that we can track
# when the event was received by the thread that received it, rather than
# the time when we got around to first noticing it in our processing loop.
struct FSWatch::Event
  property timestamp : Time = Time.utc
end
