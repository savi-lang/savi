module Mare::AST::Extract
  def self.param(node : AST::Term) : {
    AST::Identifier, # identifier
    AST::Term?,      # explicit type
    AST::Term?}      # default parameter
    if node.is_a?(AST::Identifier)
      {node, nil, nil}
    elsif node.is_a?(AST::Group) \
    && node.style == " " \
    && node.terms.size == 2
      {node.terms[0].as(AST::Identifier), node.terms[1], nil}
    elsif node.is_a?(AST::Relate) \
    && (node.op.value == "DEFAULTPARAM" || node.op.value == "=")
      recurse = param(node.lhs)
      {recurse[0], recurse[1], node.rhs}
    else
      raise NotImplementedError.new(node.to_a)
    end
  end

  def self.params(node : AST::Group?)
    return [] of {AST::Identifier, AST::Term?, AST::Term?} unless node

    node.terms.map { |child| param(child) }
  end

  def self.type_param(node : AST::Term) : {
    AST::Identifier, # identifier
    AST::Term?,      # bound
    AST::Term?}      # default
    case node
    when AST::Identifier
      {node, nil, nil}
    when AST::Group
      raise NotImplementedError.new(node) \
        unless node.terms.size == 2 && node.style == " "

      {node.terms.first.as(AST::Identifier), node.terms.last.as(AST::Term), nil}
    when AST::Relate
      raise NotImplementedError.new(node) unless node.op.value == "="

      ident, bound, _ = type_param(node.lhs)
      {ident, bound, node.rhs.as(AST::Term)}
    else
      raise NotImplementedError.new(node)
    end
  end

  def self.type_params(node : AST::Group?)
    return [] of {AST::Identifier, AST::Term?, AST::Term?} unless node

    node.terms.map { |child| type_param(child) }
  end

  def self.type_arg(node : AST::Term) : {
    AST::Identifier,  # identifier
    AST::Identifier?} # cap
    # TODO: handle more cases?
    case node
    when AST::Identifier
      {node, nil}
    when AST::Relate
      raise NotImplementedError.new(node) unless node.op.value == "'"

      {node.lhs.as(AST::Identifier), node.rhs.as(AST::Identifier)}
    else
      raise NotImplementedError.new(node)
    end
  end
end
