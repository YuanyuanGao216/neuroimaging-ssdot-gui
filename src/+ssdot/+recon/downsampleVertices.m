function centers = downsampleVertices(vertices, threshold, progress)
    %DOWNSAMPLEVERTICES Greedy subset of vertices with no two kept points closer than threshold.
    % Vertices are visited in order; each is kept unless it lies within threshold of a kept one.
    if nargin < 3 || isempty(progress)
        progress = @(varargin) [];
    end
    vertexCount = size(vertices, 1);
    centers = [];
    for i = 1:vertexCount
        if mod(i, 100) == 0 || i == 1 || i == vertexCount
            progress(i, vertexCount);
        end
        point = vertices(i, :);
        if ~isNearAny(point, centers, threshold)
            centers(end + 1, :) = point; %#ok<AGROW>
        end
    end
end

function near = isNearAny(point, centers, threshold)
    near = false;
    for j = 1:size(centers, 1)
        distance = sqrt((point(1) - centers(j, 1))^2 + ...
            (point(2) - centers(j, 2))^2 + ...
            (point(3) - centers(j, 3))^2);
        if distance < threshold
            near = true;
            return
        end
    end
end
