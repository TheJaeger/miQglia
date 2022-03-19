function props = ramificationStatsTest(impath, outpath)
%% Skeleton and Fractal Analysis of Micrographs
% A function designed to extract skeleton and fractal parameters from RGB
% mictographs of ramified cells
%
% Author: Siddhartha Dhiman
%
% Parameters
% ----------
%   impath : str
%       Path to input image file (.tif)
%   outpath : str
%       Path to output directory write out files
% Returns
% -------
%   props : struct
%       Struct containing quantified parameters
%--------------------------------------------------------------------------

    %% Begin
    if ~isfile(impath)
        error('Input file %s does not exist', impath);
    end
    if ~isdir(outpath)
        error('Output path %s is not a directory. Please specify a valid directory.', outpath);
    end
    if ~exist(outpath, 'dir')
        error('Output directory %s does not exist.', outpath)
    end
    %% Define Fixed Variables
    pixel_micron = 0.25;    % Number of microns per pixel in XY. I measured 40 pixels for 10 um (microns)
    tophat_filter = 10;      % Size of top-hat filter. Ideally the spatial size of dendrites (in microns)
    obj_remove = 50;        % Remove features same size or under (in microns)
    min_branch = 5;        % Minimum length of total branch distance (microns)

    %% Internal Pixel <--> Pixel Conversion (DO NOT ALTER!)
    obj_remove_pixel = round(obj_remove / pixel_micron, 0);
    pixel_micron_diag = sqrt(2* pixel_micron^2); % Diagonal distance of voxel
    pixel_micron_area =  pixel_micron^2; % Area of one pixel
    nhood1 = 10; % Neighborhood size of disk-shaped structuring element for initial erosion
    nhood2 = 3;  % Neighborhood size of disk-shaped structuring element closing
    nhood_th = round(tophat_filter / pixel_micron);
    %% Main
    [fpath,fname,fext] = fileparts(impath);
    img = imread(impath);
    % Maximum intensity projection to convert to grayscale
    mip = rgbmip(img);
    mip_ = uint8(max(mip(:))) - mip;     % inverted image;
    % Denoise image with 2D Weiner filter
    dnI = wiener2(mip_, [5,5]);
    % Remove redundant background
    thI = imtophat(dnI, strel('disk', nhood_th));
    % FFT bandpass filter to remove noise
%     fftI = fft_bandpass(thI, 10, 100, 1);       % GOOD FOR SOMA DETECTION
    % Sharpen image
%     shI = imsharpen(thI, 'Radius', 3, 'Amount', 0.6);
    
    % Remove extreme pixel values and normalize from 0 to 1
    bot = double(prctile(thI(:),1));
    top = double(prctile(thI(:),99));
    I = (double(thI)-bot) / (top - bot);
    I(I>1) = 1; % do the removing
    I(I<0) = 0; % do the removing
    
    %% Create cellular mask
    mask = I > .10;
    mask = bwareaopen(mask, 500);
    
    %% Find Seeds
    I_smooth = imgaussfilt(I, 2);
%     seeds = imregionalmax(I_smooth);
%     seeds = imextendedmax(I_smooth, double(prctile(I_smooth(:),85)), 4);
    seeds = I >= 0.90;
    % Remove small objects
    seeds = bwareaopen(seeds, 200);
    % ADD METHOD TO REMOVE NON-ELLIPTICAL OBJECTS
    % Connect seeds close to each other
    seeds = bwmorph(seeds, 'bridge');
    seeds = bwmorph(imfill(seeds, 'holes'), 'shrink', Inf);
    seeds(mask==0)=0; % remove seeds outside of our cyto mask
    [X, Y] = find(seeds);
    
%     figure('name','seeds','NumberTitle', 'off')
%     imshow(I,[]);
%     hold on;
%     plot(Y,X,'or','markersize',2,'markerfacecolor','r')
    
    %% Watershed
    I_smooth = imgaussfilt(I, 1); % don't smooth too much for watersheding
    I_min = imimposemin(max(I_smooth(:)) - I_smooth, seeds); % set locations of seeds to be -Inf (cause matlab watershed)
    L = watershed(I_min);
    L(mask==0)=0; % remove areas that aren't in our cellular mask
    binWatershed = L > 0;
    binWatershed = imclearborder(binWatershed);
%     binWatershed = imerode(binWatershed, strel('disk', 3));
    binWatershed = bwmorph(binWatershed, 'shrink', 2);
    L = L .* uint8(binWatershed);
    
    figure;
    imshow(labeloverlay(labeloverlay(img, imdilate(bwperim(L), ones(2,2)), 'Colormap', [0 0 1], 'Transparency', 0.5), mask, 'Colormap', [0 1 0], 'Transparency', 1));
    hold on;
    plot(Y,X,'x','markersize',10,'markeredgecolor','g','markeredgecolor','r');
    plot(Y,X,'o','markersize',10,'markeredgecolor','g','markeredgecolor','r')
    hold off;
    
    % Restore image to unint8
    I = uint8(I*255);
    
    img_props = zeros(size(mip), 'logical');
    img_skel = zeros(size(mip), 'logical');
    props = struct([]);
    iterL = unique(L); iterL(1) = [];
    cnt = 0;
    processIdx = [];
    for i = 1:length(iterL)
        cell = L == iterL(i);
