% Direct, limited comparison against the unmodified professor checkout.
% Run: MATLAB -batch "run('research/compareProfessorOriginal.m')"
% The full explicit design does not fit 16 GiB. Selected direct design blocks
% and an original inverse supplied with full compressed normal equations are
% distinguished in the report. No historical simulation data are substituted.

%% Locate and verify the unmodified original checkout
root = fileparts(fileparts(mfilename('fullpath')));
reference = getenv('SSDOT_PROFESSOR_ROOT');
if isempty(reference)
    reference = fullfile(fileparts(root), 'SSDOT');
end
commit = '31bb4206dc55bbe9b67030864629b76554b62aec';

[ok, head] = system(sprintf('git -C "%s" rev-parse HEAD', reference));
assert(ok == 0 && strcmp(strtrim(head), commit), 'Unexpected original checkout.');
[ok, status] = system(sprintf('git -C "%s" status --porcelain', reference));
assert(ok == 0 && isempty(strtrim(status)), 'Original checkout has modifications.');

addpath(fullfile(root, 'src'));
ssdot.app.initializeEnvironment(root);
addpath(fullfile(reference, 'code'), '-begin');
originalCode = string(fullfile(reference, 'code'));
assert(startsWith(string(which('Proc_stream_v7')), originalCode, 'IgnoreCase', true));

folder = fullfile(root, 'results', 'validation', 'professor-original-comparison');
if ~isfolder(folder)
    mkdir(folder);
end

%% Current model for the first ST001 recording
data = ssdot.validation.loadSt001(fullfile(root, 'datasets', 'ST001'), @(~, ~, ~) []);
cfg = ssdot.app.defaultConfig();
p = ssdot.validation.prepareModel(data.records(1).recording, data.rawModel, data.atlas, cfg, @(~, ~, ~) []);
S = p.sensitivity;
G = p.model.spatialBasis;
T = p.model.temporalBasis;
metrics = struct('name', {}, 'maxAbs', {}, 'relativeFrobenius', {}, 'correlation', {});

%% Sensitivity, masks and forward operators
fprintf('Comparing original sensitivity, masks and forward operators.\n');
measurementCount = size(p.probe.measurementList, 1);
activity = {double(ssdot.recon.activeMeasurements(p.recording.activeMeasurements, measurementCount))};
originalS = Get_A_dot([char(fullfile(root, 'datasets', 'ST001')) filesep], cfg.longSeparationThreshold, activity, false);
fprintf('Original/current channel counts: %d / %d; original missing: %s; extra: %s\n', ...
    numel(originalS.channels), numel(S.channels), ...
    mat2str(setdiff(S.channels, originalS.channels)'), mat2str(setdiff(originalS.channels, S.channels)'));
metrics(end + 1) = comparison('sensitivity brain', originalS.Adot, S.Adot);
metrics(end + 1) = comparison('sensitivity scalp', originalS.Adot_scalp, S.Adot_scalp);
metrics(end + 1) = comparison('active channels', originalS.channels, S.channels);
metrics(end + 1) = comparison('extinction', originalS.E, S.E);

originalM = Make_mask(cfg.sensitivityThreshold, originalS.Adot_orig, originalS.Adot_scalp_orig);
metrics(end + 1) = comparison('brain mask', originalM.mask_brain, S.M.mask_brain);
metrics(end + 1) = comparison('scalp mask', originalM.mask_scalp, S.M.mask_scalp);

originalA = Make_A_matrix(originalS.Adot, originalS.Adot_scalp, originalS.E, originalM);
fprintf('Sensitivity class: original %s, current %s; extinction: %s\n', ...
    class(originalS.Adot), class(S.Adot), mat2str(originalS.E));
forwardFields = {'w1_HbO', 'w1_HbR', 'w2_HbO', 'w2_HbR'};
for tissue = {'brain', 'scalp'}
    block = ['Amatrix_' tissue{1}];
    for field = forwardFields
        name = field{1};
        metrics(end + 1) = comparison(['forward ' tissue{1} ' ' name], originalA.(block).(name), S.A.(block).(name));
    end
end

