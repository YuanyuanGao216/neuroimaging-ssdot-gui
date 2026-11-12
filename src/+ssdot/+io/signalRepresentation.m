function [data, name] = signalRepresentation(node, kind, averaged)
    %SIGNALREPRESENTATION Retrieve a stored representation; never derive missing averages.
    kind = string(kind);
    if kind == "Raw data"
        assert(~averaged, "SSDOT:NoAverage", "Raw intensity has no averaged HRF representation.");
        name = "raw intensity";
        data = node.acquired.data;
    else
        assert(ismember(kind, ["OD", "Conc"]), "SSDOT:SignalKind", "Unsupported signal representation: %s.", kind);
        name = "dod";
        if kind == "Conc"
            name = "dc";
        end
        if averaged
            name = name + "Avg";
        end
        data = node.procStream.output.GetVar(char(name));
    end

    % Only the first data block is shown; a block without samples counts as missing.
    if ~isempty(data)
        data = data(1);
        if isempty(data.GetTime()) || isempty(data.GetDataTimeSeries())
            data = [];
        end
    end
end