%         maskI = I .* uint8(mask);
        % Binarize image using Otsu's thresholding
%         bwI = imbinarize(maskI, 'global');
        % Morphologically close image
%         bwI_close = imclose(bwI, strel('disk', 5));
%         bwI_holes = imfill(bwI_close, 'holes');
        % Remove small features
        bwI_open = bwareaopen(cell, 2000);
        % Go through IF loop only when voxels are detected AND there's one
        % continuous structure
        if nnz(bwI_open) > 0 & max(bwlabel(bwI_open), [], 'all') == 1
            processIdx(i) = 1;
            cnt = cnt + 1;
            img_props = bwI_open;
            % Skeletonize image
            skel = bwskel(bwI_open);
            img_skel = img_skel + skel;
            props(i).Index = cnt;
            props(i).BranchPoints = nnz(bwmorph(skel, 'branchpoints'));
            props(i).EndPoints = nnz(bwmorph(skel, 'endpoints'));
            skel_props_ = regionprops(logical(skel), 'BoundingBox');
            skel_props = regionprops(logical(skel - bwmorph(skel, 'branchpoints')), 'BoundingBox', 'Area', 'Perimeter', 'Image');
            props(i).Branches = size(skel_props, 1);
            props(i).MaxBranchLength = max(extractfield(skel_props, 'Perimeter')/2);
            props(i).AverageBranchLength = mean(extractfield(skel_props, 'Perimeter')/2);
            props(i).TotalBranchLength = sum(extractfield(skel_props, 'Perimeter')/2);
            maskI_props = regionprops(bwI_open, 'BoundingBox', 'Area', 'Circularity', 'ConvexArea', 'ConvexImage', 'Image', 'MajorAxisLength', 'MinorAxisLength');
            x = fix(maskI_props.BoundingBox(1));
            y = fix(maskI_props.BoundingBox(2));
            bx = fix(maskI_props.BoundingBox(3));
            by = fix(maskI_props.BoundingBox(4));
            soma = imcrop(bwI_open, [x, y, bx, by]);
            props(i).BoundingBox = maskI_props(1).BoundingBox;
            props(i).Area = maskI_props(1).Area;
            props(i).FractalDimension = hausDim(bwI_open);
            props(i).Circularity = maskI_props(1).Circularity;
            props(i).SpanRatio =  maskI_props(1).MinorAxisLength / maskI_props(1).MajorAxisLength;
            props(i).Density = nnz(bwperim(bwI_open)) / maskI_props(1).ConvexArea;
        else
            processIdx(i) = 0;
            continue;
        end
    end
    img_props = logical(img_props);
    img_skel = logical(img_skel);
    % Compress props by removing empty fields
    props = props(all(~cellfun(@isempty,struct2cell(props))));
    % Convert to microns
    for i = 1:length(props)
        props(i).MaxBranchLength = props(i).MaxBranchLength * pixel_micron;
        props(i).AverageBranchLength = props(i).AverageBranchLength * pixel_micron;
        props(i).TotalBranchLength = props(i).TotalBranchLength  * pixel_micron;
        props(i).Area = props(i).Area * pixel_micron_area;
    end
        
    % Filter results based on thresholds
    rmIdx = extractfield(props, 'EndPoints') == 2 & extractfield(props, 'MaxBranchLength') < min_branch;
    props = props(~rmIdx);
    totalEndPoints = sum(extractfield(props, 'EndPoints'));
    rmIdx = extractfield(props, 'TotalBranchLength') < min_branch;
    props = props(~rmIdx);
    totalBranchLength = sum(extractfield(props, 'TotalBranchLength'));
    
    % Reindex
    for i = 1:length(props)
        props(i).Index = i;
    end

    fout = fullfile(outpath, strcat('Labels', '_', fname, '.png'));
    fig2 = figure('visible', 'off', 'WindowState','maximized');
    imshow(labeloverlay(labeloverlay(img, img_props, 'Colormap', [0 1 0], 'Transparency', 0.85), img_skel, 'Colormap', [1 0 0], 'Transparency', 0.10));
    hold on;
    for i = 1:size(props, 2)
        rectangle('Position', props(i).BoundingBox, 'EdgeColor', 'r',...
            'LineWidth', 0.5, 'LineStyle', ':');
        text(props(i).BoundingBox(1)+5, props(i).BoundingBox(2)+10,...
            num2str(props(i).Index), 'FontSize', 12);
    end
    hold off;
    title(strcat(fname, ': Detected Somas and Labels'), 'Interpreter', 'none');
    saveas(fig2, fout, 'png');
    
    % Write properties
    props = rmfield(props, 'BoundingBox');
    fname_table = fullfile(outpath, strcat('Stats_', fname, '.csv'));
    writetable(struct2table(props), fname_table);
    