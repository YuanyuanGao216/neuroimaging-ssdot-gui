function loadSens(app)

folderPath = uigetdir(pwd, 'Select AtlasViewer Folder which contains fw folder');

if isequal(folderPath, 0)
    disp('User canceled folder selection.');
    return;
end

disp(['Selected folder: ', folderPath]);

mlActAuto = []; % we need to do something here later
atlasViewer = get_global_variable(app, 'AtlasState');
wavelength = [760 850]; % Vu we need users to input this or we get this information from snirf
%% Prompt the user for a mask threshold value
prompt = {'Enter threshold of sensitivity'};
dlgtitle = 'Input Threshold';
dims = [1 35];
definput = {'-2'};  % Default value

answer = inputdlg(prompt, dlgtitle, dims, definput);

% If user presses Cancel, exit
if isempty(answer)
    return;
end



% Convert input from string to numeric
mask_threshold = str2double(answer{1});

% Validate the input
if isnan(mask_threshold)
    uialert(app.UIFigure, 'Invalid input. Please enter a numeric value.', 'Error');
    return;
end


wavelength = [760 850]; % Vu please also get users to input this or we get this information from snirf

Sensitivity_Matrix = Get_A_dot(folderPath,7,mlActAuto,1,atlasViewer, wavelength, mask_threshold);

hFig =  app.UIFigure;
setappdata(hFig, 'Sensitivity_Matrix', Sensitivity_Matrix);

disp('calculate A finished');