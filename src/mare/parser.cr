require "lingo"

module Mare
  class Parser < Lingo::Parser
    root :doc
    
    rule :doc { (line >> str("\n").named(:nl)).repeat >> line }
    rule :line {
      s \
      >> (s >> eol_item.absent >> normal_item).repeat(0) \
      >> (s >> eol_item.maybe) \
      >> s
    }
    
    rule :normal_item {
      (decl.named(:decl) >> terms.maybe) | terms
    }
    
    rule :eol_item { eol_comment }
    rule :eol_comment { str("//") >> (str("\n").absent >> any).repeat(0) }
    
    rule :decl { dterms >> s >> str(":") >> s }
    rule :dterms { dterm >> s >> dterms.maybe }
    rule :dterm { ident }
    
    rule :terms { (term1 >> s >> terms) | term1 }
    rule :term1 { (term2 >> s >> binop1 >> s >> term1).named(:relate) | term2 }
    rule :term2 { ident | string }
    
    rule :binop1 { str("+") }
    
    rule :s { match(/( |\t|\r|\\\r?\n)*/) }
    rule :ident { match(/\b\w+\b/).named(:ident) }
    rule :string { str("\"") >> match(/[^"]*/).named(:string) >> str("\"") }
  end
end
