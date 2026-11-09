function simulatePerturbation(cfg)
    cfg = ssdot.simulation.validateInputs(cfg);

    %% Prepare savepath folder
    restingDataFolder = cfg.restingpath;
    cfg.savepath_rs = fullfile(cfg.savepath,'simulated_rs',num2str(cfg.scale_factor));
    cfg.savepath_zeros = fullfile(cfg.savepath,'simulated_zeros',num2str(cfg.scale_factor));
    cfg.savepath_snirf = fullfile(cfg.savepath,'simulated_snirf');
    cfg.savepath_resting = fullfile(cfg.savepath,'resting');
    mkdir(cfg.savepath_rs)
    mkdir(cfg.savepath_zeros)
    mkdir(cfg.savepath_snirf)
    mkdir(cfg.savepath_resting)
    mkdir(fullfile(cfg.savepath_zeros,'Subject'))
    %% aquire brain model vertices
    unilateralDataPath = cfg.unilateral_data_path;
    atFile = 'atlasViewer.mat';
    atlasViewer = load(fullfile(unilateralDataPath, atFile));
    brainVertices = atlasViewer.fwmodel.mesh.vertices; %20004*3
    scalpVertices = atlasViewer.fwmodel.mesh_scalp.vertices; %9563*3

    %% make perturbation
    axesOrder = [2,1,3];
    indexPerturbation = [];

    for i = 1:size(cfg.center,1)
        perturbationCenter = cfg.center(i,:);
        distance = sqrt((brainVertices(:,axesOrder(1)) - perturbationCenter(1)).^2 + ...
            (brainVertices(:,axesOrder(2)) - perturbationCenter(2)).^2 + ...
            (brainVertices(:,axesOrder(3)) - perturbationCenter(3)).^2);
        indexPerturbation = [indexPerturbation; find(distance<15)];
    end

    visualizePerturbation(cfg,atlasViewer,brainVertices,indexPerturbation,cfg.scale_factor)
    %% read the resting state data
    acquired = SnirfClass(cfg.reference_file);
    rhoSDSsThresh = 20;
    ml     = acquired.data.GetMeasListSrcDetPairs();
    SrcPos = acquired.probe.GetSrcPos();
    DetPos = acquired.probe.GetDetPos();
    lst = 1:size(ml,1);
    rhoSD = zeros(length(lst),1);
    posM = zeros(length(lst),3);
    for iML = 1:length(lst)
        rhoSD(iML) = sum((SrcPos(ml(lst(iML),1),:) - DetPos(ml(lst(iML),2),:)).^2).^0.5;
        posM(iML,:) = (SrcPos(ml(lst(iML),1),:) + DetPos(ml(lst(iML),2),:)) / 2;
    end
    lstSS = lst(find(rhoSD<=rhoSDSsThresh));
    %% calculate OD
    rsFolder = dir(fullfile(restingDataFolder,'*'));
    subjectFolder = setdiff({rsFolder([rsFolder.isdir]).name},{'.','..'});

    for ii = 1:numel(subjectFolder)
        mkdir([cfg.savepath_rs,filesep,subjectFolder{ii}])
        mkdir([cfg.savepath_snirf,filesep,subjectFolder{ii}])
        snirffile = dir(fullfile(restingDataFolder,subjectFolder{ii},'*.snirf'));
        snirffilelist = {snirffile(~[snirffile.isdir]).name};
        for jj = 1:numel(snirffilelist)
            snirf = fullfile(restingDataFolder,subjectFolder{ii},snirffilelist{jj});
            snirfObj = SnirfClass(snirf);
            fprintf('%s:\n',snirf)
            t = snirfObj.GetTime();
            % cut to the same length
            snirfObj.data.SetTime(t(1:2578))
            x = snirfObj.data.GetDataTimeSeries();
            snirfObj.data.SetDataTimeSeries(x(1:2578,:));

            snirfObj = ssdot.io.reorderMeasurements(snirfObj,cfg.reference_file);
            odRearrange = hmrR_Intensity2OD(snirfObj.data);
            odRearrange = odRearrange.GetDataTimeSeries;
            tNew = snirfObj.GetTime();
            dt = tNew(2) - tNew(1);
            nT = length(tNew);
            % time basis function
            tbasis = buildHrfBasis(dt);
            [T,stim] = buildStimulusDesign(nT,dt,tbasis,cfg.stim_sequences_path);
            savedData = struct();
            savedData.OD_rearrange = odRearrange;
            savedData.T = T;
            savedData.stim = stim;
            savedData.t_new = tNew;
            save(fullfile(cfg.savepath_resting, [subjectFolder{ii},'.mat']),'-struct','savedData');

            if ~isfile(fullfile(cfg.savepath_snirf, subjectFolder{ii}, snirffilelist{jj}))
                snirfObj.probe.detectorPos2D(17,:) = [67.8, 57, 0];
                snirfObj.probe.detectorPos3D(17,:) = [67.8, 57, 0];
                measurementListWl1 = snirfObj.data.measurementList(1,50).copy;
                measurementListWl1.detectorIndex = 17;
                measurementListWl2 = snirfObj.data.measurementList(1,100).copy;
                measurementListWl2.detectorIndex = 17;

                measurementListTmp(1, 1:51) = [snirfObj.data.measurementList(1,1:50), measurementListWl1];
                measurementListTmp(1, 52:102) = [snirfObj.data.measurementList(1,51:100), measurementListWl2];
                snirfObj.data.measurementList = measurementListTmp;

                intensity = snirfObj.data.GetDataTimeSeries();
                [~, col1] = find(intensity(:,1:50)==max(intensity(:,1:50),[],'all'));
                [~, col2] = find(intensity(:,51:100)==max(intensity(:,51:100),[],'all'));
                newIntensity = [intensity(:,1:50),...
                    intensity(:,col1),...
                    intensity(:,51:100),...
                    intensity(:,col2)];
                snirfObj.data.SetDataTimeSeries(newIntensity);
                snirfObj.Save(fullfile(cfg.savepath_snirf, subjectFolder{ii}, snirffilelist{jj}));
            end

            odSSAvgW1 = mean(odRearrange(:,lstSS),2) * 2 / 19;
            odSSAvgW2 = mean(odRearrange(:, 50 + lstSS),2) * 2 / 19;
            for tt = 1:length(T)
                dA = T{tt};
                mlActAuto{1,1} = ones(100,1);
                odHRF = generateHRF(brainVertices, scalpVertices, indexPerturbation,unilateralDataPath,dA,mlActAuto,cfg.scale_factor);
                odHRF = odHRF';
                OD = odRearrange + odHRF;
                OD = [OD(:, 1:50), ...
                    odSSAvgW1,...
                    OD(:, 51:100),...
                    odSSAvgW2];

                stimTs = stim{tt};
                stimTime = t(stimTs == 1);
                stimMat = zeros(length(stimTime),3);
                stimMat(:,1) = stimTime;
                stimMat(:,2) = 10*ones(length(stimTime),1);
                stimMat(:,3) = ones(length(stimTime),1);

                savedData = struct();
                savedData.OD = OD;
                savedData.stim_mat = stimMat;
                save(fullfile(cfg.savepath_rs,subjectFolder{ii},[snirffilelist{jj}(1:end-6) '_', int2str(tt),'.mat']),'-struct','savedData');

                OD = [odHRF(:,1:50), ...
                    zeros(size(odSSAvgW1)),...
                    odHRF(:,51:100),...
                    zeros(size(odSSAvgW2))];
                savedData = struct();
                savedData.OD = OD;
                savedData.stim_mat = stimMat;
                save(fullfile(cfg.savepath_zeros,'Subject', ['Subject_', int2str(tt),'.mat']),'-struct','savedData');
            end
        end
    end
