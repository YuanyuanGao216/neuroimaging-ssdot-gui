function output = evaluatePerformance(GHbOMat,GHbRMat, hbOSZero, hbRSZero, cfg, faces, brainVertices, cond)

    AFile = ['fw',filesep, 'Adot.mat'];
    AScalpFile = ['fw',filesep,'Adot_scalp.mat'];

    Adot        = load([cfg.av_data_path, AFile]);
    adotScalp  = load([cfg.av_data_path, AScalpFile]);

    M = ssdot.recon.buildSensitivityMask(cfg.mask_threshold, Adot.Adot, adotScalp.Adot_scalp);
    index = setdiff(1:size(GHbOMat,1), M.mask_brain);
    GHbOMat(index,:,:) = 0;
    GHbRMat(index,:,:) = 0;
    hbOSZero(index,:,:) = 0;
    hbRSZero(index,:,:) = 0;
    if exist('cond','var') % this is for experimental data
        if isfile(fullfile(cfg.ROI_path, 'ROI', ['ROI', num2str(cond), '.mat']))
            fprintf('load ROI\n')
            storedData = load(fullfile(cfg.ROI_path, 'ROI', ['ROI', num2str(cond), '.mat']), 'index_ROI', 'index_nonROI');
            indexROI = storedData.index_ROI;
            indexNonROI = storedData.index_nonROI;
        else
            fprintf('create ROI\n')
            [indexROI, indexNonROI] = ssdot.recon.findRoi(hbOSZero,hbRSZero, M, brainVertices, 0.90, 0.01, 40, cfg);
            mkdir(fullfile(cfg.ROI_path, 'ROI'))
            savedData = struct();
            savedData.index_ROI = indexROI;
            savedData.index_nonROI = indexNonROI;
            save(fullfile(cfg.ROI_path, 'ROI', ['ROI', num2str(cond), '.mat']),'-struct','savedData');
        end
    else % this is for simulation data
        if isfile(fullfile(cfg.ROI_path, 'ROI', ['ROI', '.mat']))
            fprintf('load ROI\n')
            storedData = load(fullfile(cfg.ROI_path, 'ROI', ['ROI', '.mat']), 'index_ROI', 'index_nonROI');
            indexROI = storedData.index_ROI;
            indexNonROI = storedData.index_nonROI;
            %     if 0
        else
            fprintf('create ROI\n')
            [indexROI, indexNonROI] = ssdot.recon.findRoi(hbOSZero,hbRSZero, M, brainVertices, 0.90, 0.01, 40, cfg);
            mkdir(fullfile(cfg.ROI_path, 'ROI'))
            savedData = struct();
            savedData.index_ROI = indexROI;
            savedData.index_nonROI = indexNonROI;
            save(fullfile(cfg.ROI_path, 'ROI', ['ROI', '.mat']),'-struct','savedData');
        end
    end
    % [index_ROI, index_nonROI] = find_ROI(HbO_S_zero,HbR_S_zero, M, brain_vertices, 0.50, 0.01, 0);
    axesOrder = [2,1,3];

    hFigure = figure('name','brain');
    intensity = zeros(size(brainVertices,1), 1);
    h = trisurf(faces, brainVertices(:,axesOrder(1)), brainVertices(:,axesOrder(2)), brainVertices(:,axesOrder(3)), ...
        intensity,'facecolor','black','facealpha',0.1,'edgealpha',0, 'visible','on');
    set(h,'diffusestrength',.9,'specularstrength',.12,'ambientstrength',.2);

    hold on
    plot3(brainVertices(indexROI,axesOrder(1)),brainVertices(indexROI,axesOrder(2)),brainVertices(indexROI,axesOrder(3)),'r.','linewidth',1,'markersize',13);
    plot3(brainVertices(indexNonROI,axesOrder(1)),brainVertices(indexNonROI,axesOrder(2)),brainVertices(indexNonROI,axesOrder(3)),'g.','linewidth',1,'markersize',13);
    % left
    view(-90,0)
    camtarget([128.0, 132.0, 130.0])
    campos([128.0, 2238.8, 130.0])
    camup([-1.0, 0.0, 0.0])
    % right
    % view(-90,0)
    % camtarget([128.0, 132.0, 130.0])
    % campos([128.0, -2291.8, 130.0])
    % camup([-1.0, 0.0, 0.0])

    set(gcf,'position',[10         10          313         242])
    axis off
    axis image
    imageFolder = 'image';
    mkdir(fullfile(cfg.savepath,imageFolder))
    if exist('cond','var') % this is for experimental data
        savefig(hFigure, fullfile(cfg.savepath,imageFolder,['ROI',num2str(cond),'.fig']))
    else
        savefig(hFigure, fullfile(cfg.savepath,imageFolder,'ROI.fig'))
    end
    close(hFigure)

    %% t value
    % group average
    concMeanHbO = mean(GHbOMat,3);
    concMeanHbR = mean(GHbRMat,3);

    % visualize the subject results
    if exist('cond','var') % this is for experimental data
        ssdot.viz.plotHemoglobin(['group_mean', num2str(cond)], faces, brainVertices, concMeanHbO, concMeanHbR, cfg, imageFolder,'off')
    else
        ssdot.viz.plotHemoglobin('group_mean', faces, brainVertices, concMeanHbO, concMeanHbR, cfg, imageFolder,'off')
    end

    % figure
    % subplot(131)
    % for subj = 1:size(G_HbO_mat,3)
    %     y = G_HbO_mat(:,:,subj);
    %     plot(y)
    %     hold on
    % end
    % subplot(132)
    % for subj = 1:size(G_HbO_mat,3)
    %     y = G_HbO_mat(index_ROI,:,subj);
    %     plot(y)
    %     hold on
    % end
    % subplot(133)
    % for subj = 1:size(G_HbO_mat,3)
    %     y = mean(G_HbO_mat(index_ROI,:,subj));
    %     plot(1, y, 'o')
    %     hold on
    % end
    % t value
    % first average the voxels
    voxAvgHbO = mean(GHbOMat(indexROI,:,:),1);
    voxAvgHbR = mean(GHbRMat(indexROI,:,:),1);
    % then std across subj
    stdSubjHbO = squeeze(std(voxAvgHbO, [], 3,'omitnan'));
    stdSubjHbR = squeeze(std(voxAvgHbR, [], 3,'omitnan'));

    meanSubjHbO = squeeze(mean(voxAvgHbO, 3,'omitnan'));
    meanSubjHbR = squeeze(mean(voxAvgHbR, 3,'omitnan'));

    tValueHbO = meanSubjHbO/(stdSubjHbO/sqrt(size(GHbOMat,3)));
    tValueHbR = meanSubjHbR/(stdSubjHbR/sqrt(size(GHbRMat,3)));

    output.t_value_HbO = tValueHbO;
    output.t_value_HbR = tValueHbR;
    output.Contrast_HbO = meanSubjHbO;
    output.Contrast_HbR = meanSubjHbR;
    output.std_HbO = stdSubjHbO;
    output.std_HbR = stdSubjHbR;

    % t value nonROI
    % first average the voxels
    voxAvgHbO = mean(GHbOMat(indexNonROI,:,:),1);
    voxAvgHbR = mean(GHbRMat(indexNonROI,:,:),1);
    % then std across subj
    stdSubjHbO = squeeze(std(voxAvgHbO, [], 3,'omitnan'));
    stdSubjHbR = squeeze(std(voxAvgHbR, [], 3,'omitnan'));

    meanSubjHbO = squeeze(mean(voxAvgHbO, 3,'omitnan'));
    meanSubjHbR = squeeze(mean(voxAvgHbR, 3,'omitnan'));

    tValueHbO = meanSubjHbO/(stdSubjHbO/sqrt(size(GHbOMat,3)));
    tValueHbR = meanSubjHbR/(stdSubjHbR/sqrt(size(GHbRMat,3)));

    output.t_value_HbO2 = tValueHbO;
    output.t_value_HbR2 = tValueHbR;
    output.Contrast_HbO2 = meanSubjHbO;
    output.Contrast_HbR2 = meanSubjHbR;
    output.std_HbO2 = stdSubjHbO;
    output.std_HbR2 = stdSubjHbR;

    %% test
    % thred = 30:2:45;
    % t_value_HbO = zeros(size(thred));
    % SBR_HbO = zeros(size(thred));
    % for i = 1:length(thred)
    %     [index_ROI, index_nonROI] = find_ROI(HbO_S_zero,HbR_S_zero, M, brain_vertices, 0.95, 0.001, thred(i));
    %     vox_avg_HbO = mean(G_HbO_mat(index_ROI,:,:),1);
    %     std_subj_HbO = squeeze(std(vox_avg_HbO, [], 3,'omitnan'));
    %     mean_subj_HbO = squeeze(mean(vox_avg_HbO, 3,'omitnan'));
    %     t_value_HbO(i) = mean_subj_HbO/(std_subj_HbO/sqrt(size(G_HbO_mat,3)));
    %     SBR_HbO(i) = mean(abs(mean(G_HbO_mat(index_ROI,:,:),1)./std(G_HbO_mat(index_nonROI,:,:),[],1)),3);
    % end
    % figure
    % plot(thred, t_value_HbO)
    % figure
    % plot(thred, SBR_HbO)
    %% SBR
    sbrHbO = mean(abs(mean(GHbOMat(indexROI,:,:),1)./std(GHbOMat(indexNonROI,:,:),[],1)),3);
    sbrHbR = mean(abs(mean(GHbRMat(indexROI,:,:),1)./std(GHbRMat(indexNonROI,:,:),[],1)),3);
    % mean_HbO = mean(G_HbO_mat, 3);
    % mean_HbR = mean(G_HbR_mat, 3);
    % SBR_HbO = mean(mean_HbO(index_ROI, :),1)/std(mean_HbO(index_nonROI, :), [], 1);
    % SBR_HbR = mean(mean_HbR(index_ROI, :),1)/std(mean_HbR(index_nonROI, :), [], 1);
    output.SBR_HbO = sbrHbO;
    output.SBR_HbR = sbrHbR;

    %% LI
    leftHemiIdx  = find(brainVertices(:,1) > 130);
    rightHemiIdx = find(brainVertices(:,1) <= 130);
    liSubjHbO = zeros(size(GHbOMat, 3), 1);
    liSubjHbR = zeros(size(GHbRMat, 3), 1);
    for i = 1:size(GHbOMat,3)
        hbOValue = squeeze(GHbOMat(:,:,i));
        hbRValue = - squeeze(GHbRMat(:,:,i));
        if exist('cond','var')
            liSubjHbO(i) = findLI(hbOValue,leftHemiIdx, rightHemiIdx, cond);
            liSubjHbR(i) = findLI(hbRValue,leftHemiIdx, rightHemiIdx, cond);
        end
    end
    hbOValue = squeeze(mean(GHbOMat, 3));
    hbRValue = - squeeze(mean(GHbRMat, 3));
    if exist('cond','var')
        liMeanHbO = findLI(hbOValue,leftHemiIdx, rightHemiIdx, cond);
        liMeanHbR = findLI(hbRValue,leftHemiIdx, rightHemiIdx, cond);
        output.LI_subj_HbO = liSubjHbO;
        output.LI_subj_HbR = liSubjHbR;
        output.LI_mean_HbO = liMeanHbO;
        output.LI_mean_HbR = liMeanHbR;
    end

    %% positional error

    if ~exist('cond','var') % this is for simulation data
        intensity = concMeanHbO(M.mask_brain);
        error = 0;
        sumX = 0;
        axesOrder = [2,1,3];
        fvhmIndex = find(intensity > 0.5*max(intensity));
        %     FVHM_index = index_ROI;

        for i = 1:length(fvhmIndex)
            index = fvhmIndex(i);
            x = intensity(index)-min(intensity(fvhmIndex));
            indexBrain = M.mask_brain(index);
            r = sqrt((brainVertices(indexBrain,axesOrder(1)) - cfg.center(1)).^2 + ...
                (brainVertices(indexBrain,axesOrder(2)) - cfg.center(2)).^2 + ...
                (brainVertices(indexBrain,axesOrder(3)) - cfg.center(3)).^2);
            error = error + x*r;
            sumX = sumX + x;
        end
        if length(fvhmIndex) == 1
            output.positional_error_HbO = r;
        else
            output.positional_error_HbO = error/sumX;
        end
        output.positional_error_HbR = output.positional_error_HbO;

        %     % second
        %     if cfg.original_ROI == 0
        %         max_pos_true_HbO = brain_vertices(find(HbO_S_zero == max(HbO_S_zero),1),:);
        %         max_pos_true_HbR = brain_vertices(find(HbR_S_zero == max(HbR_S_zero),1),:);
        %     elseif cfg.original_ROI == 1
        maxPosTrueHbO = cfg.center(axesOrder);
        maxPosTrueHbR = cfg.center(axesOrder);
        %     end
        % how many max values
        fprintf('max(HbO) %d\t max(HbR) %d \n', length(find(concMeanHbO == max(concMeanHbO),1)), length(find(concMeanHbR == max(concMeanHbR),1)))
        maxPosHbO = brainVertices(find(concMeanHbO == max(concMeanHbO),1),:);
        maxPosHbR = brainVertices(find(concMeanHbR == min(concMeanHbR),1),:);
        output.positional_error_HbO_2 = sqrt(sum((maxPosHbO - maxPosTrueHbO).^2));
        output.positional_error_HbR_2 = sqrt(sum((maxPosHbR - maxPosTrueHbR).^2));

    end

end

function LI = findLI(hbOValue,leftHemiIdx, rightHemiIdx, cond)
    V50 = find(hbOValue > 0.5* max(hbOValue));
    if cond == 1
        C = length(intersect(V50, rightHemiIdx));
        I = length(intersect(V50, leftHemiIdx));
    elseif cond == 2
        C = length(intersect(V50, leftHemiIdx));
        I = length(intersect(V50, rightHemiIdx));
    end
    LI = (C - I)/(C + I);
end
