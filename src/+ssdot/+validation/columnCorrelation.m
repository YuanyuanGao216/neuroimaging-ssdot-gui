function r=columnCorrelation(a,b)
    a=a-mean(a); b=b-mean(b); r=sum(a.*b)./sqrt(sum(a.^2).*sum(b.^2));
end

