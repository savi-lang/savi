require "../src/fswatch"

FSWatch.watch "./playground", recursive: true do |event|
  pp! event, event.path, event.created?, event.is_file?
end

puts "sleeping..."
sleep 10
