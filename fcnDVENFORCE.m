function [en, nfree,nind,liftfree,liftind,sidefree,sideind] = fcnDVENFORCE(matCOEFF...
    ,vecK,matDVE,valNELE,matCENTER,matVLST,matUINF,vecDVELESWP,vecDVEMCSWP,vecDVEHVSPN,vecDVEHVCRD,vecDVEROLL,...
    vecDVEPITCH,vecDVEYAW,vecDVELE,matADJE,valWNELE, matWDVE, matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN,vecWDVEHVCRD,...
    vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, vecWDVETESWP, valWSIZE, valTIMESTEP, vecDVESYM, vecDVETESWP, matVEHROT, vecDVEVEHICLE, flagTRI, flagSTEADY, flagGPU)
%DVE element normal forces

% //computes lift and side force/density acting on surface DVE's. The local
% //lift force is comuted by applying Kutta-Joukowski's theorem to both edges
% //and to the center of DVE's bound vortices. These values are integrated,
% //using Simpson's rule (with overhang), in order to get the lift force/density
% //for the complete surface DVE.
% //Furthermore, as of now, any lift force due to the DVE's vortex sheet is
% //neglected, since the resulting induced side velocities should be small
% //
% //
% //Note: the velocities are not computed directly at the vortex edges, but
% //at 80% of the of the DVE halfspan.
% //Otherwise, the computed induced velocity would become singular at that
% //point due to the next neighboring elementary wing influence.

% INPUTS:

% OUTPUTS:
% nind - induced normal force for each DVE
% nfree - freestream normal force for each DVE
% liftfree - freestream lift force for each DVE
% liftind - induced lift for each DVE
% sidefree - freestream side force for each DVE
% sideind - induced side force for each DVE


%% preliminary stuff

%for quad elements:
%we need to average mid chord velocities of each
%chordwise row to estimate LE vels, since there may be a gap at the LE

%for triangle elements:
%we find all velocities directly at the LE

if flagTRI ==1  %tri elements
    idx1 = ones(valNELE,1) == 1 ;
    
else %quad elements,
    idx1 = vecDVELE == 1; %index of LE vectors (will be the same)
end
% find vector across element (should already have this somewhere...)
% for first spanwise row, vector is LE vect, for all other spanwise rows,
% vector is halfchord vect.

% vector of bound vortex along leading edge for LE row
% tempa(idx1,1) = tan(vecDVELESWP(idx1));
s = zeros(valNELE,3);
s(idx1,:) =( matVLST(matDVE(idx1,2),:) -matVLST(matDVE(idx1,1),:) )  ./ repmat((vecDVEHVSPN(idx1).*2),1,3); %?? why is the S vector non-dim. to the span?

% vector along midchord for remaining elements
if any(idx1 == 0)
    tempa = zeros(valNELE,1);
    tempa(idx1==0,1) = tan(vecDVEMCSWP(idx1==0));
    tempa= [tempa ones(valNELE,1)  zeros(valNELE,1)];
    
    % global vectors to find ind. velocitiess
    s(idx1 ==0,:)= fcnSTARGLOB(tempa(idx1==0,:), vecDVEROLL(idx1==0), vecDVEPITCH(idx1==0), vecDVEYAW(idx1==0));
    
    %using the verticies to do this doesn't match the results from above for idx1 ==0
    % s(idx1==0,:) =(( (matVLST(matDVE(idx1,2),:) + matVLST(matDVE(idx1,3),:))./2 ) -...
    %     ( (matVLST(matDVE(idx1,1),:) + matVLST(matDVE(idx1,4),:))./2 ) )./ (vecDVEHVSPN.*2);
    
end

% 80% of halfspan
eta8 = vecDVEHVSPN*0.8;

% UxS
% tempb = cross(repmat(matUINF,[valNELE,1]),s,2);
nUINF = matUINF ./ sqrt(sum(matUINF.^2,2));
tempb = cross(matUINF, s, 2);


uxs = sqrt(sum(abs(tempb).^2,2));

en = tempb.*repmat((1./uxs),1,3);

