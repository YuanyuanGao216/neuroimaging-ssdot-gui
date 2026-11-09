function observations = buildObservations(recording,S,probe,T,config)
    %PREPARE_OD_DATA Stack OD and build sparse SS/drift regressors.
    OD=recording.od;
    channels=S.channels(:);
    [nTime,nMeasurements]=size(OD);
    nPairs=nMeasurements/2;
    SD=struct('MeasList',probe.measurementList,'MeasListAct',probe.active, ...
        'SrcPos',probe.sourcePositions,'DetPos',probe.detectorPositions);
    assert(size(SD.MeasList,1)==nMeasurements,'SSDOT:MeasurementCount', ...
        'Atlas and recording measurement counts differ.');
    observations.od=struct('w1',OD(:,channels)','w2',OD(:,nPairs+channels)');
    observations.response=[reshape(OD(:,channels)',[],1);reshape(OD(:,nPairs+channels)',[],1)];
    active=ssdot.recon.activeMeasurements(recording.activeMeasurements,nMeasurements);
    active=active(1:nPairs) & active(nPairs+(1:nPairs));
    ml=SD.MeasList(1:nPairs,:);
    distance=sqrt(sum((SD.SrcPos(ml(:,1),:)-SD.DetPos(ml(:,2),:)).^2,2));
    short=find(active & SD.MeasListAct(1:nPairs)==1 & distance<config.shortSeparationThreshold);
    assert(~isempty(short),'SSDOT:NoShortChannels', ...
        'No active short-separation channels remain below 22 mm. Check channel pruning and probe geometry.');
    nLong=numel(channels);
    short1=mean(OD(:,short),2); short2=mean(OD(:,nPairs+short),2);
    SS1=kron(sparse(short1),speye(nLong));
    SS2=kron(sparse(short2),speye(nLong));
    observations.shortRegressors=blkdiag(SS1,SS2);

    assert(size(T.T_HbO_brain,1)==nTime,'SSDOT:TemporalSize', ...
        'Generate a temporal basis for the current recording before preparing OD.');
    D=ssdot.recon.buildDriftMatrix(T,config.driftOrder);
    block=kron(sparse(D),speye(nLong));
    % Keep the original channel-major ordering of nuisance coefficients.
    order=reshape(reshape(1:nLong*size(D,2),nLong,[])',1,[]);
    block=block(:,order);
    observations.driftRegressors=blkdiag(block,block);
    % Exact factors of the existing sparse regressors, used for orthogonal compression.
    observations.nuisanceTemporal=struct('short',{{short1,short2}},'drift',D);
end
