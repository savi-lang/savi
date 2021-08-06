module Savi::AST::Extract
  def self.name_and_params(node : AST::Term) : {AST::Identifier, AST::Group?}
    case node
    when AST::Identifier
      {node, nil}
    when AST::Qualify
      {node.term.as(AST::Identifier), node.group}
    else
      raise NotImplementedError.new(node)
    end
  end

  def self.param(node : AST::Term) : {
    AST::Identifier, # identifier
    AST::Term?,      # explicit type
    AST::Term?}      # default parameter
    if node.is_a?(AST::Identifier)
      {node, nil, nil}
    elsif node.is_a?(AST::Relate) && node.op.value == "EXPLICITTYPE"
      {node.lhs.as(AST::Identifier), node.rhs, nil}
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
    if node.is_a?(AST::Identifier)
      {node, nil, nil}
    elsif node.is_a?(AST::Relate) && node.op.value == "EXPLICITTYPE"
      {node.lhs.as(AST::Identifier), node.rhs, nil}
    elsif node.is_a?(AST::Relate) \
    && (node.op.value == "DEFAULTPARAM" || node.op.value == "=")
      recurse = param(node.lhs)
      {recurse[0], recurse[1], node.rhs}
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