len = size(nUINF,1);

% I didn't want to do this, Alton made me because he is cruel and gross
% T.D.K 2017-07-10
spandir = zeros(len,3);
for i = 1:max(vecDVEVEHICLE)
%     l = sum(nonzeros(vecDVEVEHICLE == i));
%     spandir(vecDVEVEHICLE == i,:) = fcnSTARGLOB([0 1 0], matVEHROT(i,1), matVEHROT(i,2), matVEHROT(i,3));
    spandir(vecDVEVEHICLE == i,:) = repmat([0 1 0] * angle2dcm(matVEHROT(i,3), matVEHROT(i,1), matVEHROT(i,2),'ZXY'),length(nonzeros(vecDVEVEHICLE == i)),1);
end

% Implemented on a vehicle-by-vehicle basis - TDK 2017-07-10
el = cross(nUINF,spandir,2);

% the side force direction eS=UxeL/|UxeL|
% clear tempa tempb
tempc = cross(el,matUINF,2);
es = tempc.*1./ repmat((sqrt(sum(abs(tempc).^2,2)) ),1,3);

% clear tempa
%% normal force due to freestream

% N_free = (A*2*eta + C/3*2*eta*eta*eta)*UxS;
% if first row, A=A, B=B, C=C
A = zeros(1,valNELE);
B = zeros(1,valNELE);
C = zeros(1,valNELE);

A(idx1) = matCOEFF(idx1,1);
B(idx1) = matCOEFF(idx1,2);
C(idx1) = matCOEFF(idx1,3);
% if any other row, A= A-Aupstream, B= B-Bupstream, C= C-Cupstream

idx2 = vecDVELE == 1; %idx2 since we need to do this even for triangles
dvenum = find(idx2==0); %dvenum in question
idxf = matADJE((ismember(matADJE(:,1), dvenum) & matADJE(:,2) == 1),3); %upstream dve num
A(idx2 ==0) = (matCOEFF(idx2==0,1)-matCOEFF(idxf,1));
B(idx2 ==0) = (matCOEFF(idx2==0,2)-matCOEFF(idxf,2));
C(idx2 ==0) = (matCOEFF(idx2==0,3)-matCOEFF(idxf,3));


