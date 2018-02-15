% clc
clear
warning off
tic
% profile -memory on

disp('=============================================================================');
disp('              `    /$$    /$$  /$$$$$$  /$$$$$$$         /$$$$$$      /$$$$$$ ');
disp('+---------------+| $$   | $$ /$$__  $$| $$__  $$       /$$__  $$    /$$$_  $$');
disp('| RYERSON       || $$   | $$| $$  \ $$| $$  \ $$      |__/  \ $$   | $$$$\ $$');
disp('| APPLIED       ||  $$ / $$/| $$$$$$$$| $$$$$$$/         /$$$$$/   | $$ $$ $$');
disp('| AERODYNAMICS  | \  $$ $$/ | $$__  $$| $$____/         |___  $$   | $$\ $$$$');
disp('| LABORATORY OF |  \  $$$/  | $$  | $$| $$             /$$  \ $$   | $$ \ $$$');
disp('| FLIGHT        |   \  $/   | $$  | $$| $$            |  $$$$$$//$$|  $$$$$$/');
disp('+---------------+    \_/    |__/  |__/|__/             \______/|__/ \______/');
disp('=============================================================================');
disp(' ');

%% Best Practices
% 1. Define wing from one wingtip to another in one direction

%% Reading in geometry
filename = 'inputs/J_COLE_BASELINE.vap';


[flagRELAX, flagSTEADY, matGEOM, valMAXTIME, valMINTIME, valDELTIME, valDELTAE, ...
    valDENSITY, valKINV, valVEHICLES, matVEHORIG, vecVEHVINF, vecVEHALPHA, vecVEHBETA, vecVEHROLL, ...
    vecVEHFPA, vecVEHTRK, ~, vecWINGTRI, vecWAKETRI, ~, vecAREA, vecSPAN, vecCMAC, ~, ...
    ~, vecSYM, vecN0, vecM0, ~, ~, ~, vecPANELWING, ...
    vecSURFACEVEHICLE, valPANELS, ~, vecROTORRPM, vecROTDIAM, matROTORHUB, matROTORAXIS, vecROTORBLADES0, ~, vecPANELROTOR0,...
    vecFTURB, vecFUSESECTIONS, matFGEOM, matSECTIONFUSELAGE, vecFUSEVEHICLE, matFUSEAXIS, matFUSEORIG, vecVEHRADIUS,...
    vecCOLLECTIVE] = fcnXMLREAD(filename);

vecWINGTRI(~isnan(vecWINGTRI)) = nan;
vecWAKETRI(~isnan(vecWAKETRI)) = nan;
flagTRI = 0;
flagGPU = 0;

flagPRINT   = 1;
flagPLOT    = 1;
flagCIRCPLOT = 0;
flagGIF = 1;
flagPREVIEW = 0;
flagPLOTWAKEVEL = 0;
flagPLOTUINF = 0;
flagVERBOSE = 0;
flagVISCOUS = 0;

% Setup different run cases
valCASES = 1;
% seqVEVINF = vecROTDIAM*(vecROTORRPM/60)*[0.2 0.4 0.6 0.8 1];
% valCASES = length(seqVEVINF);
% 
% vecVEHALPHA = [3:9];
% valCASES = length(vecVEHALPHA);
% 
% vecCOLLECTIVE = 0;
% valCASES = length(vecCOLLECTIVE);
% vecVEHALPHA = repmat(vecVEHALPHA,valCASES,1);

valROTORS = max(vecPANELROTOR0);
% Preallocating for a turbo-boost in performance
vecCL = nan(valMAXTIME,valVEHICLES,valCASES);
vecCLF = nan(valMAXTIME,valVEHICLES,valCASES);
vecCLI = nan(valMAXTIME,valVEHICLES,valCASES);
vecCDI = nan(valMAXTIME,valVEHICLES,valCASES);
vecE = nan(valMAXTIME,valVEHICLES,valCASES);
vecCT = nan(valMAXTIME,valROTORS,valCASES);
vecCP = nan(valMAXTIME,valROTORS,valCASES);
vecCTCONV = nan(valMAXTIME, valROTORS,valCASES);

