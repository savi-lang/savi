require "pegmatite"

module Mare::Parser
  module Builder
    def self.build(tokens, source)
      iter = Pegmatite::TokenIterator.new(tokens)
      main = iter.next
      build_doc(main, iter, source)
    end
    
    private def self.assert_kind(token, kind)
      raise "Unexpected token: #{token.inspect}; expected: #{kind.inspect}" \
        unless token[0] == kind
    end
    
    private def self.build_doc(main, iter, source)
      assert_kind(main, :doc)
      doc = AST::Document.new
      decl : AST::Declare? = nil
      
      iter.while_next_is_child_of(main) do |child|
        if child[0] == :decl
          decl = build_decl(child, iter, source)
          doc.list << decl
        else
          decl.as(AST::Declare).body << build_term(child, iter, source)
        end
      end
      
      doc
    end
    
    private def self.build_decl(main, iter, source)
      assert_kind(main, :decl)
      decl = AST::Declare.new.with_pos(source, main)
      
      iter.while_next_is_child_of(main) do |child|
        decl.head << build_term(child, iter, source)
      end
      
      decl
    end
    
    private def self.build_term(main, iter, source)
      kind, start, finish = main
      case kind
      when :ident
        value = source.content[start...finish]
        AST::Identifier.new(value).with_pos(source, main)
      when :string
        value = source.content[start...finish]
        AST::LiteralString.new(value).with_pos(source, main)
      when :integer
        value = source.content[start...finish].to_u64
        AST::LiteralInteger.new(value).with_pos(source, main)
      when :float
        value = source.content[start...finish].to_f
        AST::LiteralFloat.new(value).with_pos(source, main)
      when :op
        value = source.content[start...finish]
        AST::Operator.new(value).with_pos(source, main)
      when :relate  then build_relate(main, iter, source)
      when :group   then build_group(main, iter, source)
      when :prefix  then build_prefix(main, iter, source)
      when :qualify then build_qualify(main, iter, source)
      else
        raise NotImplementedError.new(kind)
      end
    end
    
    private def self.build_relate(main, iter, source)
      assert_kind(main, :relate)
      relate = AST::Relate.new.with_pos(source, main)
      
      iter.while_next_is_child_of(main) do |child|
        relate.terms << build_term(child, iter, source)
      end
      
      relate
    end
    
    private def self.build_group(main, iter, source)
      assert_kind(main, :group)
      style = source.content[main[1]..main[1]]
      group = AST::Group.new(style).with_pos(source, main)
      
      iter.while_next_is_child_of(main) do |child|
        group.terms << build_term(child, iter, source)
      end
      
      group
    end
    
    private def self.build_prefix(main, iter, source)
      assert_kind(main, :prefix)
      
      op = build_term(iter.next_as_child_of(main), iter, source)
      op = op.as(AST::Operator)
      
      term = build_term(iter.next_as_child_of(main), iter, source)
      
      # TODO: Don't use array of terms here.
      AST::Prefix.new(op, [term]).with_pos(source, main)
    end
    
    private def self.build_qualify(main, iter, source)
      assert_kind(main, :qualify)
      
      term = build_term(iter.next_as_child_of(main), iter, source)
      
      group = build_term(iter.next_as_child_of(main), iter, source)
      group = group.as(AST::Group)
      
      # TODO: Flip order and don't use array of terms here.
      AST::Qualify.new(group, [term]).with_pos(source, main)
    end
  end
end
