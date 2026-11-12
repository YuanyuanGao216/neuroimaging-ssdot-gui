function tests=testNormalization()
    tests=functiontests(localfunctions);
end
function setupOnce(~)
    root=fileparts(fileparts(mfilename('fullpath')));addpath(root);addpath(fullfile(root,'src'));ssdot.app.initializeEnvironment();
end
function testSensitivityNormalizationMatchesProfessorLastWavelengthAndCache(t)
    ml=[1 1 1 1;1 2 1 1;1 1 1 2;1 2 1 2];
    probe=struct('measurementList',ml,'active',ones(4,1),'wavelengths',[760 850], ...
        'sourcePositions',[0 0 0],'detectorPositions',[10 0 0;20 0 0]);
    brain=reshape(single(1:16),2,4,2);scalp=reshape(single(2:13),2,3,2);
    raw=struct('probe',probe,'brain',brain,'scalp',scalp,'cached',[]);
    cfg=ssdot.app.defaultConfig();cfg.longSeparationThreshold=0;cfg.sensitivityThreshold=-100;cfg.spatialRegularization=true;
    s=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    [expectedB,ll]=originalScaling(brain);[expectedS,llScalp]=originalScaling(scalp);
    verifyEqual(t,s.Adot,expectedB);verifyEqual(t,s.Adot_scalp,expectedS);
    verifyEqual(t,s.ll,ll);verifyEqual(t,s.ll_scalp,llScalp);
    raw.cached=struct('brain',expectedB,'scalp',expectedS,'brainScaling',ll,'scalpScaling',llScalp);
    cached=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    verifyEqual(t,cached.Adot,s.Adot);verifyEqual(t,cached.Adot_scalp,s.Adot_scalp);verifyEqual(t,cached.ll,s.ll);
    cfg.spatialRegularization=false;unscaled=ssdot.recon.prepareSensitivity(raw,ones(4,1),cfg);
    verifyEqual(t,unscaled.Adot,brain);verifyEqual(t,unscaled.Adot_scalp,scalp);verifyFalse(t,isfield(unscaled,'ll'));
end
function [a,lastScale]=originalScaling(a)
    for w=1:size(a,3)
        x=a(:,:,w);v=sum(x.^2,1);lastScale=sqrt(v+.1*max(v));a(:,:,w)=x./lastScale;
    end
end