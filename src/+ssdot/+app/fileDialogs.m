function dialogs = fileDialogs()
    %FILEDIALOGS Operating-system file choosers; each returns "" when cancelled.
    % Tests replace these handles instead of driving native dialogs.
    dialogs = struct('folder', @chooseFolder, 'openFile', @chooseFile, 'saveFile', @chooseSaveFile);
end

function folder = chooseFolder(initial, titleText)
    folder = uigetdir(char(initial), char(titleText));
    folder = selection(folder);
end

function filename = chooseFile(filter, titleText, initial)
    [file, folder] = uigetfile(filter, char(titleText), char(initial));
    filename = selection(file, folder);
end

function filename = chooseSaveFile(filter, titleText, initial)
    [file, folder] = uiputfile(filter, char(titleText), char(initial));
    filename = selection(file, folder);
end

function path = selection(name, folder)
    %SELECTION The chosen path as a string; "" when the dialog was cancelled.
    if isequal(name, 0)
        path = "";
    elseif nargin < 2
        path = string(name);
    else
        path = string(fullfile(folder, name));
    end
end
