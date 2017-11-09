function [w_wake] = fcnWDVEVEL(fpg, valWNELE, matWDVE, matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, vecWDVETESWP, vecDVESYM, valWSIZE, valTIMESTEP, flagTRI, flagSTEADY, flagGPU)

% vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, ...
% vecWDVEMCSWP, vecWDVETESWP, matWDVENORM, matWVLST, matWDVE, valWNELE, ...
% matWCENTER, matWCOEFF, vecWK

% List of wDVEs we are influencing from (each one for each of the fieldpoints)
len = length(fpg(:,1));
dvenum = reshape(repmat(1:valWNELE,len,1),[],1);

fpg = repmat(fpg,valWNELE,1);

if flagSTEADY == 1
    % DVE type 1 is a regular wake DVE
    dvetype = ones(length(dvenum),1);

    % Newest row of wake DVEs have a filament at the leading edge
    if flagTRI == 1
        newest_row = sort([valWNELE:-2:valWNELE-valWSIZE*2+1]-1)';
    else
        newest_row = [((valWNELE-valWSIZE)+1):1:valWNELE]';
    end

    dvetype(ismember(dvenum, newest_row)) = 2;

    % Oldest row of wake DVEs are semi-infinite
    if flagTRI == 1
        oldest_row = [2:2:valWSIZE*2];
    else
    oldest_row = [1:valWSIZE]';
    end

    if valTIMESTEP == 1 && flagTRI == 0
        dvetype(ismember(dvenum, oldest_row)) = -3;
    elseif valTIMESTEP > 0 && flagTRI == 0
        dvetype(ismember(dvenum, oldest_row)) = 3;
    elseif flagTRI == 1 % last row of wake elements in a tri-wake never has a bound vortex
        dvetype(ismember(dvenum, oldest_row)) = 3;
    end

elseif flagSTEADY == 0 || 2
    % DVE type 1 is a regular wake DVE
    dvetype = zeros(length(dvenum),1);

    % Oldest row of wake DVEs are semi-infinite
    if flagTRI == 1
        oldest_row = [2:2:valWSIZE*2];
    else
        oldest_row = [1:valWSIZE]';
    end
    
    dvetype(ismember(dvenum, oldest_row)) = -3;
    
end

[w_ind] = fcnDVEVEL(dvenum, fpg, dvetype, matWDVE, matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, vecWDVETESWP, vecDVESYM, flagGPU);

w_wake = reshape(sum(reshape(w_ind', len*3, [])',1),3,[])';
end

