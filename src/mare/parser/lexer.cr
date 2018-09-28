require "lingo"

class Mare::Parser
  class Lexer < Lingo::Parser
    root :doc
    
    rule :doc { (line >> str("\n").named(:nl)).repeat >> line }
    rule :line {
      s \
      >> (s >> eol_item.absent >> normal_item).repeat(0) \
      >> (s >> eol_item.maybe) \
      >> s
    }
    
    rule :normal_item { (decl.named(:decl) >> terms.maybe) | terms }
    
    rule :eol_item { eol_comment }
    rule :eol_comment { str("//") >> (str("\n").absent >> any).repeat(0) }
    
    rule :decl { dterms >> s >> str(":") >> s }
    rule :dterms { dterm >> s >> dterms.maybe }
    rule :dterm { atom }
    
    rule :terms { (t >> s).repeat }
    rule :t { (tw >> (opw >> s >> tw >> s).repeat).named(:relate) | tw }
    rule :tw { (t1 >> (sn >> op1 >> sn >> t1 >> s).repeat).named(:relate) | t1 }
    rule :t1 { (t2 >> (sn >> op2 >> sn >> t2 >> s).repeat).named(:relate) | t2 }
    rule :t2 { (t3 >> (sn >> op3 >> sn >> t3 >> s).repeat).named(:relate) | t3 }
    rule :t3 { (t4 >> (sn >> op4 >> sn >> t4 >> s).repeat).named(:relate) | t4 }
    rule :t4 { (t5 >> (sn >> op5 >> sn >> t5 >> s).repeat).named(:relate) | t5 }
    rule :t5 { (t6 >> (sn >> op6 >> sn >> t6 >> s).repeat).named(:relate) | t6 }
    rule :t6 { (t7 >> (sn >> op7 >> sn >> t7 >> s).repeat).named(:relate) | t7 }
    rule :t7 { atom }
    
    rule :opw { str(" ").named(:op) }
    rule :op1 { match(/(&&|\|\|)/).named(:op) }
    rule :op2 { match(/(===|==|!==|!=|=~)/).named(:op) }
    rule :op3 { match(/(>=|<=|<|>)(?![><~|])/).named(:op) }
    rule :op4 { match(/(<\|>|<~>|<<<|>>>|<<~|~>>|<<|>>|<~|~>)/).named(:op) }
    rule :op5 { match(/(\.\.|<>)/).named(:op) }
    rule :op6 { match(/(\+|-)/).named(:op) }
    rule :op7 { match(/(\*|\/)/).named(:op) }
    
    rule :atom { parens | string | float | integer | ident }
    
    rule :parens { (str("(") >> s >> terms >> s >> str(")")).named(:group) }
    rule :string { str("\"") >> match(/[^"]*/).named(:string) >> str("\"") }
    rule :float { match(/\b[0-9][_0-9]*\.[_0-9]+\b/).named(:float) }
    rule :integer { match(/\b[1-9][_0-9]*\b/).named(:integer) }
    rule :ident { match(/\b\w+\b/).named(:ident) }
    
    rule :s { match(/( |\t|\r|\\\r?\n)*/) }
    rule :sn { match(/( |\t|\r|\\\r?\n|\n)*/) }
  end
end