%% Temporal and drift bases
proc = struct('dA', cat(3, T.T_HbO_brain, T.T_HbR_brain), 'tbasis', cat(3, T.t_HbO_brain, T.t_HbR_brain), ...
    'stim', repmat(struct(), 1, T.nConditions));
originalT = Make_T_matrix(proc);
for field = {'T_HbO_brain', 'T_HbR_brain', 't_HbO_brain', 't_HbR_brain', 'T_HbO_scalp', 'T_HbR_scalp'}
    name = field{1};
    metrics(end + 1) = comparison(['temporal ' name], originalT.(name), T.(name));
end
currentDrift = ssdot.recon.buildDriftMatrix(T, cfg.driftOrder);
metrics(end + 1) = comparison('drift basis', make_D(originalT, cfg.driftOrder), currentDrift);

%% Gaussian kernels on a vertex subset
% Exact professor kernels allocate an N-by-N temporary; a representative
% 256-vertex subset is used without changing sigma or normalization.
vertices = data.atlas.fwmodel.mesh.vertices(S.M.mask_brain, :);
vertices = vertices(1:min(256, end), :);
centersOriginal = down_sample_vertices(vertices, cfg.brainSamplingThreshold);
centersCurrent = ssdot.recon.downsampleVertices(vertices, cfg.brainSamplingThreshold);
metrics(end + 1) = comparison('kernel centers subset', centersOriginal, centersCurrent);
kernelOriginal = make_kernel_matrix_gpu(centersOriginal, vertices, cfg.brainSigma);
kernelCurrent = ssdot.recon.buildGaussianKernels(centersCurrent, vertices, cfg.brainSigma, 'cpu');
metrics(end + 1) = comparison('Gaussian kernels subset', kernelOriginal, kernelCurrent);

%% Design blocks on sampled kernels and times
fprintf('Comparing direct original design blocks.\n');
times = unique(round(linspace(1, numel(p.recording.time), 32)));
smallT = originalT;
for field = {'T_HbO_brain', 'T_HbR_brain', 'T_HbO_scalp', 'T_HbR_scalp'}
    name = field{1};
    smallT.(name) = originalT.(name)(times, :);
end
smallG = struct('G_brain', sampleKernels(G.G_brain), 'G_scalp', sampleKernels(G.G_scalp));
nChannels = numel(S.channels);
smallY = zeros(2 * nChannels * numel(times), 1);

[originalBrainDesign, originalScalpDesign] = make_H_matrix(originalA, smallG, smallT, smallY, 'cpu', struct());
[currentBrainDesign, currentScalpDesign] = designBlocks(S.A, smallG, smallT, numel(smallY));
metrics(end + 1) = comparison('brain design sampled kernels and times', originalBrainDesign, currentBrainDesign);
metrics(end + 1) = comparison('scalp design sampled kernels and times', originalScalpDesign, currentScalpDesign);

