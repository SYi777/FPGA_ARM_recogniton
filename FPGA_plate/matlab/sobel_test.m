%% 读取图像
originalImage = imread('testst.png');
figure;
%% 定义阈值
thre = 55;
%      -1   0  +1    %      +1   2  +1
% gx = -2   0  +2    % gy =  0   0  0
%      -1   0  +1    %      -1  -2  -1

%% 显示原图
subplot(1, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
sobelImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 4;  % 窗口大小 
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height);%窗口下边界
        c1 = max(j - halfWindowSize, 1);%窗口左边界
        c2 = min(j + halfWindowSize, img_width);%窗口右边界
        
        % 提取窗口
        window = double(grayImage(r1:r2, c1:c2));
        
        % 计算窗口GX GY
        GX = window(1,3)+2*window(2,3)+window(3,3)-window(1,1)-2*window(2,1)-window(3,1);
        GY = window(1,1)+2*window(1,2)+window(1,3)-window(3,1)-2*window(3,2)-window(3,3);
        %计算G
        G= sqrt(GX^2+GY^2);
        %G=abs(GX)+abs(GY);
        if G > thre %比阈值大 视为边沿
            sobelImage(i,j) = 0;
        else
            sobelImage(i,j) = 255;
        end
        
    end
end
%% 无符号8bit
sobelImage = uint8(sobelImage);   
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);

% 显示原图和处理后的图像
subplot(1, 3, 2);
imshow(grayImage);
imwrite(grayImage,'gray.png')
title('灰度化图像');

subplot(1, 3, 3);
imshow(sobelImage);
imwrite(sobelImage,'D:\pango_isp\img_test_pg\img_test_pg\01_led_test\sim\matlab_sobel.png')
title('sobel处理后的图像');
