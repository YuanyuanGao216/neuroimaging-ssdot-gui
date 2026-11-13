function manifest = prepareExternal(options, progress)
    %PREPAREEXTERNAL Verify public bytes and create a documented numerical adapter.
    package = fileparts(mfilename('fullpath'));
    script = fullfile(package, 'prepareBenchmarks.py');
    logFile = fullfile(options.outputFolder, 'benchmark-download.log');

    progress("Checking public benchmark inputs", 0, 1);
    process = ssdot.validation.runProcess([options.pythonExecutable, string(script), options.externalDataRoot, ...
        "--public-root", options.publicDataRoot], logFile);
    while process.isAlive()
        % A native HTTPS read completes before cancellation; pause yields to UI
        % callbacks while avoiding an orphaned downloader subprocess.
        pause(0.25);
        drawnow limitrate;
    end
    assert(process.exitValue() == 0, 'SSDOT:BenchmarkPreparation', 'Benchmark adapter failed. Details: %s', logFile);

    manifest = jsondecode(fileread(fullfile(options.externalDataRoot, 'cedalion', 'provenance.json')));
    assert(ssdot.io.fileHash(manifest.derivedMat) == string(manifest.derivedMatSha256), ...
        'SSDOT:BenchmarkIntegrity', 'Derived benchmark changed after preparation.');
    progress("Public recording/model identities verified", 1, 1);
end