end

function tbasis = buildHrfBasis(dt)
    nB = 1; % one gamma basis
    trange = [-2, 18];
    nPre = round(trange(1)/dt);
    nPost = round(trange(2)/dt);
    tHRF = (1*nPre*dt:dt:nPost*dt)';
    ntHRF = length(tHRF);
    nConc = 2; % HbO and HbR
    tbasis = zeros(ntHRF,nB,nConc);
    paramsBasis = [0.1 3 7 0.1 3 7];
    for iConc = 1:nConc
        tau = paramsBasis((iConc-1)*3+1);
        sigma = paramsBasis((iConc-1)*3+2);
        T = paramsBasis((iConc-1)*3+3);

        tbasis(:,1,iConc) = (exp(1)*(tHRF-tau).^2/sigma^2) .* exp( -(tHRF-tau).^2/sigma^2 );
        lstNeg = find(tHRF<0);
        tbasis(lstNeg,1,iConc) = 0;

        if tHRF(1)<tau
            tbasis(1:round((tau-tHRF(1))/dt),1,iConc) = 0;
        end

        if T>0
            for ii=1:nB
                foo = conv(tbasis(:,ii,iConc),ones(round(T/dt),1)) / round(T/dt);
                tbasis(:,ii,iConc) = foo(1:ntHRF,1);
            end
        end
    end
