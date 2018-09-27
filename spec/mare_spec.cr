require "./spec_helper"

describe Mare do
  it "parses an example" do
    source = fixture "example.mare"
    
    ast = Mare::Parser.new.parse(source)
    ast.should be_truthy
    
    visitor = Mare::Visitor.new
    visitor.visit(ast)
    visitor.doc.should eq [
      [
        Mare::AST::Identifier.new("class"),
        Mare::AST::Identifier.new("Example"),
      ],
      [
        Mare::AST::Identifier.new("prop"),
        Mare::AST::Identifier.new("name"),
        Mare::AST::Identifier.new("String"),
      ],
      [
        Mare::AST::Identifier.new("fun"),
        Mare::AST::Identifier.new("ref"),
        Mare::AST::Identifier.new("greeting"),
        Mare::AST::Identifier.new("String"),
      ],
    ]
  end
end
