function report = gpuDiagnostics(runComputation,passive)
    %GPUDIAGNOSTICS Record products, license, actual device and allocation/computation checks.
    if nargin < 1, runComputation = false; end
    if nargin < 2, passive=false; end
    report = struct('installed',exist('gpuDevice','file')~=0 && exist('gpuArray','file')~=0, ...
        'licensed',logical(license('test','Distrib_Computing_Toolbox')),'available',false, ...
        'name',"",'driver',"",'totalMemory',0,'availableMemory',0,'matlabAvailableMemory',0,'physicalAvailableMemory',Inf, ...
        'computationPassed',false,'reconstructionValidated',false,'identifier',"",'message',"",'hardware',"");
    [status,hardware] = system('nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader');
    if status==0, report.hardware = strtrim(string(hardware)); end
    if ~report.installed
        report.identifier = "SSDOT:GPUUnavailable";
        report.message = "Parallel Computing Toolbox is not installed. MATLAB cannot execute gpuArray operations.";
        return;
    end
    if ~report.licensed
        report.identifier = "SSDOT:GPUUnavailable"; report.message = "Parallel Computing Toolbox license unavailable."; return;
    end
    if passive && ~runComputation
        report.message="GPU initialization deferred while CPU is selected. Choose GPU or run diagnostics to validate availability.";
        return;
    end
    try
        device = gpuDevice;
        report.name = string(device.Name); report.totalMemory = device.TotalMemory;
        report.availableMemory = device.AvailableMemory; report.available = device.DeviceAvailable;
        report.matlabAvailableMemory=device.AvailableMemory;
        [memoryStatus,memoryText]=system(sprintf('nvidia-smi -i %d --query-gpu=memory.free --format=csv,noheader,nounits',device.Index-1));
        physical=str2double(strtrim(memoryText));
        if memoryStatus==0 && isfinite(physical)
            report.physicalAvailableMemory=physical*2^20;
            report.availableMemory=min(report.availableMemory,report.physicalAvailableMemory);
        end
        if isprop(device,'DriverVersion'), report.driver = string(device.DriverVersion); end
        if runComputation
            input = gpuArray(reshape(1:16,4,4)); actual = input'*input;
            assert(isa(actual,'gpuArray'),'SSDOT:GPUExecution','The diagnostic did not execute on the GPU.');
            assert(isequal(gather(actual),reshape(1:16,4,4)'*reshape(1:16,4,4)),'SSDOT:GPUExecution','GPU arithmetic check failed.');
            wait(device); report.computationPassed = true;
        end
        report.message = "GPU available. A completed GPU reconstruction is still required for pipeline validation.";
    catch exception
        report.available = false; report.identifier = string(exception.identifier); report.message = string(exception.message);
    end
end
