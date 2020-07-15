module Mare::AST::Extract
  def self.call(node : AST::Relate) : {
    AST::Identifier, # identifier
    AST::Group?, # arguments
    AST::Group?, # yield params
    AST::Group?} # yield block
    rhs = node.rhs
    if rhs.is_a?(AST::Identifier)
      {rhs, nil, nil, nil}
    elsif rhs.is_a?(AST::Qualify)
      ident = rhs.term.as(AST::Identifier)
      {ident, rhs.group, nil, nil}
    elsif rhs.is_a?(AST::Relate) && rhs.op.value == "->"
      rhs_rhs = rhs.rhs.as(AST::Group)
      yield_params, yield_block =
        case rhs_rhs.style
        when "("
          {nil, rhs_rhs}
        when "|"
          raise NotImplementedError.new(rhs_rhs.to_a) \
            unless rhs_rhs.terms.size == 2 \

          {rhs_rhs.terms[0].as(AST::Group), rhs_rhs.terms[1].as(AST::Group)}
        else
          raise NotImplementedError.new(rhs_rhs.to_a)
        end

      rhs_lhs = rhs.lhs
      case rhs_lhs
      when AST::Identifier
        {rhs_lhs, nil, yield_params, yield_block}
      when AST::Qualify
        ident = rhs_lhs.term.as(AST::Identifier)
        {ident, rhs_lhs.group, yield_params, yield_block}
      else
        raise NotImplementedError.new(rhs_lhs.to_a)
      end
    else
      raise NotImplementedError.new(rhs.to_a)
    end
  end

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
