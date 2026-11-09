function saveRoi(filename, roi, surface)
    %SAVEROI Persist selections with mesh identity and coordinate provenance.
    roi = ssdot.viz.validateRoi(roi,surface);
    save(filename,'roi');
end
