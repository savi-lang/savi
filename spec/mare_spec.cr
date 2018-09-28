require "./spec_helper"

describe Mare do
  it "parses an example" do
    source = fixture "example.mare"
    
    ast = Mare::Parser.new.parse(source)
    ast.should be_truthy
    
    visitor = Mare::Visitor.new
    visitor.visit(ast)
    visitor.doc.should eq [
      Mare::AST::Declare.new([
        Mare::AST::Identifier.new("class"),
        Mare::AST::Identifier.new("Example"),
      ] of Mare::AST::Term),
      Mare::AST::Declare.new([
        Mare::AST::Identifier.new("prop"),
        Mare::AST::Identifier.new("name"),
        Mare::AST::Identifier.new("String"),
      ] of Mare::AST::Term, [
        Mare::AST::LiteralString.new("World"),
      ] of Mare::AST::Term),
      Mare::AST::Declare.new([
        Mare::AST::Identifier.new("fun"),
        Mare::AST::Identifier.new("ref"),
        Mare::AST::Identifier.new("greeting"),
        Mare::AST::Identifier.new("String"),
      ] of Mare::AST::Term, [
        Mare::AST::Relate.new([
          Mare::AST::LiteralString.new("Hello, "),
          Mare::AST::Operator.new("+"),
          Mare::AST::Identifier.new("name"),
          Mare::AST::Operator.new("+"),
          Mare::AST::LiteralString.new("!"),
        ] of Mare::AST::Term),
      ] of Mare::AST::Term),
    ]
  end
end
