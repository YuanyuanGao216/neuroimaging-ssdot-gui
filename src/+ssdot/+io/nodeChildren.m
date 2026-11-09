function children = nodeChildren(node)
    %NODECHILDREN Keep Homer hierarchy knowledge in one adapter.
    if isa(node, "GroupClass")
        children = node.subjs;
    elseif isa(node, "SubjClass")
        children = node.sess;
    elseif isa(node, "SessClass")
        children = node.runs;
    else
        children = [];
    end
end
