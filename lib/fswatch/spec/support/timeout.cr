def with_timeout(timeout = 3.seconds, file = __FILE__, line = __LINE__, &block : -> T) forall T
  value = Channel(T).new
  error = Channel(Exception).new

  spawn do
    begin
      value.send block.call
    rescue e
      error.send e
    end
  end

  select
  when val = value.receive
    val
  when e = error.receive
    raise e
  when timeout(timeout)
    fail "Unexpected timeout", file: file, line: line
  end
end

def no_return(timeout = 3.seconds, file = __FILE__, line = __LINE__, &block : -> T) forall T
  value = Channel(T).new
  error = Channel(Exception).new

  spawn do
    begin
      value.send block.call
    rescue e
      error.send e
    end
  end

  select
  when val = value.receive
    fail "Unexpected returned value #{val.inspect}", file: file, line: line
  when e = error.receive
    raise e
  when timeout(timeout)
    nil # ok
  end
end
