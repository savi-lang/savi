require "./../spec_helper"

describe Array do
  describe "#duplicate_value" do
    it "retuens duplicate value." do
      ["a", "b", "a"].duplicate_value.should eq ["a"]
      ["a", "b", "a", "b", "c"].duplicate_value.should eq ["a", "b"]
      [1, 1, 2, 2, 3].duplicate_value.should eq [1, 2]
      [1, 1, "a", "a", 3].duplicate_value.should eq [1, "a"]
      [1, "a", 2, "b"].duplicate_value.should eq [] of String | Int32
      ([] of String | Int32).duplicate_value.should eq [] of String | Int32
    end
  end
end
