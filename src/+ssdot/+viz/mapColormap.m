function colors = mapColormap(name)
    %MAPCOLORMAP Colormaps offered for signed maps (concentration change and T values).
    % "jetNeutral" (original display): jet with the three central entries gray,
    % so values within about 1.2% of the color limit around zero appear gray.
    switch string(name)
        case "jetNeutral", colors = jet(256); colors(127:129,:) = 0.8;
        case "jet", colors = jet(256);
        case "parula", colors = parula(256);
        case "turbo", colors = turbo(256);
        otherwise, error('SSDOT:Colormap','Unknown colormap "%s".',name);
    end
end
