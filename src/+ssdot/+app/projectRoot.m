function root = projectRoot()
    %PROJECTROOT Locate the checkout without relying on the working directory.
    root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
