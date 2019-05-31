require "./spec_helper"

describe LSP::Wire do
  it "can send a notification" do
    i = IO::Memory.new("")
    o = IO::Memory.new
    
    wire = LSP::Wire.new(i, o)
    
    msg = wire.notify LSP::Message::ShowMessage do |msg|
      msg.params.message = "Hello, World!"
      msg
    end
    msg.params.message.should eq "Hello, World!"
    
    LSP::Codec.read_message(IO::Memory.new(o.to_s)).should eq msg
  end
  
  it "can send a request" do
    i = IO::Memory.new("")
    o = IO::Memory.new
    
    wire = LSP::Wire.new(i, o)
    
    msg = wire.request LSP::Message::ShowMessageRequest do |msg|
      msg.params.message = "Hello, World!"
      msg
    end
    msg.params.message.should eq "Hello, World!"
    
    LSP::Codec.read_message(IO::Memory.new(o.to_s)).should eq msg
  end
  
  it "can receive a request and send a response" do
    # Create some pipes to represent each end of the wire.
    i, send_i = IO.pipe
    from_o, o = IO.pipe
    
    # Write a request into the input of the wire.
    req = LSP::Message::Initialize.new(UUID.random.to_s)
    req.params.process_id = 42
    outstanding = {} of (String | Int64) => LSP::Message::AnyRequest
    LSP::Codec.write_message(send_i, req, outstanding)
    
    # Test that the wire can receive the request.
    wire = LSP::Wire.new(i, o)
    wire.receive.should eq req
    
    # Close the input end of the wire and test that we can't read any further.
    send_i.close
    expect_raises(Channel::ClosedError) { wire.receive }
    
    # Write a response back on the wire.
    msg = wire.respond req do |msg|
      msg.result.capabilities.hover_provider.should eq false
      msg.result.capabilities.hover_provider = true
      msg
    end
    msg.result.capabilities.hover_provider.should eq true
    
    # Test that the response written to the wire can be received.
    LSP::Codec.read_message(from_o, outstanding).should eq msg
  end
end
