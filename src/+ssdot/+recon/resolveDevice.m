function device = resolveDevice(device)
    %RESOLVEDEVICE Validate the requested backend; never silently switch it.
    device = validatestring(device, {'cpu', 'gpu'});
    if strcmp(device, 'cpu')
        return
    end
    assert(exist('gpuDevice', 'file') ~= 0 && exist('gpuArray', 'file') ~= 0, 'SSDOT:GPUUnavailable', ...
        ['GPU requested, but Parallel Computing Toolbox is not installed. ' ...
        'Select CPU explicitly or install the toolbox.']);
    assert(license('test', 'Distrib_Computing_Toolbox'), 'SSDOT:GPUUnavailable', ...
        'GPU requested, but a Parallel Computing Toolbox license is unavailable.');
    try
        gpuDevice;
    catch exception
        error('SSDOT:GPUUnavailable', ...
            'GPU initialization failed (%s): %s. CPU has not been selected automatically.', ...
            exception.identifier, exception.message);
    end
end
