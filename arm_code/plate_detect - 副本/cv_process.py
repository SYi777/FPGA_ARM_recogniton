import cv2
import numpy as np
import time
from PIL import Image, ImageDraw, ImageFont

class CVImageProcessor:
    """图像处理与可视化类（融合了颜色判断与裁剪绘制等功能）"""
    def __init__(self, gamma=1.5):
        self.gamma = gamma
        # 定义颜色范围
        self.lower_blue = np.array([100, 43, 46])
        self.upper_blue = np.array([124, 255, 255])
        self.lower_yellow = np.array([15, 40, 46])
        self.upper_yellow = np.array([34, 255, 255])
        self.lower_green = np.array([35, 43, 46])
        self.upper_green = np.array([77, 255, 255])
        self.lower_black = np.array([0, 0, 0])
        self.upper_black = np.array([180, 255, 46])
        self.lower_white = np.array([0, 0, 221])
        self.upper_white = np.array([180, 30, 255])

    def gamma_correction(self, image_gray):
        """对灰度图进行 Gamma 矫正"""
        invGamma = 1.0 / self.gamma
        table = np.array([((i / 255.0) ** invGamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
        return cv2.LUT(image_gray, table)

    def draw_chinese_text(self, img, text, position, textColor=(0, 255, 0), textSize=30):
        """利用 PIL 在图像上绘制中文字符"""
        if isinstance(img, np.ndarray):
            img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        draw = ImageDraw.Draw(img)
        fontStyle = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", textSize, encoding="utf-8")
        draw.text(position, text, textColor, font=fontStyle)
        return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)

    def draw_result(self, img, pts, text):
        """在图像上绘制包围框和中文识别结果"""
        x1, y1, x2, y2 = pts
        cv2.rectangle(img, (int(x1), int(y1)), (int(x2), int(y2)), (0, 0, 255), 2)
        return self.draw_chinese_text(img, text, (int(x1), max(int(y1)-30, 0)), textColor=(0, 255, 0), textSize=30)

    def draw_fps(self, draw_img, mode_text=""):
        """绘制当前帧率和模式文本（内部计算帧率）"""
        # 初始化上次计时
        if not hasattr(self, '_last_time'):
            self._last_time = time.time()
            self._fps = 0.0

        curr_time = time.time()
        elapsed = curr_time - self._last_time
        # 简单平滑：若 elapsed 很小，避免除零
        if elapsed > 0:
            instant_fps = 1.0 / elapsed
            # 指数移动平均平滑 fps，alpha 控制平滑程度
            alpha = 0.3
            self._fps = alpha * instant_fps + (1 - alpha) * getattr(self, '_fps', instant_fps)
        else:
            instant_fps = getattr(self, '_fps', 0.0)

        self._last_time = curr_time

        text = f"FPS: {self._fps:.2f}"
        if mode_text:
            text += f" | Mode: {mode_text}"
        cv2.putText(draw_img, text, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
        return draw_img

    def extract_padded_box(self, origin_img, box, pad_w_ratio=0.08, pad_h_ratio=0.15):
        """
        根据指定的边界框和扩展比例，从原图中安全地提取车牌 ROI
        :param origin_img: 原图 (BGR)
        :param box: [x1, y1, x2, y2]
        :param pad_w_ratio: 宽度的外扩比例
        :param pad_h_ratio: 高度的外扩比例
        :return: (plate_img, padded_box)
        """
        x1, y1, x2, y2 = map(int, box)
        pad_w = int((x2 - x1) * pad_w_ratio)
        pad_h = int((y2 - y1) * pad_h_ratio)
        
        cx1, cy1 = max(0, x1 - pad_w), max(0, y1 - pad_h)
        cx2, cy2 = min(origin_img.shape[1], x2 + pad_w), min(origin_img.shape[0], y2 + pad_h)
        
        plate_img = origin_img[cy1:cy2, cx1:cx2]
        return plate_img, [cx1, cy1, cx2, cy2]

    def get_color(self, img_patch):
        if img_patch.size == 0:
            return '未知'
        hsv = cv2.cvtColor(img_patch, cv2.COLOR_BGR2HSV)
        mask_blue = cv2.inRange(hsv, self.lower_blue, self.upper_blue)
        mask_yellow = cv2.inRange(hsv, self.lower_yellow, self.upper_yellow)
        mask_green = cv2.inRange(hsv, self.lower_green, self.upper_green)
        mask_black = cv2.inRange(hsv, self.lower_black, self.upper_black)
        mask_white = cv2.inRange(hsv, self.lower_white, self.upper_white)
        
        counts = {
            'blue': cv2.countNonZero(mask_blue),
            'yellow': cv2.countNonZero(mask_yellow),
            'green': cv2.countNonZero(mask_green),
            'black': cv2.countNonZero(mask_black)
        }
        
        color_type = max(counts, key=counts.get)

        return color_type

    def determine_plate_color(self, plate_img):
        """基于 HSV 颜色空间的区域判断车牌颜色属性"""
        if plate_img is None or plate_img.size == 0:
            return "未知"
            
        h, w = plate_img.shape[:2]
        left_img = plate_img[:, :int(w * 0.3)]
        right_img = plate_img[:, -int(w * 0.6):]

        left_color = self.get_color(left_img)
        right_color = self.get_color(right_img)

        if left_color == 'yellow' and right_color == 'green':
            return '新能源大型车'

        if right_color == 'yellow':
            return '单层黄牌'
        elif right_color == 'green':
            return '新能源小型车'
        elif right_color == 'blue':
            return '普通蓝牌'
        else:
            return '未知'

    def extract_plate_corners(self, plate_img):
        """
        通过灰度化、高斯模糊、Sobel算子、形态学等方式提取车牌边缘，
        最终利用 findContours 找到面积最大的外界矩形，并返回四个角点
        :param plate_img: 彩色车牌图像 ROI
        :return: (4, 2) 形状的 np.ndarray (float32) 代表角点，如果未找到则返回 None
        """
        if plate_img is None or plate_img.size == 0:
            return None
            
        gray = cv2.cvtColor(plate_img, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Sobel 提取垂直边缘信息（车牌字符造成的垂直梯度很强）
        sobelx = cv2.Sobel(blurred, cv2.CV_16S, 1, 0, ksize=3)
        absX = cv2.convertScaleAbs(sobelx)
        
        # 二值化
        _, binary = cv2.threshold(absX, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # 形态学操作将零碎的字符边缘联结成一体
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 3))
        closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
        
        # 寻找轮廓
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return None
            
        c = max(contours, key=cv2.contourArea)
        rect = cv2.minAreaRect(c)
        box = cv2.boxPoints(rect)
        
        pts = box.reshape(4, 2).astype(np.float32)
        
        # 排序角点: 左上、右上、右下、左下
        rect_pts = np.zeros((4, 2), dtype=np.float32)
        s = pts.sum(axis=1)
        diff = pts[:, 0] - pts[:, 1]
        
        rect_pts[0] = pts[np.argmin(s)]    # 左上
        rect_pts[2] = pts[np.argmax(s)]    # 右下
        rect_pts[1] = pts[np.argmax(diff)] # 右上
        rect_pts[3] = pts[np.argmin(diff)] # 左下
        
        return rect_pts

    def perspective_transform(self, img, pts):
        """
        利用给定的四个角点将图像进行透视变换，拉正为平整的矩形图
        :param img: 要形变的图像
        :param pts: [[左上角], [右上角], [右下角], [左下角]] float32格式的锚点
        :return: 拉正后的图像，拉正失败返回原本 img
        """
        if pts is None or len(pts) != 4:
            return img

        (tl, tr, br, bl) = pts
        
        # 计算最大宽度
        widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
        widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
        maxWidth = max(int(widthA), int(widthB))
        
        # 计算最大高度
        heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
        heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
        maxHeight = max(int(heightA), int(heightB))
        
        if maxWidth <= 10 or maxHeight <= 10:
            return img
            
        dst_pts = np.array([
            [0, 0],
            [maxWidth - 1, 0],
            [maxWidth - 1, maxHeight - 1],
            [0, maxHeight - 1]
        ], dtype="float32")
        
        M = cv2.getPerspectiveTransform(pts, dst_pts)
        warped_img = cv2.warpPerspective(img, M, (maxWidth, maxHeight))
        
        return warped_img
