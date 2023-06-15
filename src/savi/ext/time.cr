require "time"

struct Time
  # A handy convenience method for measuring the time duration of a block.
  # It works like Time.measure but it returns the result value of the block
  # and prints the timing information, including an optional label and indent.
  def self.show(label : String, indent : Int32 = 0, &block : Nil -> U) : U forall U
    result : U? = nil
    time = Time.measure { result = block.call(nil) }
    puts "#{" " * indent}#{time} - #{label}"
    result.as(U)
  end
end
