% dod = hmrConc2OD( dc, SD, ppf )
%
% UI NAME:
% Conc_to_OD
%
% dod = hmrConc2OD( dc, SD, ppf )
% Convert concentrations to OD
%
% INPUTS:
% dc: the concentration data (#time points x 3 x #SD pairs
%     3 concentrations are returned (HbO, HbR, HbT)
% SD:  the SD structure
% ppf: partial pathlength factors for each wavelength. If there are 2
%      wavelengths of data, then this is a vector ot 2 elements.
%      Typical value is ~6 for each wavelength if the absorption change is 
%      uniform over the volume of tissue measured. To approximate the
%      partial volume effect of a small localized absorption change within
%      an adult human head, this value could be as small as 0.1.
%
% OUTPUTS:
% dod: the change in OD (#time points x #channels)
%

function dod = hmrConc2OD( dc, SD, ppf )

nWav = length(SD.Lambda);
ml = SD.MeasList;
%% Yuanyuan
% new_ml = zeros(size(ml));
% sources
% source_list = unique(ml(:,1));
% source_list_in_order = sort(source_list);
% detectors
% detector_list = unique(ml(:,2));
% detector_list_in_order = sort(detector_list);

% iM = 1;
% for iWav = 1:2
% %     fprintf('iWav = %d\t',iWav)
%     for is = 1:length(source_list_in_order)
%         s = source_list_in_order(is);
%         for id = 1:length(detector_list_in_order)
%             d = detector_list_in_order(id);
%             iM_old = find(ml(:,1)==s & ml(:,2)==d & ml(:,4) == iWav);
%             if isempty(iM_old)
%                 continue
%             end
%             
% %             fprintf('s = %d\td = %d\tiM = %d\tiM_old = %d\n',s,d,iM,iM_old)
%             new_ml(iM,:) = ml(iM_old,:);
%             iM = iM + 1;
%         end
%     end
% end
%  ml = new_ml;
%%
if length(ppf)~=nWav
    errordlg('The length of PPF must match the number of wavelengths in SD.Lambda');
    dod = zeros(size(dod,1),size(ml,1));
    return
end

nTpts = size(dc,1);

e = GetExtinctions( SD.Lambda );
e = e(:,1:2) / 10; % convert from /cm to /mm
%einv = inv( e'*e )*e';

lst = find( ml(:,4)==1 );
for idx=1:length(lst)
    idx1 = lst(idx);
    idx2 = find( ml(:,4)>1 & ml(:,1)==ml(idx1,1) & ml(:,2)==ml(idx1,2) );
    rho = norm(SD.SrcPos(ml(idx1,1),:)-SD.DetPos(ml(idx1,2),:));
%     fprintf('idx is %d idx1 is %d idx2 is %d\n', idx, idx1, idx2)
    dod(:,[idx1 idx2']) = (e * dc(:,1:2,idx)')' .* (ones(nTpts,1)*rho*ppf);
%    dc(:,:,idx) = ( einv * (dod(:,[idx1 idx2'])./(ones(nTpts,1)*rho*ppf))' )';
end
%dc(:,3,:) = dc(:,1,:) + dc(:,2,:);