for i = 1:valCASES
    %     vecVEHVINF = seqVEVINF(i);
    
    %% Discretizing geometry into DVEs
    
    % Adding collective pitch to the propeller/rotor
     tmatGEOM = matGEOM;
%     tmatGEOM(:,5,vecPANELROTOR > 0) = matGEOM(:,5,vecPANELROTOR > 0) + repmat(reshape(vecCOLLECTIVE(vecPANELROTOR(vecPANELROTOR > 0), 1),1,1,[]),2,1,1);
    
    [matCENTER, vecDVEHVSPN, vecDVEHVCRD, vecDVELESWP, vecDVEMCSWP, vecDVETESWP, vecDVEROLL,...
        vecDVEPITCH, vecDVEYAW, vecDVEAREA, matDVENORM, matVLST, matNTVLST, matDVE, valNELE,...
        matADJE, vecDVESYM, vecDVETIP, vecDVESURFACE, vecDVELE, vecDVETE, vecDVEPANEL, matPANELTE,...
        valWINGS,vecDVEVEHICLE, vecDVEWING, vecDVEROTOR, vecDVEROTORBLADE, matSURFACETYPE, vecROTORVEH, ...
        matFUSEGEOM, matVEHUVW, matVEHROT, matVEHROTRATE, matCIRORIG, vecVEHPITCH, vecVEHYAW,...
        matROTORHUBGLOB, matUINF, vecDVETRI, vecN, vecM, valWSIZE, valWSIZETRI, vecPANELROTOR, vecQARM] = fcnGEOM2DVE(tmatGEOM, ...
        matVEHORIG, vecWINGTRI, vecWAKETRI, vecN0, vecM0, vecPANELWING,...
        vecSYM, vecSURFACEVEHICLE, vecPANELROTOR0, vecROTORBLADES0, matROTORHUB, matROTORAXIS, matSECTIONFUSELAGE,...
        vecFUSESECTIONS, matFGEOM, matFUSEAXIS, matFUSEORIG, vecFUSEVEHICLE, vecVEHVINF, vecVEHALPHA, vecVEHBETA, ...
        vecVEHFPA, vecVEHROLL, vecVEHTRK, vecVEHRADIUS, valVEHICLES, vecROTORRPM, vecPANELROTOR0);

    %% Viscous wrapper
    valDENSITY = 1.225;
    valKINV = 1.45e-5;

    vecAIRFOIL = 10*ones(valNELE,1);

    valVSPANELS = 0;
    matVSGEOM = [];
    valFPANELS = [];
    matFGEOM = [];
    valFTURB = [];
    valFPWIDTH = [];
    valINTERF = 15;
    
    vecROTORJ = [];
    
    for jj = 1:length(vecROTORRPM)
        vecROTORJ(i,jj) = (vecVEHVINF(vecROTORVEH(jj))*60)./(abs(vecROTORRPM(jj)).*vecROTDIAM(jj));
    end
    
    %% Add boundary conditions to D-Matrix
    [matD] = fcnDWING(valNELE, matADJE, vecDVEHVSPN, vecDVESYM, vecDVETIP, vecN);
    
    %% Add kinematic conditions to D-Matrix
    [vecK] = fcnSINGFCT(valNELE, vecDVESURFACE, vecDVETIP, vecDVEHVSPN);
    [matD] = fcnKINCON(matD, valNELE, matDVE, matCENTER, matVLST, matDVENORM, vecK, vecDVEROLL, vecDVEPITCH, vecDVEYAW, vecDVELESWP, vecDVETESWP, vecDVEHVSPN, vecDVEHVCRD, vecSYM, flagGPU);
    
    %% Preparing to timestep
    
    % Initializing wake parameters
    matWAKEGEOM = [];
    matNPWAKEGEOM = [];
    vecWDVEHVSPN = [];
    vecWDVEHVCRD = [];
    vecWDVEROLL = [];
    vecWDVEPITCH = [];
    vecWDVEYAW = [];
    vecWDVELESWP = [];
    vecWDVEMCSWP = [];
    vecWDVETESWP = [];
    vecWDVEAREA = [];
    matWDVENORM = [];
    matWVLST = [];
    matWDVE = [];
    valWNELE = 0;
    matWCENTER = [];
    matWCOEFF = [];
    vecWK = [];
    matWADJE = [];
    vecWDVEPANEL = [];
    valLENWADJE = 0;
    vecWKGAM = [];
    vecWDVESYM = [];
    vecWDVETIP = [];
    vecWDVESURFACE = [];
    vecWDVETRI = [];
    vecWPLOTSURF = [];
    
    % Building wing resultant
    [vecR] = fcnRWING(valNELE, 0, matCENTER, matDVENORM, matUINF, valWNELE, matWDVE, ...
        matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN, vecWDVEHVCRD,vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, ...
        vecWDVETESWP, vecDVESYM, valWSIZE, flagTRI, flagSTEADY);
    
    % Solving for wing coefficients
    [matCOEFF] = fcnSOLVED(matD, vecR, valNELE);
    
    %% Timestepping
    for valTIMESTEP = 1:valMAXTIME
        %% Timestep to solution
        %   Move wing
        %   Generate new wake elements
        %   Create and solve WD-Matrix for new elements
        %   Solve wing D-Matrix with wake-induced velocities
        %   Solve entire WD-Matrix
        %   Relaxation procedure (Relax, create W-Matrix and W-Resultant, solve W-Matrix)
        %   Calculate surface normal forces
        %   Calculate DVE normal forces
        %   Calculate induced drag
        %   Calculate cn, cl, cy, cdi
        %   Calculate viscous effects
        
        %% Moving the vehicles
        
        [matUINF, matUINFTE, matVEHORIG, matVLST, matCENTER, matNEWWAKE, matNPNEWWAKE, ...
            matFUSEGEOM, matNEWWAKEPANEL, vecDVEROLL, vecDVEPITCH, vecDVEYAW, matDVENORM, matNTVLST, matUINFROT] = fcnMOVESURFACE(matVEHORIG, matVEHUVW, matVEHROTRATE, matCIRORIG, vecVEHRADIUS, ...
            valDELTIME, matVLST, matCENTER, matDVE, vecDVEVEHICLE, vecDVETE, matFUSEGEOM, vecFUSEVEHICLE, ...
            matVEHROT, vecROTORVEH, matROTORHUB, matROTORAXIS, vecDVEROTOR, vecROTORRPM, matPANELTE, matNTVLST);
        
        %% Generating new wake elements
        
        idxtri = vecDVETRI == 1;
        widxtri = vecWDVETRI == 1;
        
        [matWAKEGEOM, matNPWAKEGEOM, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, ...
            vecWDVEMCSWP, vecWDVETESWP, vecWDVEAREA, matWDVENORM, matWVLST, matWDVE, valWNELE, matWCENTER, matWCOEFF, vecWK, matWADJE, matNTVLST, vecWDVEPANEL, valLENWADJE, vecWDVESYM, vecWDVETIP, vecWKGAM, vecWDVESURFACE, vecWPLOTSURF] ...
            = fcnCREATEWAKEROW(matNEWWAKE, matNPNEWWAKE, matWAKEGEOM, matNPWAKEGEOM, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, ...
            vecWDVEMCSWP, vecWDVETESWP, vecWDVEAREA, matWDVENORM, matWVLST, matWDVE, valWNELE, matWCENTER, matWCOEFF, vecWK, matCOEFF, vecDVETE, matWADJE, matNTVLST, vecDVEPANEL, ...
            vecWDVEPANEL, vecSYM, valLENWADJE, vecWKGAM, vecWDVESYM, vecWDVETIP, vecK, vecDVESURFACE, vecWDVESURFACE, flagSTEADY, valWSIZE, vecWPLOTSURF, vecDVEWING, vecDVEROTOR);
        
        if flagPREVIEW ~= 1
            %% Creating and solving WD-Matrix for latest row of wake elements
            % We need to grab from matWADJE only the values we need for this latest row of wake DVEs
            idx = sparse(sum(ismember(matWADJE,[((valWNELE - valWSIZE) + 1):valWNELE]'),2)>0 & (matWADJE(:,2) == 4 | matWADJE(:,2) == 2));
            temp_WADJE = [matWADJE(idx,1) - (valTIMESTEP-1)*valWSIZE matWADJE(idx,2) matWADJE(idx,3) - (valTIMESTEP-1)*valWSIZE];
            
            [matWD, vecWR] = fcnWDWAKE([1:valWSIZE]', temp_WADJE, vecWDVEHVSPN(end-valWSIZE+1:end), vecWDVESYM(end-valWSIZE+1:end), vecWDVETIP(end-valWSIZE+1:end), vecWKGAM(end-valWSIZE+1:end), vecN);
            [matWCOEFF(end-valWSIZE+1:end,:)] = fcnSOLVEWD(matWD, vecWR, valWSIZE, vecWKGAM(end-valWSIZE+1:end), vecWDVEHVSPN(end-valWSIZE+1:end));
            
            %% Rebuilding and solving wing resultant
            [vecR] = fcnRWING(valNELE, valTIMESTEP, matCENTER, matDVENORM, matUINF, valWNELE, matWDVE, ...
                matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN, vecWDVEHVCRD,vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, ...
                vecWDVETESWP, vecDVESYM, valWSIZE, flagTRI, flagSTEADY, flagGPU);
            
            [matCOEFF] = fcnSOLVED(matD, vecR, valNELE);
            
            %% Creating and solving WD-Matrix
            [matWD, vecWR] = fcnWDWAKE([1:valWNELE]', matWADJE, vecWDVEHVSPN, vecWDVESYM, vecWDVETIP, vecWKGAM, vecN);
            [matWCOEFF] = fcnSOLVEWD(matWD, vecWR, valWNELE, vecWKGAM, vecWDVEHVSPN);
            
            %% Relaxing wake
            if valTIMESTEP > 2 && flagRELAX == 1
                
                [vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW,...
                    vecWDVELESWP, vecDVEWMCSWP, vecDVEWTESWP, vecWDVEAREA, matWCENTER, matWDVENORM, ...
                    matWVLST, matWDVE, matWDVEMP, matWDVEMPIND, idxWVLST, vecWK] = fcnRELAXWAKE(matUINF, matCOEFF, matDVE, matVLST, matWADJE, matWCOEFF, ...
                    matWDVE, matWVLST, valDELTIME, valNELE, valTIMESTEP, valWNELE, valWSIZE, vecDVETE, vecDVEHVSPN, vecDVEHVCRD, vecDVELESWP, ...
                    vecDVEPITCH, vecDVEROLL, vecDVETESWP, vecDVEYAW, vecK, vecDVESYM, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVELESWP, vecWDVEPITCH, ...
                    vecWDVEROLL, vecWDVESYM, vecWDVETESWP, vecWDVETIP, vecWDVEYAW, vecWK, vecWDVESURFACE, flagSTEADY, flagGPU);
                
                % Creating and solving WD-Matrix
                [matWD, vecWR] = fcnWDWAKE([1:valWNELE]', matWADJE, vecWDVEHVSPN, vecWDVESYM, vecWDVETIP, vecWKGAM, vecN);
                [matWCOEFF] = fcnSOLVEWD(matWD, vecWR, valWNELE, vecWKGAM, vecWDVEHVSPN);
            end
            %[hFig2] = fcnPLOTBODY(0, valNELE, matDVE, matVLST, matCENTER, [])
            
            %% Forces
            [vecCLv(:,i), vecCD(:,i), vecPREQ(:,i), vecLD(:,i), vecCL(valTIMESTEP,:,i), vecCLF(valTIMESTEP,:,i), vecCLI(valTIMESTEP,:,i), vecCDI(valTIMESTEP,:,i), vecCT(valTIMESTEP,:,i), vecCP(valTIMESTEP,:,i), vecE(valTIMESTEP,:,i), vecDVENFREE, vecDVENIND, ...
                vecDVELFREE, vecDVELIND, vecDVESFREE, vecDVESIND] = fcnFORCES(matCOEFF, vecK, matDVE, valNELE, matCENTER, matVLST, matUINF, vecDVELESWP, ...
                vecDVEMCSWP, vecDVEHVSPN, vecDVEHVCRD, vecDVEROLL, vecDVEPITCH, vecDVEYAW, vecDVELE, vecDVETE, matADJE, valWNELE, matWDVE, matWVLST, ...
                matWCOEFF, vecWK, vecWDVEHVSPN, vecWDVEHVCRD, vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, vecWDVETESWP, valWSIZE, valTIMESTEP, ...
                vecDVESYM, vecDVETESWP, vecAREA, vecSPAN, [], vecDVEWING, vecWDVESURFACE, vecN, vecM, vecDVEPANEL, vecDVEVEHICLE, valVEHICLES, matVEHROT, flagTRI, flagSTEADY, flagGPU, vecDVEROTOR, matROTORAXIS, vecROTORRPM, vecROTDIAM, valDELTIME, vecVEHVINF, valDENSITY, valKINV,  vecDVEAREA, vecAIRFOIL, flagVERBOSE, vecSYM, valVSPANELS, matVSGEOM, valFPANELS, matFGEOM, valFTURB, valFPWIDTH, valINTERF, valMAXTIME, vecPANELROTOR, matUINFROT, vecQARM, flagVISCOUS);
                
            vecCTCONV = vecCT;
                   
        end
        
        %% Post-timestep outputs
        if flagPRINT == 1
            fcnPRINTOUT(flagPRINT, valTIMESTEP, valVEHICLES, vecCL, vecCDI, vecCTCONV, vecROTORJ, vecROTORVEH,i)
        end
        
        if flagGIF == 1 % Creating GIF (output to GIF/ folder by default)
            fcnGIF(flagVERBOSE, valTIMESTEP, valNELE, matDVE, matVLST, matCENTER, matFUSEGEOM, valWNELE, matWDVE, matWVLST, matWCENTER, vecWPLOTSURF, i);
        end
    
        if flagPREVIEW ~= 1 && max(vecDVEROTOR) > 0
            temp_cdi = fcnTIMEAVERAGE(vecCDI(:,end,i), vecROTORRPM, valDELTIME);
        end
    end
    if flagPRINT == 1 && flagPREVIEW == 0
        fprintf('VISCOUS CORRECTIONS => CLv = %0.4f \tCD = %0.4f \n', vecCLv(i), vecCD(i))
    end
    
    fprintf('\n');
end

%% Plotting
if flagPREVIEW == 1; flagRELAX = 0; end

if flagPLOT == 1 && flagRELAX == 1 && valMAXTIME > 0
    fcnPLOTPKG(flagVERBOSE, flagPLOTWAKEVEL, flagCIRCPLOT, flagPLOTUINF, valNELE, matDVE, matVLST, matCENTER, matFUSEGEOM, valWNELE, matWDVE, matWVLST, matWCENTER, ...
        matWDVEMP, matWDVEMPIND, matUINF, vecDVEROLL, vecDVEPITCH, vecDVEYAW, matCOEFF, vecWDVESURFACE);
elseif flagPLOT == 1 && (flagRELAX ~= 1 || valMAXTIME == 0)
    fcnPLOTPKG(flagVERBOSE, flagPLOTWAKEVEL, flagCIRCPLOT, flagPLOTUINF, valNELE, matDVE, matVLST, matCENTER, matFUSEGEOM, valWNELE, matWDVE, matWVLST, matWCENTER, ...
        [], [], matUINF, vecDVEROLL, vecDVEPITCH, vecDVEYAW, matCOEFF, vecWPLOTSURF);
end
