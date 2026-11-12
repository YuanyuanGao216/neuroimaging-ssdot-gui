function tests = testStatistics()
    tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src'));
end
function testTwoRecordingsMatchClosedForm(t)
    % n = 2, values 1 and 3: mean 2, standard error 1, t = 2, df = 1.
    % For df = 1 the two-sided p is 1 - 2*atan(|t|)/pi.
    results = struct('hbo',{[1;-1;0],[3;-3;0]},'hbr',{[0;5;2],[0;7;2]});
    stats = ssdot.recon.groupStatistics(results);
    verifyEqual(t,stats.recordings,2); verifyEqual(t,stats.degreesOfFreedom,1);
    verifyEqual(t,stats.hbo.t(1:2),[2;-2],'AbsTol',1e-12);
    verifyEqual(t,stats.hbo.p(1:2),(1-2*atan(2)/pi)*[1;1],'AbsTol',1e-12);
    verifyTrue(t,isnan(stats.hbo.t(3)) && isnan(stats.hbo.p(3)),'No variation: t and p are undefined.');
    verifyEqual(t,stats.hbr.t(2),6,'AbsTol',1e-12);
    verifyTrue(t,isnan(stats.hbr.t(1)) && isnan(stats.hbr.t(3)),'Identical nonzero values have no defined t.');
end
function testThreeRecordingsMatchClosedFormAndToolbox(t)
    % df = 2: two-sided p = 1 - |t|/sqrt(2 + t^2).
    rng(7); values = randn(50,2,3)*1e-9 + 0.5e-9;
    results = struct('hbo',squeeze(num2cell(values,[1 2])),'hbr',squeeze(num2cell(-values,[1 2])));
    stats = ssdot.recon.groupStatistics(results);
    expectedT = mean(values,3)./(std(values,0,3)/sqrt(3));
    verifyEqual(t,stats.hbo.t,expectedT,'RelTol',1e-12);
    verifyEqual(t,stats.hbr.t,-expectedT,'RelTol',1e-12);
    verifyEqual(t,stats.hbo.p,1-abs(expectedT)./sqrt(2+expectedT.^2),'AbsTol',1e-12);
    verifyEqual(t,stats.hbr.p,stats.hbo.p,'AbsTol',1e-15);
    if exist('ttest','file')==2
        [~,p,~,detail] = ttest(squeeze(values(7,1,:)));
        verifyEqual(t,stats.hbo.p(7,1),p,'AbsTol',1e-12); verifyEqual(t,stats.hbo.t(7,1),detail.tstat,'RelTol',1e-12);
    end
end
function testRejectsTooFewOrMismatchedRecordings(t)
    one = struct('hbo',ones(4,1),'hbr',ones(4,1));
    verifyError(t,@()ssdot.recon.groupStatistics(one),'SSDOT:StatisticsCount');
    mismatched = struct('hbo',{ones(4,1),ones(5,1)},'hbr',{ones(4,1),ones(4,1)});
    verifyError(t,@()ssdot.recon.groupStatistics(mismatched),'SSDOT:ResultSize');
end
function testDisplayIsNeutralForUndefinedValuesAndGraysNonSignificantP(t)
    shown = ssdot.viz.statisticDisplay("t",[NaN;-4;2],[]);
    verifyEqual(t,shown.values,[0;-4;2]); verifyEqual(t,shown.limits,[-4 4]); verifyEqual(t,shown.undefined,1);
    verifyEqual(t,ssdot.viz.statisticDisplay("t",[1;2],3).limits,[-3 3]);
    shown = ssdot.viz.statisticDisplay("p",[0.01;NaN;0.2],0.05);
    verifyEqual(t,shown.values,[0.01;1;0.2]);
    verifyEqual(t,size(shown.colors),[256 3]); verifyEqual(t,shown.colors(end,:),[0.8 0.8 0.8]);
    % The significance level is exactly where the gray (last) color starts.
    index = @(p)min(256,floor((p-shown.limits(1))/diff(shown.limits)*256)+1);
    verifyEqual(t,index(0.0499),255); verifyEqual(t,index(0.0501),256);
    rejected = false;
    try, ssdot.viz.statisticDisplay("p",0.1,2); catch, rejected = true; end
    verifyTrue(t,rejected,'Significance above 1 is rejected.');
end
function testAverageConditionsAreMatchedByName(t)
    [common,columns,omitted] = ssdot.app.matchConditions({{'A','B'},{'B','A','0'}},["r1" "r2"]);
    verifyEqual(t,common,["A" "B"]); verifyEqual(t,columns,{[1 2],[2 1]});
    verifyEqual(t,omitted,"condition 0 of r2");
    [common,columns] = ssdot.app.matchConditions({{},{}},["r1" "r2"]);
    verifyEmpty(t,common); verifyEqual(t,columns,{[],[]},'Unnamed results are matched by position.');
    verifyError(t,@()ssdot.app.matchConditions({{'A'},{'B'}},["r1" "r2"]),'SSDOT:AverageConditions');
    verifyError(t,@()ssdot.app.matchConditions({{'A'},{}},["r1" "r2"]),'SSDOT:AverageConditions');
end
