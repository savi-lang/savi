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
      (decl.named(:decl) >> impr.maybe) | impr
    }
    
    rule :eol_item { eol_comment }
    rule :eol_comment { str("//") >> (str("\n").absent >> any).repeat(0) }
    
    rule :decl { dterms >> s >> str(":") >> s }
    rule :dterms { dterm >> s >> dterms.maybe }
    rule :dterm { ident.named(:decl_ident) }
    
    rule :impr { string }
    
    rule :s { match(/( |\t|\r|\\\r?\n)*/) }
    rule :ident { match(/\b\w+\b/).named(:ident) }
    rule :string { str("\"") >> match(/[^"]*/).named(:string) >> str("\"") }
  end
end
