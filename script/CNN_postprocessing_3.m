function [] = CNN_postprocessing_3(output_path, path_download, b0)
% Code 3 of the dentate nucleus (DN) segmentation pipeline
%
% Segmentation and post-processing of the dentate nucleus (DN) from B0 images using a CNN
%
% INPUTS:
%   output_path   - Folder where outputs will be saved and where previous outputs are located
%   path_download - Folder containing the pre-trained CNN model 'rete1.mat'
%   b0            - Full path to the original B0 NIfTI image
%
% OUTPUTS (saved in output_path):
%   - 'DN_CNN_125.nii'      : CNN segmentation in resampled space (1.25 mm)
%   - 'DN_CNN_orig.nii.gz'  : CNN segmentation mapped back to original B0 space
%   - 'DN_CNN_final.nii.gz' : Post-processed segmentation filtered by SUIT mask

%% Define paths to required files from previous steps
b0_resampled_mat = fullfile(output_path, 'b0_125.mat');      % from script 2
seg_den_suit     = fullfile(output_path, 'DN_diff_SUIT.nii.gz');    % from script 1

%% Load CNN model
load(fullfile(path_download, 'rete1.mat'));

%% Initialize segmentation volume
dentati_sa = zeros(86, 71, 66);

if exist(seg_den_suit, 'file') && exist(b0_resampled_mat, 'file')
    % Load normalized B0 image
    b0_img = niftiread(fullfile(output_path, 'B0_N.nii.gz'));
    b0_hdr = niftiinfo(fullfile(output_path, 'B0_N.nii.gz'));
    b0_test = b0_img(30:115, 10:80, 5:70); % crop as in original
    
    % CNN segmentation slice-by-slice
    for slice = 1:66
        [C, score] = semanticseg(b0_test(:,:,slice), net);
        dentati_sa_slice = uint8(C) - 1; % DN = 1, background = 0
        dentati_sa(:,:,slice) = dentati_sa_slice;
    end
    
    % Expand segmentation to full volume
    dent_sa_dim = zeros(145, 174, 145);
    dent_sa_dim(30:115, 10:80, 5:70) = dentati_sa;
    
    % Save CNN segmentation in resampled space
    dentati_sa_hdr = b0_hdr;
    dentati_sa_hdr.Datatype = 'double';
    dentati_sa_img = dent_sa_dim;
    niftiwrite(dentati_sa_img, fullfile(output_path, 'DN_CNN_125.nii'), dentati_sa_hdr);
    unix(horzcat('gzip -f ', output_path, '/DN_CNN_125.nii'));
    
    %% Map segmentation back to original B0 space
    unix(horzcat('convert_xfm -omat ', fullfile(output_path,'b0_125_inv.mat'), ' -inverse ', b0_resampled_mat));
    unix(horzcat('flirt -in ', fullfile(output_path, 'DN_CNN_125.nii.gz'), ' -applyxfm -init ', fullfile(output_path,'b0_125_inv.mat'), ...
        ' -out ', fullfile(output_path,'DN_CNN_orig.nii.gz'), ' -paddingsize 0.0 -interp nearestneighbour -ref ', b0));

    %% Dilate SUIT mask for post processing
    unix(horzcat('fslmaths ', fullfile(output_path, 'DDN_diff_SUIT.nii.gz'), ' -dilM -dilM ', fullfile(output_path, 'DN_diff_SUIT_dil.nii.gz')))
    maschera_dil_img = niftiread(fullfile(output_path, 'DN_diff_SUIT_dil.nii.gz'));
    maschera_dil_hdr = niftiinfo(fullfile(output_path, 'DN_diff_SUIT_dil.nii.gz'));
    
    % Load CNN segmentation in original space
    DN_CNN = niftiread(fullfile(output_path, 'DN_CNN_orig.nii.gz'));
    
    % Apply SUIT mask to CNN segmentation
    DN_CNN_final_vect = maschera_dil_img(:) .* DN_CNN(:);
    DN_CNN_final = reshape(DN_CNN_final_vect, size(DN_CNN));
    
    sa_filtrata_hdr = maschera_dil_hdr;
    sa_filtrata_img = DN_CNN_final;
    
    % Save post-processed segmentation
    niftiwrite(sa_filtrata_img, fullfile(output_path, 'DN_CNN_final.nii'), sa_filtrata_hdr);
    unix(horzcat('gzip -f ', output_path, '/DN_CNN_final.nii'));
    
else
    disp('Required inputs from previous steps not found! Run scripts 1 and 2 first.');
end
