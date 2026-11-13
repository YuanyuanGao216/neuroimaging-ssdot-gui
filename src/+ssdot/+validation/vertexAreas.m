function area = vertexAreas(mesh)
    %VERTEXAREAS One third of the area of every triangle touching each vertex.
    faces = mesh.faces;
    vertices = mesh.vertices;
    edge1 = vertices(faces(:, 2), :) - vertices(faces(:, 1), :);
    edge2 = vertices(faces(:, 3), :) - vertices(faces(:, 1), :);
    triangleArea = sqrt(sum(cross(edge1, edge2, 2).^2, 2)) / 2;
    area = accumarray(faces(:), repmat(triangleArea / 3, 3, 1), [size(vertices, 1), 1]);
end
