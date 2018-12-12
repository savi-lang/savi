module Mare::Compiler::Macros::Util
  def self.match_ident?(node : AST::Group, index : Int32, value : String? = nil)
    child = node.terms[index]?
    return false unless child.is_a?(AST::Identifier)
    return false unless value.nil? || value == child.value
    true
  end
  
  def self.require_terms(node : AST::Group, term_docs : Array(String?))
    if node.terms.size > term_docs.size
      list = [] of String
      list << "This macro has too many terms:"
      list << node.pos.show
      
      index = -1
      while (index += 1) < node.terms.size
        if index < term_docs.size
          if term_docs[index]
            list << "- this term is #{term_docs[index]}:"
            list << node.terms[index].pos.show
          end
        else
          list << "- this is an excessive term:"
          list << node.terms[index].pos.show
        end
      end
      
      raise Error.new(list.join("\n"))
    end
    
    if node.terms.size < term_docs.size
      list = [] of String
      list << "This macro has too few terms:"
      list << node.pos.show
      
      index = -1
      while (index += 1) < term_docs.size
        if index < node.terms.size
          if term_docs[index]
            list << "- this term is #{term_docs[index]}:"
            list << node.terms[index].pos.show
          end
        else
          list << "- expected a term: #{term_docs[index]}"
        end
      end
      
      raise Error.new(list.join("\n"))
    end
  end
end
