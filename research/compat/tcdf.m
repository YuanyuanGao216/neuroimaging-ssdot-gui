function p = tcdf(x, nu)
    %TCDF Student t CDF compatibility shim for the original GLM's p-value output.
    % Uses the regularized incomplete beta function supplied with base MATLAB.
    validateattributes(nu, {'numeric'}, {'scalar', 'positive', 'finite'});
    x = double(x);
    z = nu./(nu + x.^2);
    p = 0.5*betainc(z, nu/2, 0.5);
    p(x > 0) = 1 - p(x > 0);
end
