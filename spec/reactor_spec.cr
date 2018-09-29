require "./spec_helper"

describe Mare::Reactor do
  it "calls back to blocks that existed before fulfillment" do
    r = Mare::Reactor.new
    
    results = [] of Int32
    
    r.on(Int32, ["test", "foo"]) { |n| results << n + 1 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 2 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 3 }
    r.fulfill(["test", "foo"], "not an Int32")
    r.fulfill(["test", "foo"], 6)
    r.fulfill(["test", "bar"], -6)
    
    results.should eq [7, 8, 9]
  end
  
  it "calls back to blocks that are created after fulfillment" do
    r = Mare::Reactor.new
    
    results = [] of Int32
    
    r.fulfill(["test", "foo"], "not an Int32")
    r.fulfill(["test", "foo"], 6)
    r.fulfill(["test", "bar"], -6)
    r.on(Int32, ["test", "foo"]) { |n| results << n + 1 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 2 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 3 }
    
    results.should eq [7, 8, 9]
  end
  
  it "calls back to blocks that are created both before and after" do
    r = Mare::Reactor.new
    
    results = [] of Int32
    
    r.on(Int32, ["test", "foo"]) { |n| results << n + 1 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 2 }
    r.fulfill(["test", "foo"], "not an Int32")
    r.fulfill(["test", "foo"], 6)
    r.fulfill(["test", "bar"], -6)
    r.on(Int32, ["test", "foo"]) { |n| results << n + 3 }
    r.on(Int32, ["test", "foo"]) { |n| results << n + 4 }
    
    results.should eq [7, 8, 9, 10]
  end
  
  it "shows remaining expectations that were never fulfilled" do
    r = Mare::Reactor.new
    
    r.on(Int32, ["test", "foo"]) { }
    r.on(Int32, ["test", "bar"]) { }
    r.on(Int32, ["test", "baz"]) { }
    r.on(String, ["test", "foo"]) { }
    r.on(String, ["test", "bar"]) { }
    r.on(String, ["test", "baz"]) { }
    r.fulfill(["test", "foo"], 0)
    r.fulfill(["test", "bar"], "zero")
    r.fulfill(["test", "baz"], 0)
    
    r.show_remaining.sort.should eq [
      "- Int32 [\"test\", \"bar\"]",
      "- String [\"test\", \"baz\"]",
      "- String [\"test\", \"foo\"]",
    ]
  end
end
