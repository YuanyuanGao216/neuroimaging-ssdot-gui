function values=percentiles(x,p)
    x=sort(x(:)); location=1+(numel(x)-1)*p(:)'/100;
    lo=floor(location); hi=ceil(location); values=x(lo)'.*(hi-location)+x(hi)'.*(location-lo);
    equal=lo==hi; values(equal)=x(lo(equal));
end