end

function [Amatrix,stim] = buildStimulusDesign(nT,dt,tbasis,sequenceFile)

    storedData = load(sequenceFile,'index','task_mat','rest_mat');
    index = storedData.index;
    taskMat = storedData.task_mat;
    restMat = storedData.rest_mat;
    % for each resting state run, we are simulating three types of stimulus sequences
    n = 3;
    nCond = 1;% we are using only one type of stimulus
    nB = 1; % one gamma basis

    for i = 1:n
        taskArray = taskMat(index(i),:);
        restArray = restMat(index(i),:);
        % build onset time
        onset = zeros(nT,nCond);
        timePoint = 5/dt;
        for j = 1:length(taskArray)
            if j == 1
                onset(round(timePoint)) = 1;
            else
                timePoint = timePoint + 5/dt + restArray(j)/dt;
                onset(round(timePoint)) = 1;
            end
        end
        % calculate dA
        dA=zeros(nT,nB*nCond,2);
        for iConc = 1:2
            iC = 0;
            for iCond=1:nCond
                for b=1:nB
                    iC = iC + 1;
                    if size(tbasis,3)==1
                        clmn = conv(onset(:,iCond),tbasis(:,b));
                    else
                        clmn = conv(onset(:,iCond),tbasis(:,b,iConc));
                    end
                    clmn = clmn(1:nT);
                    dA(:,iC,iConc) = clmn;
                    onset = onset(1:nT);
                end
            end
        end
        Amatrix{i} = dA;
        stim{i} = onset;
    end
end


