function process = runProcess(command, logFile)
    %RUNPROCESS Launch an argument array, never a string-built shell command.
    argumentList = java.util.ArrayList();
    for value = string(command(:))'
        argumentList.add(java.lang.String(char(value)));
    end
    builder = java.lang.ProcessBuilder(argumentList);
    builder.redirectErrorStream(true);
    builder.redirectOutput(java.io.File(char(logFile)));
    process = builder.start();
end
