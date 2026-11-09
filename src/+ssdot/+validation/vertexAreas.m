function area=vertexAreas(mesh)
    f=mesh.faces; v=mesh.vertices;
    triangle=sqrt(sum(cross(v(f(:,2),:)-v(f(:,1),:),v(f(:,3),:)-v(f(:,1),:),2).^2,2))/2;
    area=accumarray(f(:),repmat(triangle/3,3,1),[size(v,1),1]);
end

