function children = nodeChildren(node)
    %NODECHILDREN Keep Homer hierarchy knowledge in one adapter.
    if isa(node, "ssdot.homer.DatasetNode")
        children = node.children;
    elseif isa(node, "GroupClass")
        children = node.subjs;
    elseif isa(node, "SubjClass")
        children = node.sess;
    elseif isa(node, "SessClass")
        children = node.runs;
    else
        children = [];
    end
end
