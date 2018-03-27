function [valCL, valCD, valPREQ, valLD] = fcnVISCOUS_WING(valCL, valCDI, valAREA, valDENSITY, valKINV, vecDVENFREE, vecDVENIND, ...
    vecDVELFREE, vecDVELIND, vecDVESFREE, vecDVESIND, vecDVEPANEL, vecDVELE, vecDVEWING, vecN, vecM, vecDVEAREA, ...
    matCENTER, vecDVEHVCRD, cellAIRFOIL, flagVERBOSE, vecSYM, valVSPANELS, matVSGEOM, valFPANELS, matFGEOM, valFTURB, ...
    valFPWIDTH, valINTERF, vecDVEROLL, matUINF, matWUINF, matDVE, matVLST, valVEHVINF)

% Calculate chordline direction at midspan of each dve
avgle = (matVLST(matDVE(:,1),:)+matVLST(matDVE(:,2),:))./2;
avgte = (matVLST(matDVE(:,3),:)+matVLST(matDVE(:,4),:))./2;
tempDIF = avgte - avgle;
matCRDLINE = (tempDIF)./(repmat(sqrt(sum(tempDIF.^2,2)),[1,3]));
% Calculate velocity with induced effects
vecV = dot(matUINF(vecDVEWING>0) + matWUINF(vecDVEWING>0), matCRDLINE(vecDVEWING>0),2);

% Compute dynamic pressure
q_infandind = ((vecV.^2)*valDENSITY)/2; % With both freestream and induced velocities
q_inf = ((valVEHVINF^2)*valDENSITY)/2; % With only freestream velocities

% Calculate induced drag as a force
di = valCDI*valAREA*q_inf;

% Summing freestream and induced forces of each DVE
vecDVECN = (vecDVENFREE + vecDVENIND);

[ledves, ~, ~] = find(vecDVELE > 0);
lepanels = vecDVEPANEL(ledves);

vecCNDIST = [];
matXYZDIST = [];
vecLEDVEDIST = [];
vecREDIST = [];
vecAREADIST = [];

