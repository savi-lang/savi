require "../src/fswatch"

# pp! FSWatch.verbose
# FSWatch.verbose = true
# pp! FSWatch.verbose

i = 5
FSWatch.watch __DIR__, latency: 3.0, recursive: false do |event|
  i -= 1
  pp! event
end

while i > 0
  puts "Waiting for #{i} events"
  sleep 0.1
  Fiber.yield
end
