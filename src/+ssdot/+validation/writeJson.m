function writeJson(filename,value)
    %WRITEJSON Replace only this study's generated status/report atomically.
    file=fopen(filename+".partial",'w','n','UTF-8'); assert(file>=0,'SSDOT:ValidationWrite','Cannot write %s.',filename);
    cleanup=onCleanup(@()fclose(file)); fprintf(file,'%s\n',jsonencode(value,'PrettyPrint',true)); clear cleanup
    movefile(filename+".partial",filename,'f');
end
