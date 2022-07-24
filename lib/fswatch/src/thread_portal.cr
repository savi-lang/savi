module FSWatch
  # :nodoc:
  struct ThreadPortal(T)
    {% if flag?(:preview_mt) %}
      @channel : Channel(T)

      def initialize
        @channel = Channel(T).new
      end
    {% else %}
      @producer_reader : IO
      @producer_writer : IO
      @consumer_reader : IO
      @consumer_writer : IO
      @next_value : T

      def initialize
        @producer_reader, @producer_writer = IO.pipe(read_blocking: false, write_blocking: true)
        @consumer_reader, @consumer_writer = IO.pipe(read_blocking: false, write_blocking: true)
        @next_value = uninitialized T
      end
    {% end %}

    def send(value : T)
      {% if flag?(:preview_mt) %}
        @channel.send value
      {% else %}
        @next_value = value
        @producer_writer.write_bytes(1i32)
        @consumer_reader.read_bytes(Int32)
      {% end %}
    end

    def receive : T
      {% if flag?(:preview_mt) %}
        @channel.receive
      {% else %}
        @producer_reader.read_bytes(Int32)
        value = @next_value
        @consumer_writer.write_bytes(1i32)
        value
      {% end %}
    end
  end
end
