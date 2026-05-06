import cv2
import numpy as np

class RedBoxDetector:
    """查找图片中国纯红色的框(R=255, G=0, B=0左右)"""
    def __init__(self):
        pass

    def detect(self, img):
        """
        检测图像中的红色框（车牌）
        :param img: 输入图像(BGR格式)
        :return: 检测到的框列表，每个框为[x1, y1, x2, y2]格式
        """
        # 红色在 BGR 通道中是 [0, 0, 255]
        # 这里为了容错，允许G和B有小幅波动，R有大幅波动
        lower_red1 = np.array([0, 0, 240])
        upper_red1 = np.array([0, 0, 255])

        mask = cv2.inRange(img, lower_red1, upper_red1)

        # 寻找轮廓
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        valid_boxes = []
        for c in contours:
            x, y, w, h = cv2.boundingRect(c)
            # 过滤掉太小的噪点
            if w > 20 and h > 10:
                valid_boxes.append([x, y, x + w, y + h])

        return valid_boxes