import cv2
import numpy as np

def double_plate_cut(plate_img):
    h, w = plate_img.shape[:2]
    w_start = int(w * 0.15)
    w_end = int(w * 0.85)
    top_img = plate_img[:int(h * 0.5), w_start:w_end]
    bottom_img = plate_img[int(h * 0.4):, :]

    # 调整上层图和下层图高度一致以便合并
    h_bottom = bottom_img.shape[0]
    top_img_resized = cv2.resize(top_img, (top_img.shape[1], h_bottom))

    # 左右拼接
    combined_img = np.hstack((top_img_resized, bottom_img))

    return combined_img

def detect_text_color(plate_img):
    """
    检测文字颜色：黑色或白色
    """
    h, w = plate_img.shape[:2]
    gray = cv2.cvtColor(plate_img, cv2.COLOR_BGR2GRAY)
    
    # 使用自适应阈值提取文字区域
    binary = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                                  cv2.THRESH_BINARY, 11, 2)
    
    # 在原图中采样文字区域的颜色
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    black_pixels = 0
    white_pixels = 0
    
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < 50 or area > h*w*0.1:  # 过滤过大过小的区域
            continue
            
        x, y, cw, ch = cv2.boundingRect(contour)
        if ch < h*0.3 or cw < w*0.05:  # 过滤非字符区域
            continue
            
        # 提取字符区域
        char_region = plate_img[y:y+ch, x:x+cw]
        
        # 转换为HSV分析颜色
        hsv_char = cv2.cvtColor(char_region, cv2.COLOR_BGR2HSV)
        
        # 黑色文字检测（低亮度）
        lower_black = np.array([0, 0, 0])
        upper_black = np.array([180, 255, 80])
        mask_black = cv2.inRange(hsv_char, lower_black, upper_black)
        black_pixels += cv2.countNonZero(mask_black)
        
        # 白色文字检测（高亮度、低饱和度）
        lower_white = np.array([0, 0, 200])
        upper_white = np.array([180, 60, 255])
        mask_white = cv2.inRange(hsv_char, lower_white, upper_white)
        white_pixels += cv2.countNonZero(mask_white)
    
    return "black" if black_pixels > white_pixels else "white"

def double_plate_check(plate_img, color):
    if plate_img is None or plate_img.size == 0:
        return plate_img, color

    h, w = plate_img.shape[:2]
    # 用 HSV 判断白/黑
    hsv = cv2.cvtColor(plate_img, cv2.COLOR_BGR2HSV)

    if color == '新能源小型车':
        # 调用 detect_text_color 检测文字颜色
        text_color = detect_text_color(plate_img)
        
        # 根据文字颜色设置 HSV 掩码范围
        if text_color == 'white':
            lower = np.array([0, 0, 220])
            upper = np.array([180, 60, 255])
        else:  # black
            lower = np.array([0, 0, 0])
            upper = np.array([180, 255, 80])  # 使用 detect_text_color 中的黑色范围
        
        mask = cv2.inRange(hsv, lower, upper)

        # 去噪与连通
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=1)

        # 找轮廓并过滤小区域
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return plate_img, color

        ys = []
        img_area = h * w
        for c in contours:
            area = cv2.contourArea(c)
            if area < max(10, img_area * 0.0005):
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            ys.append(y + ch // 2)  # 中心y坐标

        if not ys:
            return plate_img, color

        # 将中心 y 坐标聚类为若干行：按 y 排序并计算相邻差距
        ys = sorted(ys)
        groups = [ys[0:1]]
        for val in ys[1:]:
            if abs(val - groups[-1][-1]) > max(10, h * 0.1):
                groups.append([val])
            else:
                groups[-1].append(val)

        # 如果有两组或以上，视为双层字符
        if len(groups) >= 2:
            combined_img = double_plate_cut(plate_img)
            return combined_img, "拖拉机绿牌"
        else:
            return plate_img, color

    elif color == '单层黄牌':
        # 对黄牌，文字为黑色。用黑色/深色掩码提取字符
        lower_black = np.array([0, 0, 0])
        upper_black = np.array([180, 255, 90])
        mask = cv2.inRange(hsv, lower_black, upper_black)

        # 去噪与连通
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=1)

        # 找轮廓并过滤小区域
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return plate_img, color

        ys = []
        img_area = h * w
        for c in contours:
            area = cv2.contourArea(c)
            if area < max(10, img_area * 0.0005):
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            ys.append(y + ch // 2)  # 中心y坐标

        if not ys:
            return plate_img, color

        # 将中心 y 坐标聚类为若干行：按 y 排序并计算相邻差距
        ys = sorted(ys)
        groups = [ys[0:1]]
        for val in ys[1:]:
            if abs(val - groups[-1][-1]) > max(10, h * 0.1):
                groups.append([val])
            else:
                groups[-1].append(val)

        # 如果有两组或以上，视为双层字符
        if len(groups) >= 2:
            combined_img = double_plate_cut(plate_img)
            return combined_img, "双层黄牌"
        else:
            return plate_img, color

    else:
        # 其他颜色直接返回原图
        return plate_img, color