% Normal equations from the identical original design block.
probe = sin((1:numel(smallY))' / 31);
[originalVector, originalNormal] = make_HTY_and_HTH(originalBrainDesign, originalScalpDesign, [], [], probe, 1024, 'cpu', []);
originalDesign = [originalBrainDesign originalScalpDesign];
currentVector = originalDesign' * probe;
currentNormal = originalDesign' * originalDesign;
metrics(end + 1) = comparison('normal matrix from identical original design block', originalNormal, currentNormal);
metrics(end + 1) = comparison('normal vector from identical original design block', originalVector, currentVector);

% The professor's CPU matrix multiplication retains native single sensitivity
% precision; compare again after both implementations receive double inputs.
doubleA = originalA;
for tissue = {'brain', 'scalp'}
    block = ['Amatrix_' tissue{1}];
    for field = forwardFields
        name = field{1};
        doubleA.(block).(name) = double(doubleA.(block).(name));
    end
end
[hbDouble, hsDouble] = make_H_matrix(doubleA, smallG, smallT, smallY, 'cpu', struct());
[hbCurrentDouble, hsCurrentDouble] = designBlocks(doubleA, smallG, smallT, numel(smallY));
metrics(end + 1) = comparison('brain design matched double', hbDouble, hbCurrentDouble);
metrics(end + 1) = comparison('scalp design matched double', hsDouble, hsCurrentDouble);
clear originalBrainDesign originalScalpDesign currentBrainDesign currentScalpDesign originalDesign
clear originalS originalA kernelOriginal kernelCurrent

%% Saved noiseless synthetic cases
% Recreate the saved noiseless cases using their saved ground-truth arrays.
caseFolder = fullfile(root, 'results', 'validation', 'scientific-20261108-final', 'synthetic');
cases = [1 2];
results = cell(1, numel(cases));

% Terms shared by both cases: HRF peak, scalp physiology and linear/quadratic drift.
[~, peak] = max(T.t_HbO_brain);
t = p.recording.time(:);
time = (t - t(1)) / (t(end) - t(1));
physiology = sin(2*pi*.07*t) + .3*sin(2*pi*.015*t + .4);
scalpShape = 1 + .3*sin(data.atlas.fwmodel.mesh_scalp.vertices(:, 1) / 20);
drift = (.005*time + .002*(time.^2 - mean(time.^2))) * linspace(.8, 1.2, 2*nChannels);
nBrain = size(G.G_brain, 1) * size(T.T_HbO_brain, 2) * 2;
nScalp = size(G.G_scalp, 1) * size(T.T_HbO_scalp, 2) * 2;
vertexCount = size(data.atlas.fwmodel.mesh.vertices, 1);

for k = 1:numel(cases)
    id = cases(k);
    c = load(fullfile(caseFolder, sprintf('case-%02d.mat', id)));
    fprintf('Case %d: reconstructing identical noiseless optical measurements.\n', id);

    % Noiseless optical density: brain activation plus scalp physiology, then drift.
    truthO = c.truthHbo / c.trueHboHrf(peak);
    truthR = c.truthHbr / c.trueHbrHrf(peak);
    od = zeros(numel(t), 2*nChannels);
    for w = 1:2
        if id == 1
            % Case 1: brain-mask activity through the forward matrix.
            ao = S.A.Amatrix_brain.(sprintf('w%d_HbO', w)) * truthO(S.M.mask_brain, :);
            ar = S.A.Amatrix_brain.(sprintf('w%d_HbR', w)) * truthR(S.M.mask_brain, :);
        else
            % Case 2: all vertices through the unmasked sensitivity.
            ao = (double(S.Adot_orig(:, :, w)) * truthO) * S.E(w, 1);
            ar = (double(S.Adot_orig(:, :, w)) * truthR) * S.E(w, 2);
        end
        brainOd = (ao*T.T_HbO_brain' + ar*T.T_HbR_brain')';
        scalpMap = double(S.Adot_scalp_orig(:, :, w)) * scalpShape;
        scalpAmplitude = S.E(w, 1)*c.scalpHboAmplitudeM - S.E(w, 2)*c.scalpHboAmplitudeM*.3;
        od(:, (w - 1)*nChannels + (1:nChannels)) = brainOd + physiology*(scalpMap'*scalpAmplitude);
    end
    od = od + drift;

    % Current reconstruction of the recreated measurements.
    recording = p.recording;
    recording.od = od;
    observations = ssdot.recon.buildObservations(recording, S, p.probe, T, cfg);
    factors = ssdot.recon.factorDesign(p.model, 'cpu');
    compressed = ssdot.recon.compressDesign(factors, observations, cfg);
    [current, ~, ~, diagnostics] = ssdot.recon.solveCompressed(compressed, cfg);
    metrics(end + 1) = comparison(sprintf('case %d recreated current coefficients vs saved', id), current, c.coefficients);

    % The full normal equations are computed from exact QR coordinates of the
    % current implementation. Thus this is the original inverse, not an
    % independent full-design or end-to-end original reconstruction.
    X = [compressed.image compressed.nuisance];
    state = struct('HTH', X'*X, 'HTY', X'*compressed.response, ...
        'H_brain', zeros(1, nBrain), 'H_scalp', zeros(1, nScalp));
    cfgOriginal = struct('regularization', cfg.regularization, 'alpha', cfg.alpha, 'beta', cfg.beta);
    original = Proc_stream_v7('', '', cfgOriginal, state);
    imageColumns = 1:nBrain + nScalp;
    originalPenalty = cfg.alpha * eigs(state.HTH(imageColumns, imageColumns), 1);
    metrics(end + 1) = comparison(sprintf('case %d original image regularization scale', id), ...
        originalPenalty, diagnostics.imagePenalty);
    metrics(end + 1) = comparison(sprintf('case %d original inverse coefficients', id), original.b, current);

    % Original projection of the original inverse to vertices.
    originalCalculated = struct('Proc_data', proc, 'G', G, 'T', originalT, 'b', original.b, 'M', originalM);
    gpuConfig = struct('device', 'gpu', 'n_batch_brain', 128, 'with_scalp', 0);
    originalCalculated.Conc = approximate_Conc(originalCalculated, gpuConfig);
    [originalHbo, originalHbr] = project2vertex(originalCalculated, vertexCount);
    metrics(end + 1) = comparison(sprintf('case %d original HbO vs saved', id), originalHbo, c.hbo);
    metrics(end + 1) = comparison(sprintf('case %d original HbR vs saved', id), originalHbr, c.hbr);

    results{k} = struct('caseId', id, 'originalHbo', originalHbo, 'originalHbr', originalHbr, ...
        'currentHbo', c.hbo, 'currentHbr', c.hbr, 'truthHbo', c.truthHbo, 'truthHbr', c.truthHbr, ...
        'originalCoefficients', original.b, 'currentCoefficients', current, ...
        'penalty', diagnostics.imagePenalty, 'originalPenalty', originalPenalty);
    result = results{k};
    save(fullfile(folder, sprintf('case-%02d.mat', id)), '-struct', 'result', '-v7.3');
    writetable(struct2table(metrics), fullfile(folder, 'comparison-metrics.csv'));
    clear X state original compressed factors observations recording
end

writetable(struct2table(metrics), fullfile(folder, 'comparison-metrics.csv'));
save(fullfile(folder, 'comparison.mat'), 'metrics', 'results', 'cfg', 'commit', '-v7.3');
fprintf('Completed comparison: %s\n', folder);

function result = comparison(name, a, b)
    % Agreement metrics of two equally sized arrays over their finite entries.
    assert(isequal(size(a), size(b)), 'Size mismatch in %s', name);
    a = double(a(:));
    b = double(b(:));
    d = a - b;
    assert(isequal(isnan(a), isnan(b)) && isequal(isinf(a), isinf(b)), 'Nonfinite mismatch in %s', name);

    keep = isfinite(a) & isfinite(b);
    a = a(keep);
    b = b(keep);
    d = d(keep);
    if isempty(a)
        result = struct('name', string(name), 'maxAbs', NaN, 'relativeFrobenius', NaN, 'correlation', NaN);
        return
    end

    r = NaN;
    if std(a) > 0 && std(b) > 0
        c = corrcoef(a, b);
        r = c(1, 2);
    end
    result = struct('name', string(name), 'maxAbs', max(abs(d)), ...
        'relativeFrobenius', norm(d) / max(norm(a), realmin), 'correlation', r);
end

function sampled = sampleKernels(kernels)
    % The first, middle and last kernel.
    count = size(kernels, 1);
    sampled = kernels(unique([1, round(count / 2), count]), :);
end

function [brain, scalp] = designBlocks(A, G, T, rows)
    % The app's design columns, read from its factorized operator one unit coefficient at a time.
    model = struct('forwardMatrix', A, 'spatialBasis', G, 'temporalBasis', T);
    factors = ssdot.recon.factorDesign(model, 'cpu');
    noNuisance = struct('shortRegressors', sparse(rows, 0), 'driftRegressors', sparse(rows, 0));
    nColumns = factors.imageColumns;
    design = zeros(rows, nColumns);
    for column = 1:nColumns
        unit = zeros(nColumns, 1);
        unit(column) = 1;
        design(:, column) = ssdot.recon.applyFactorizedDesign(factors, noNuisance, unit, false);
    end
    nBrain = 2 * size(G.G_brain, 1) * size(T.T_HbO_brain, 2);
    brain = design(:, 1:nBrain);
    scalp = design(:, nBrain + 1:end);
end
