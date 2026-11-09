function r=correlationOf(a,b)
    a=a-mean(a); b=b-mean(b); r=ssdot.validation.safeDivide(sum(a.*b),norm(a)*norm(b));
end

