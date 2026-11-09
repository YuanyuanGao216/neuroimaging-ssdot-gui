function output = applyFactorizedDesign(factors, observations, input, transpose)
    %APPLYFACTORIZEDDESIGN Original uncompressed design/adjoint without forming H.
    % Independent forward-space checks and matrix-free iterative investigations use this operator.
    n=factors.channels; nt=factors.timeCount; ni=factors.imageColumns; block=n*nt;
    ns=size(observations.shortRegressors,2); nd=size(observations.driftRegressors,2);
    if ~transpose
        validateattributes(input,{'double'},{'column','numel',ni+ns+nd});
        output=observations.shortRegressors*input(ni+(1:ns))+observations.driftRegressors*input(ni+ns+(1:nd));
        for wavelength=1:2
            values=zeros(n,nt);
            for part=1:4
                f=factors.parts(part); columns=factors.offsets(part)+(1:f.width);
                coefficients=reshape(input(columns),size(f.time,2),f.kernelCount)';
                values=values+(f.optical{wavelength}*coefficients)*f.time';
            end
            rows=(wavelength-1)*block+(1:block); output(rows)=output(rows)+values(:);
        end
    else
        validateattributes(input,{'double'},{'column','numel',2*block});
        output=zeros(ni+ns+nd,1);
        output(ni+(1:ns))=observations.shortRegressors'*input;
        output(ni+ns+(1:nd))=observations.driftRegressors'*input;
        for wavelength=1:2
            rows=(wavelength-1)*block+(1:block); values=reshape(input(rows),n,nt);
            for part=1:4
                f=factors.parts(part); columns=factors.offsets(part)+(1:f.width);
                coefficients=f.optical{wavelength}'*(values*f.time);
                output(columns)=output(columns)+reshape(coefficients',[],1);
            end
        end
    end
end
