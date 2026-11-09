function tests = testRoi()
    tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'src')); ssdot.app.initializeEnvironment();
end
function testSelectionRetainsIndependentNonRoiRule(t)
    vertices = [0 0 0;1 0 0;10 0 0;50 0 0;60 0 0];
    [hits,background] = ssdot.recon.findRoi([10;.01;.02;.01;0],zeros(5,1), ...
        struct('mask_brain',(1:5)'),vertices,.9,.01,40,struct('original_ROI',0));
    verifyEqual(t,hits,1); verifyEqual(t,background,[4;5]);
    verifyNotEqual(t,background,setdiff((1:5)',hits));
    % Geometric centers use the historical display order [2 1 3] and radius 15.
    vertices = [100 0 0;0 100 0;100 0 16;100 0 14];
    [hits,background] = ssdot.recon.findRoi(zeros(4,1),zeros(4,1), ...
        struct('mask_brain',(1:4)'),vertices,.9,.01,40,struct('original_ROI',1,'center',[0 100 0]));
    verifyEqual(t,hits,[1;4]); verifyEqual(t,background,[2;3]);
end
function testMeshIndexAndFrameValidation(t)
    surface = smallSurface();
    roi = ssdot.io.roiFromIndices(surface,[1 2],4,'fixture ROI');
    verifyEqual(t,roi.indices,[1;2]);
    logicalRoi = ssdot.io.roiFromIndices(surface,[true false false true],[],'logical fixture');
    verifyEqual(t,logicalRoi.indices,[1;4]);
    for bad = {[0 1],[1 5],[1 1],[1 NaN],[1 1.5]}
        verifyError(t,@()ssdot.io.roiFromIndices(surface,bad{1},[],'invalid'),'SSDOT:RoiIndex');
    end
    other = surface; other.vertices(1,1) = 2; other.meshId = ssdot.io.meshIdentity(other.vertices,other.faces);
    verifyError(t,@()ssdot.viz.validateRoi(roi,other),'SSDOT:RoiMesh');
    roi.units = "cm";
    verifyError(t,@()ssdot.viz.validateRoi(roi,surface),'SSDOT:RoiCoordinates');
end
function testNeutralCoordinateDistance(t)
    a = struct('coordinates',[0 0 0],'coordinateSystem',"known frame",'units',"mm");
    b = a; b.coordinates = [3 4 0];
    value = ssdot.recon.coordinateDistance(a,b);
    verifyEqual(t,value.value,5); verifyEqual(t,value.label,"Coordinate distance");
    b.coordinateSystem = "other frame";
    verifyError(t,@()ssdot.recon.coordinateDistance(a,b),'SSDOT:CoordinateMismatch');
end
function testSingleAndComparisonRenderWithoutAccumulation(t)
    surface = smallSurface();
    a = ssdot.io.roiFromIndices(surface,1,3,'first fixture');
    b = ssdot.io.roiFromIndices(surface,2,4,'second fixture');
    fig = figure('Visible','off'); t.addTeardown(@()delete(fig));
    left = subplot(1,2,1,'Parent',fig); right = subplot(1,2,2,'Parent',fig);
    h = ssdot.viz.plotRoi(left,surface,a);
    verifyEqual(t,h.roi.XData,surface.vertices(1,2));
    verifyEqual(t,h.surface.FaceAlpha,0.12);
    verifyEqual(t,h.surface.FaceColor,[0.4 0.4 0.4]);
    verifyEmpty(t,findall(fig,'Type','colorbar')); % ROI colors do not encode amplitude.
    ssdot.viz.plotRoi(left,surface,a);
    verifyEqual(t,numel(findall(left,'Type','patch')),1);
    ssdot.viz.plotRoiComparison(left,right,surface,a,b,"sideBySide");
    verifyEqual(t,numel(findall(right,'Type','patch')),1);
    ssdot.viz.plotRoiComparison(left,right,surface,a,b,"overlay");
    verifyEqual(t,numel(findall(left,'Type','line')),4);
    verifyEmpty(t,findall(right,'Type','patch')); drawnow;
end
function testLegacyAssociationAndCanonicalRoundTrip(t)
    surface = smallSurface();
    fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    filename = fullfile(fixture.Folder,'legacy.mat');
    index_ROI = [1;2]; index_nonROI = 4; save(filename,'index_ROI','index_nonROI');
    verifyError(t,@()ssdot.io.readRoi(filename,surface),'SSDOT:UnassociatedRoi');
    roi = ssdot.io.readRoi(filename,surface,true);
    verifyEqual(t,roi.indices,index_ROI); verifyEqual(t,roi.nonRoiIndices,index_nonROI);
    filename = fullfile(fixture.Folder,'canonical.mat'); ssdot.io.saveRoi(filename,roi,surface);
    verifyEqual(t,ssdot.io.readRoi(filename,surface),roi);
end
function testGuiSingleRoiNeedsNoReconstructionOrComparison(t)
    root = fileparts(fileparts(mfilename('fullpath'))); addpath(root);
    app = main(); t.addTeardown(@()delete(app)); app.figure.Visible = 'off';
    group = app.loadDataset(fullfile(root,'ST001'),false);
    state = app.controller.stateForNode(group.subjs(1).sess(1).runs(1));
    app.controller.loadAtlas(state,fullfile(root,'ST001','atlasViewer.mat'));
    viewer = app.controller.openRoiViewer(state); viewer.figure.Visible = 'off';
    verifyEmpty(t,state.rois); verifyEmpty(t,state.result);
    roi = ssdot.io.roiFromIndices(viewer.surface,[1;2],3,'single ROI fixture'); viewer.addRoi(roi);
    verifyEqual(t,numel(state.rois),1); verifyEqual(t,viewer.mode.Value,'single');
    verifyEqual(t,string(viewer.mode.Enable),"off"); verifyEqual(t,string(viewer.secondSelection.Enable),"off");
    verifyEqual(t,viewer.firstSelection.Value,1);
    roi.label = "second compatible fixture"; roi.indices = 4; viewer.addRoi(roi);
    viewer.secondSelection.Value = 1; viewer.mode.Value = 'sideBySide'; viewer.refresh();
    verifyEqual(t,string(viewer.mode.Enable),"on");
    viewer.mode.Value = 'overlay'; viewer.refresh();
    verifyEqual(t,numel(findall(viewer.firstAxes,'Type','patch')),1);
    viewer.vertexInputs(1).Value = 1; viewer.vertexInputs(2).Value = 2;
    distance = viewer.measureDistance();
    verifyEqual(t,distance.value,norm(viewer.surface.vertices(1,:)-viewer.surface.vertices(2,:)));
    viewer.meshSelection.Value = 'pial'; viewer.changeMesh();
    verifySize(t,viewer.surface.vertices,[34207 3]); verifyEmpty(t,viewer.compatibleIndices);
    verifyEqual(t,viewer.firstSelection.Value,0);
    verifyTrue(t,contains(string(viewer.status.Text),'No ROI is defined'));
    verifyEqual(t,string(viewer.calculateButton.Enable),"off");
    % A session preserves both explicit mesh associations, never remaps the indices.
    pial = ssdot.io.roiFromIndices(viewer.surface,34207,[],'full-pial fixture'); viewer.addRoi(pial);
    fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    filename = fullfile(fixture.Folder,'rois.mat'); ssdot.io.saveSession(filename,state);
    other = ssdot.app.ReconstructionState(); other.nodeName = state.nodeName; other.datasetRoot = state.datasetRoot;
    ssdot.io.restoreSession(filename,other); verifyEqual(t,other.rois,state.rois);
    drawnow;
end
function surface = smallSurface()
    vertices = [0 0 0;1 0 0;0 1 0;0 0 1]; faces = [1 2 3;1 2 4;1 3 4;2 3 4];
    surface = struct('vertices',vertices,'faces',faces,'meshId',ssdot.io.meshIdentity(vertices,faces), ...
        'coordinateSystem',"fixture",'units',"mm",'name',"fixture mesh");
end
