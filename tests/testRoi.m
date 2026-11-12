function tests = testRoi()
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src'));
    ssdot.app.initializeEnvironment();
end

function testSelectionRetainsIndependentNonRoiRule(t)
    vertices = [0 0 0; 1 0 0; 10 0 0; 50 0 0; 60 0 0];
    [hits, background] = ssdot.recon.findRoi([10; .01; .02; .01; 0], zeros(5, 1), ...
        struct('mask_brain', (1:5)'), vertices, .9, .01, 40, struct('original_ROI', 0));
    verifyEqual(t, hits, 1);
    verifyEqual(t, background, [4; 5]);
    verifyNotEqual(t, background, setdiff((1:5)', hits));

    % Geometric centers use the historical display order [2 1 3] and radius 15.
    vertices = [100 0 0; 0 100 0; 100 0 16; 100 0 14];
    [hits, background] = ssdot.recon.findRoi(zeros(4, 1), zeros(4, 1), ...
        struct('mask_brain', (1:4)'), vertices, .9, .01, 40, struct('original_ROI', 1, 'center', [0 100 0]));
    verifyEqual(t, hits, [1; 4]);
    verifyEqual(t, background, [2; 3]);
end

function testMeshIndexAndFrameValidation(t)
    surface = smallSurface();

    roi = ssdot.io.roiFromIndices(surface, [1 2], 4, 'fixture ROI');
    verifyEqual(t, roi.indices, [1; 2]);
    logicalRoi = ssdot.io.roiFromIndices(surface, [true false false true], [], 'logical fixture');
    verifyEqual(t, logicalRoi.indices, [1; 4]);

    for invalid = {[0 1], [1 5], [1 1], [1 NaN], [1 1.5]}
        verifyError(t, @() ssdot.io.roiFromIndices(surface, invalid{1}, [], 'invalid'), 'SSDOT:RoiIndex');
    end

    other = surface;
    other.vertices(1, 1) = 2;
    other.meshId = ssdot.io.meshIdentity(other.vertices, other.faces);
    verifyError(t, @() ssdot.viz.validateRoi(roi, other), 'SSDOT:RoiMesh');

    roi.units = "cm";
    verifyError(t, @() ssdot.viz.validateRoi(roi, surface), 'SSDOT:RoiCoordinates');
end

function testNeutralCoordinateDistance(t)
    origin = struct('coordinates', [0 0 0], 'coordinateSystem', "known frame", 'units', "mm");
    point = origin;
    point.coordinates = [3 4 0];

    distance = ssdot.recon.coordinateDistance(origin, point);
    verifyEqual(t, distance.value, 5);
    verifyEqual(t, distance.label, "Coordinate distance");

    point.coordinateSystem = "other frame";
    verifyError(t, @() ssdot.recon.coordinateDistance(origin, point), 'SSDOT:CoordinateMismatch');
end

function testLegacyAssociationAndCanonicalRoundTrip(t)
    surface = smallSurface();
    fixture = t.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
    filename = fullfile(fixture.Folder, 'legacy.mat');

    % Variable names of the legacy ROI file format.
    index_ROI = [1; 2];
    index_nonROI = 4;
    save(filename, 'index_ROI', 'index_nonROI');

    verifyError(t, @() ssdot.io.readRoi(filename, surface), 'SSDOT:UnassociatedRoi');
    roi = ssdot.io.readRoi(filename, surface, true);
    verifyEqual(t, roi.indices, index_ROI);
    verifyEqual(t, roi.nonRoiIndices, index_nonROI);

    filename = fullfile(fixture.Folder, 'canonical.mat');
    ssdot.io.saveRoi(filename, roi, surface);
    verifyEqual(t, ssdot.io.readRoi(filename, surface), roi);
end

function surface = smallSurface()
    vertices = [0 0 0; 1 0 0; 0 1 0; 0 0 1];
    faces = [1 2 3; 1 2 4; 1 3 4; 2 3 4];
    surface = struct('vertices', vertices, 'faces', faces, 'meshId', ssdot.io.meshIdentity(vertices, faces), ...
        'coordinateSystem', "fixture", 'units', "mm", 'name', "fixture mesh");
end
