function [brainVerticesNew] = downsampleVertices(brainVertices, threshod, progress)
    if nargin < 3, progress = []; end
    brainVerticesNew = [];

    for i = 1:size(brainVertices,1)
        if ~isempty(progress) && (mod(i,100)==0 || i==1 || i==size(brainVertices,1)), progress(i,size(brainVertices,1)); end
        point = brainVertices(i,:);

        if isempty(brainVerticesNew) % add the first point to the new set
            brainVerticesNew(end+1,:) = point;
            continue
        else
            % is it close to any of the points in new_vertices?
            closeFlag = 0;
            for j = 1:size(brainVerticesNew,1)
                distance = sqrt((point(1) - brainVerticesNew(j,1))^2 + ...
                    (point(2) - brainVerticesNew(j,2))^2 + ...
                    (point(3) - brainVerticesNew(j,3))^2);
                if distance < threshod
                    closeFlag = 1;
                    break
                end
            end
        end
        % after running all the points in the new vertices, there is no close
        % points, we can add this one
        if closeFlag == 0
            brainVerticesNew(end + 1,:) = point;
        end
    end
