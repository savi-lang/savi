module Mare::Compiler::Macros::Util
  def self.match_ident?(node : AST::Group, index : Int32, value : String? = nil)
    child = node.terms[index]?
    return false unless child.is_a?(AST::Identifier)
    return false unless value.nil? || value == child.value
    true
  end
  
  def self.require_terms(node : AST::Group, term_docs : Array(String?))
    if node.terms.size > term_docs.size
      info = [] of Tuple(AST::Node, String)
      
      index = -1
      while (index += 1) < node.terms.size
        if index < term_docs.size
          if term_docs[index]
            info << {node.terms[index], "this term is #{term_docs[index]}"}
          end
        else
          info << {node.terms[index], "this is an excessive term"}
        end
      end
      
      Error.at node, "This macro has too many terms", info
    end
    
    if node.terms.size < term_docs.size
      info = [] of Tuple(AST::Node, String)
      
      index = -1
      while (index += 1) < term_docs.size
        if index < node.terms.size
          if term_docs[index]
            info << {node.terms[index], "this term is #{term_docs[index]}"}
          end
        else
          info << {node, "expected a term: #{term_docs[index]}"}
        end
      end
      
      Error.at node, "This macro has too few terms", info
    end
  end
end