function odHRF = generateHRF(brainVertices,scalpVertices, indexPerturbation,acquiredPath,dA,mlActAuto, scaleFactor)
    %% building b matrix
    g = zeros(size(brainVertices,1),1);
    g(indexPerturbation) = 1;
    % scale_factor = 1e-2; % for HbO, max activation = 0.4*scale_factor
    bBrainHbO = kron(g,squeeze(dA(:,:,1))'*scaleFactor); % the max of dA is 0.4, so the max activation is 0.4e-3 here
    bBrainHbR = kron(g,squeeze(dA(:,:,2))'*(-0.5*scaleFactor));
    bScalpHbO = zeros(size(scalpVertices,1),size(dA,1));
    bScalpHbR = zeros(size(scalpVertices,1),size(dA,1));

    %% building A matrix
    rhoSDSsThresh = 0;
    sensitivityConfig = ssdot.app.defaultConfig();
    sensitivityConfig.longSeparationThreshold = rhoSDSsThresh;
    sensitivityConfig.spatialRegularization = false;
    sensitivityMatrix = ssdot.io.loadSensitivity(acquiredPath,mlActAuto,sensitivityConfig);
    E = sensitivityMatrix.E;
    Adot = sensitivityMatrix.Adot_orig;
    adotScalp = sensitivityMatrix.Adot_scalp_orig;

    Adot = double(Adot);
    adotScalp = double(adotScalp);
    A = ssdot.recon.buildForwardMatrix(Adot, adotScalp, E,  []);

    amatrixBrain = A.Amatrix_brain;
    amatrixScalp = A.Amatrix_scalp;

    %% calculate x matrix
    ABrain = [amatrixBrain.w1_HbO,amatrixBrain.w1_HbR;...
        amatrixBrain.w2_HbO,amatrixBrain.w2_HbR];
    AScalp = [amatrixScalp.w1_HbO,amatrixScalp.w1_HbR;...
        amatrixScalp.w2_HbO,amatrixScalp.w2_HbR];
    odHRF = [ABrain, AScalp] * [bBrainHbO; bBrainHbR; bScalpHbO; bScalpHbR ];

end

function visualizePerturbation(cfg,atlasViewer,brainVertices,indexPerturbation,scaleFactor)

    h = figure('name','perturbation_HbO');
    axesOrder = [2,1,3];
    intensity = zeros(size(brainVertices,1),1);
    intensity(indexPerturbation) = 0.4*scaleFactor;
    faces = atlasViewer.fwmodel.mesh.faces;
    trisurf(faces, brainVertices(:,axesOrder(1)), brainVertices(:,axesOrder(2)), brainVertices(:,axesOrder(3)), ...
        intensity,'facecolor','interp','edgealpha',0, 'visible','on');
    view(-90,0)
    camtarget([128.0, 132.0, 130.0])
    campos([128.0, 2238.8, 130.0])
    camup([-1.0, 0.0, 0.0])
    caxis([-1 1]*0.5*scaleFactor)
    title('HbO')
    set(gcf,'position',[ 10         10         399         235])
    axis image
    if(~exist('light_onoff') | (exist('light_onoff') & strcmp(lightOnoff,'on')))
        l = camlight;
        set(l,'Position',[50 2000 100]);

        l2 = camlight;
        set(l2,'Position',[50 -100 -100]);

        camlight(0,0);
    end
    lighting phong;
    myColorMap = jet(256);
    myColorMap(127:129,:) = 0.8;
    colormap(myColorMap);
    colorbar
    hold on

    savefig([cfg.savepath_rs,filesep,'pertubation_HbO.fig'])
    close(h)

    h = figure('name','perturbation_HbR');
    axesOrder = [2,1,3];
    intensity = zeros(size(brainVertices,1),1);
    intensity(indexPerturbation) = -0.4*0.5*scaleFactor;
    faces = atlasViewer.fwmodel.mesh.faces;
    trisurf(faces, brainVertices(:,axesOrder(1)), brainVertices(:,axesOrder(2)), brainVertices(:,axesOrder(3)), ...
        intensity,'facecolor','interp','edgealpha',0, 'visible','on');
    view(-90,0)
    camtarget([128.0, 132.0, 130.0])
    campos([128.0, 2238.8, 130.0])
    camup([-1.0, 0.0, 0.0])
    caxis([-1 1]*0.5*scaleFactor)
    title('HbR')
    set(gcf,'position',[ 10         10         399         235])
    axis image
    if(~exist('light_onoff') | (exist('light_onoff') & strcmp(lightOnoff,'on')))
        l = camlight;
        set(l,'Position',[50 2000 100]);

        l2 = camlight;
        set(l2,'Position',[50 -100 -100]);

        camlight(0,0);
    end
    lighting phong;
    myColorMap = jet(256);
    myColorMap(127:129,:) = 0.8;
    colormap(myColorMap);
    colorbar

    savefig([cfg.savepath_rs,filesep,'pertubation_HbR.fig'])
    close(h)

end