for i = 1:max(vecDVEWING)
    
    %% Getting the CL, CY, CN distribution
    idxdve = uint16(ledves(vecDVEWING(ledves) == i));
    idxpanel = lepanels(vecDVEWING(ledves) == i);
    
    m = vecM(idxpanel);
    if any(m - m(1))
        disp('Problem with wing chordwise elements.');
        break
    end
    
    m = m(1);
    
    % Matrix of how much we need to add to an index to get the next chordwise element
    % It is done this way because n can be different for each panel. Unlike in the wake,
    % we can't just add a constant value to get to the same spanwise location in the next
    % row of elements
    tempm = repmat(vecN(idxpanel), 1, m).*repmat([0:m-1],length(idxpanel~=0),1);

    rows = repmat(idxdve,1,m) + uint16(tempm);
    
    % Note this CN is non-dimensionalized with Vinf + Vind
    vecCNDIST = [vecCNDIST; (sum(vecDVECN(rows),2).*2)./((mean(vecV(rows),2).^2).*sum(vecDVEAREA(rows),2))];
    
    % The average coordinates for this row of elements
    matXYZDIST = [matXYZDIST; mean(permute(reshape(matCENTER(rows,:)',3,[],m),[2 1 3]),3)];
    
    % The leading edge DVE for the distribution
    vecLEDVEDIST = [vecLEDVEDIST; idxdve];
    
    %% Wing/horizontal stabilizer lift and drag
    % Note that Re is compute with Vinf + Vind
    vecREDIST = [vecREDIST; mean(vecV(rows),2).*2.*sum(vecDVEHVCRD(rows),2)./valKINV];
    vecAREADIST = [vecAREADIST; sum(vecDVEAREA(rows),2)];
    
    vecCDPDIST = nan(size(vecCNDIST)); % pre-allocate the array to store viscous drag results
    vecCLMAX   = nan(size(vecCNDIST));
    
    % collect all the unique airfoils and load them
    [uniqueAirfoil,~,idxAirfoil] = unique(cellAIRFOIL);
    for k = 1:length(uniqueAirfoil)
        % Load airfoil .mat files
        try
            load(strcat('airfoils/',cellAIRFOIL{k},'.mat'));
            
        catch
            error('Error: Unable to locate airfoil file: %s.mat.', cellAIRFOIL{k});
        end

        Cl  = reshape(pol(:,2,:),[],1);
        Cdp = reshape(pol(:,3,:),[],1);
        Re  = reshape(pol(:,8,:),[],1);

        %which rows of DVE belongs to the airfoil in this loop
        isCurrentAirfoil = idxAirfoil(idxpanel) == k;

        idxNans = isnan(Cl) | isnan(Cdp) | isnan(Re);
        Cl = Cl(~idxNans);
        Cdp = Cdp(~idxNans);
        Re = Re(~idxNans);

        % Compare Re data range to panel Re
        if max(vecREDIST(isCurrentAirfoil)) > max(Re)
            disp('Re higher than airfoil Re data.')
        end
        
        if min(vecREDIST(isCurrentAirfoil)) < min(Re)
            disp('Re lower than airfoil Re data.')
        end

        % find CLmax for each row of dves
        polarClmax = max(pol(:,2,:));
        polarClmax = polarClmax(:);
        
        polarClmaxRe = unique(pol(:,8,:));
        polarClmaxRe = sort(polarClmaxRe(~isnan(polarClmaxRe)));
        %polarClmaxRe = reshape(pol(1,8,:),[],1);
        
        vecCLMAX(isCurrentAirfoil) = interp1(polarClmaxRe,polarClmax,vecREDIST(isCurrentAirfoil),'linear');
        
        % Out of range Reynolds number index
        idxReOFR = (vecREDIST > max(Re) | vecREDIST < min(Re)) & isCurrentAirfoil;
        % Nearest extrap for out of range Reynolds number
        vecCLMAX(idxReOFR) = interp1(polarClmaxRe,polarClmax,vecREDIST(idxReOFR),'nearest','extrap');

        % Check for stall and change the CL
        idxSTALL = (vecCNDIST > vecCLMAX) & isCurrentAirfoil;
        vecCNDIST(idxSTALL) = vecCLMAX(idxSTALL).*0.825;
        if sum(idxSTALL) > 1
            disp('Airfoil sections have stalled.')
        end

        F = scatteredInterpolant(Re,Cl,Cdp,'linear');
        vecCDPDIST(isCurrentAirfoil) = F(vecREDIST(isCurrentAirfoil), vecCNDIST(isCurrentAirfoil));
        clear pol foil
    end
	% CN in terms of Vinf instead of Vinf + Vind
    vecCNDIST = vecCNDIST.*(mean(vecV(rows),2).^2)/(valVEHVINF^2);
end

% dimensionalize in terms of both Vinf and Vind
dprof = sum(vecCDPDIST.*mean(q_infandind(rows),2).*vecAREADIST);

% This function does not account for symmetry well, it is all or nothing with symmetry,
% but it really should be wing-by-wing
if any(vecSYM) == 1
    dprof = 2.*dprof;
end

%% Vertical tail drag

dvt = 0;
% for ii = 1:valVSPANELS
%     Re = valVINF*matVSGEOM(ii,2)/valKINV;
%     
%     % Load airfoil data
%     airfoil = dlmread(strcat('airfoils/airfoil',num2str(matVSGEOM(ii,4)),'.dat'),'', 1, 0);
%     
%     % determining the drag coefficient corresponding to lift
%     % coefficient of 0
%     
%     % MATLAB:
%     F = scatteredInterpolant(airfoil(:,4), airfoil(:,2), airfoil(:,3),'nearest');
%     cdvt = F(Re, 0);
%     % Octave:
%     % cdvt = griddata(Temp.Airfoil(:,4), Temp.Airfoil(:,2), Temp.Airfoil(:,3), Re, 0, 'nearest');
%     
%     dvt = dvt + cdvt*matVSGEOM(ii,3);
% end

dvt = dvt*q_inf;

%% Fuselage drag

dfuselage = 0;

tempSS = valVEHVINF*valFPWIDTH/valKINV;

for ii = 1:valFPANELS
    Re_fus = (ii-0.5)*tempSS;
    if ii < valFTURB
        cdf = 0.664/sqrt(Re_fus); % Laminar
    else
        cdf = 0.0576/(Re_fus^0.2); % Turbulent
    end
    
    dfuselage = dfuselage + cdf*matFGEOM(ii,2)*pi*valFPWIDTH;
end

dfuselage = dfuselage*q_inf;

%% Total Drag

dtot = di + dprof + dvt + dfuselage;

dint = dtot*(valINTERF/100);

dtot = dtot + dint;

valCD = dtot/(q_inf*valAREA);

%% Adjusting CL for stall
valCL = sum(vecCNDIST.*vecAREADIST.*cos(vecDVEROLL(vecLEDVEDIST)))/valAREA*2;

%% Final calculations
valLD = valCL./valCD;
valPREQ = dtot.*valVEHVINF;

end