nfree = ((A .*2 .* vecDVEHVSPN'+  C./3.*2.*vecDVEHVSPN'.*vecDVEHVSPN'.*vecDVEHVSPN') .*uxs')';

%% induced force
% for triangluar elements we compute velocities directly at LE. idx1 = 1
% for all elements. 

% for first row (m=1):
%	compute 3 velocities along LE of DVE

% for remaining rows (m>1):
%	3 velocities are average of element center and upstream DVE center

% element leading edge midpoint of LE elements only:
xle = (matVLST(matDVE(idx1,1),:) + matVLST(matDVE(idx1,2),:))/2;

% fpg will be all points that we grab velocity at. It will be
% valNELE x XYZ x 3 for now, then we will reshape after
fpg = zeros(valNELE,3,3);

% leading edge row:
fpg(idx1,:,1) = (xle + s(idx1==1,:).*repmat(-eta8(idx1==1),1,3)); %left side
fpg(idx1,:,2) = xle ; %middle
fpg(idx1,:,3) = (xle + s(idx1==1,:).*repmat(eta8(idx1==1),1,3)); %right ride

% Remaining rows:
if any(idx1 == 0)
    fpg(idx1==0,:,1) = (matCENTER(idx1==0,:) + s(idx1==0,:).*repmat(-eta8(idx1==0),1,3)); %left side
    fpg(idx1==0,:,2) = matCENTER(idx1==0,:) ; %middle
    fpg(idx1==0,:,3) = (matCENTER(idx1==0,:) + s(idx1==0,:).*repmat(eta8(idx1==0),1,3)); %right ride
end

% if there are any elements in not the first row, we will append all the LE center
% points to the bottom, necessary for averaging. the if statement will be ignored if all m=1.
% need to remove tan, we should already have the vector
if any(idx1 == 0)
    fpg(1:(valNELE+sum(idx1)),:,1) = [fpg(1:valNELE,:,1) ; (matCENTER(idx1==1,:) + repmat(tan(vecDVEMCSWP(idx1==1)).*-eta8(idx1==1),1,3))]; %left side
    fpg(1:(valNELE+sum(idx1)),:,2) = [fpg(1:valNELE,:,2) ; matCENTER(idx1==1,:)] ; %middle
    fpg(1:(valNELE+sum(idx1)),:,3) = [fpg(1:valNELE,:,3) ; (matCENTER(idx1==1,:) + repmat(tan(vecDVEMCSWP(idx1==1)).*eta8(idx1==1),1,3))]; %right ride
end

len = size(fpg,1);

% take second dimension, move to bottom. then take third dimension and move
% to bottom
fpg = reshape(permute(fpg,[1 3 2]),[],3);

% get velocities
[w_total] = fcnINDVEL(fpg,valNELE, matDVE, matVLST, matCOEFF, vecK, vecDVEHVSPN, vecDVEHVCRD, vecDVEROLL, vecDVEPITCH, vecDVEYAW, vecDVELESWP, vecDVETESWP, vecDVESYM,...
    valWNELE, matWDVE, matWVLST, matWCOEFF, vecWK, vecWDVEHVSPN,vecWDVEHVCRD,vecWDVEROLL, vecWDVEPITCH, vecWDVEYAW, vecWDVELESWP, vecWDVETESWP, valWSIZE, valTIMESTEP, flagTRI, flagSTEADY, flagGPU);

% undo reshape and permute
% matrix is now LE vels for all LE elements, center vels for remaining DVES,
% and the center vels for the LE elements are appended to the bottom
w_total = permute(reshape(w_total,[],3,3),[1 3 2]);

%grab LE DVE values into final w matrix
w = zeros(valNELE,3,3);
w(idx1,:,:) = w_total(idx1,:,:);

%make a matrix with all DVE center velocities
if any(idx1 ==0)
    w_center = zeros(valNELE,3,3);
    w_center(idx1 ==0,:,:) = w_total(idx1 ==0,:,:);
    w_center(idx1,:,:) = w_total(valNELE+1:end,:,:); %add center vels from LE DVES
    
    %//case of multiple lifting lines along the span
    %//the induced velocity at the lifting line is averaged with the
    %//velocities at mid chord locations of the DVES upstream and
    %//downstream of the bound vortex. Otherwise, the singularity of
    %//the bound vortex and the discontinuity of the bound vortex sheet
    %//of a wing with twist causes trouble.
    w(idx1 ==0,:,:) = (w_center(idx1 ==0,:,:)+w_center(idxf,:,:))./2;
end

% perform integration
tempd = cross(w,repmat(s,[1,1,3]),2);
gamma(:,1) = A - B.*eta8' + C.*eta8'.*eta8';
gamma(:,2) = A;
gamma(:,3) = A + B.*eta8' + C.*eta8'.*eta8';
tempr = tempd .* repmat(permute(gamma,[1 3 2]),1,3,1);

%//The resulting induced force is
%//determined by numerically integrating forces acros element
%//using Simpson's Rule with overhaning parts\
%  R = (R1 + 4*Ro+R2).*eta8/3;
r = (tempr(:,:,1) + 4.*tempr(:,:,2) + tempr(:,:,3)) .* repmat(eta8,1,3) ./3;
%  R = R + ((7.*R1 - 8.*Ro + 7.*R2).*(eta-eta8)./3);
r = r + ((7.*tempr(:,:,1) - 8.*tempr(:,:,2) + 7.*tempr(:,:,3)).*repmat((vecDVEHVSPN-eta8),1,3)./3);

% induced normal force
nind = dot(r,en,2);  %induced normal force

%lift and side force
liftfree = nfree.*sqrt(en(:,1).*en(:,1) + en(:,3).*en(:,3)); %does this work with beta?
liftfree(en(:,3)<0) = -liftfree(en(:,3)<0);
liftind = dot(r,el,2);


sidefree = nfree.*en(:,2);
sideind = dot(r,es,2);