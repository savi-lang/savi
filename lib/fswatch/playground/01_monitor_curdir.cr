require "../src/fswatch"

session = FSWatch::Session.new
session.add_path __DIR__
session.on_change do |event|
  pp! event
end

puts "Starting monitor"
session.start_monitor

sleep 10

puts "Stopping monitor"
session.stop_monitor
