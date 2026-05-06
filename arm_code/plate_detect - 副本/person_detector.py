import os
import cv2
import time
import numpy as np
from ultralytics import YOLO

class PersonDetector:
    """行人检测类，基于YOLO模型"""

    def __init__(self, model_path):
        """
        初始化行人检测器

        Args:
            model_path: YOLO模型路径
        """
        print("加载行人检测YOLO模型...")
        self.model = YOLO(model_path, task='detect')
        print("行人检测模型加载完成")

    def detect(self, img, conf_threshold=0.5):
        """
        检测图像中的行人

        Args:
            img: 输入图像
            conf_threshold: 置信度阈值

        Returns:
            list: 包含检测结果的列表，每个元素为[x1, y1, x2, y2, confidence]
        """
        results = self.model(img, verbose=False)
        res = results[0]

        detections = []

        if hasattr(res, 'boxes') and res.boxes is not None:
            for box, cls, conf in zip(res.boxes.xyxy.cpu().numpy(),
                                    res.boxes.cls.cpu().numpy(),
                                    res.boxes.conf.cpu().numpy()):
                # 只检测行人（YOLO中person的类别ID为0）
                if int(cls) == 0 and conf >= conf_threshold:
                    x1, y1, x2, y2 = map(int, box)
                    # 确保坐标在图像范围内
                    x1, y1 = max(0, x1), max(0, y1)
                    x2, y2 = min(img.shape[1], x2), min(img.shape[0], y2)

                    if x2 > x1 and y2 > y1:
                        detections.append([x1, y1, x2, y2, float(conf)])

        return detections

    def draw_detections(self, img, detections):
        """
        在图像上绘制检测结果

        Args:
            img: 输入图像
            detections: 检测结果列表

        Returns:
            numpy.ndarray: 绘制了检测框的图像
        """
        draw_img = img.copy()

        for det in detections:
            x1, y1, x2, y2, conf = det

            # 绘制边界框
            cv2.rectangle(draw_img, (x1, y1), (x2, y2), (255, 0, 0), 2)

            # 绘制标签
            label = f"Person {conf:.2f}"
            cv2.putText(draw_img, label, (x1, max(y1-10, 0)),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)

        return draw_img

def main():
    """行人检测独立运行的主函数"""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    person_detector_path = os.path.join(base_dir, "yolo26n_ncnn_model")

    detector = PersonDetector(person_detector_path)

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("无法打开摄像头")
        return

    print("按 q 或 ESC 退出行人检测")

    prev_time = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        curr_time = time.time()
        fps = 1 / (curr_time - prev_time) if curr_time != prev_time else 0
        prev_time = curr_time

        # 检测行人
        detections = detector.detect(frame)

        # 绘制结果
        result_img = detector.draw_detections(frame, detections)

        # 显示FPS
        cv2.putText(result_img, f"FPS: {fps:.2f} | Persons: {len(detections)}",
                   (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)

        cv2.imshow("Person Detection (NCNN)", result_img)

        key = cv2.waitKey(1) & 0xFF
        if key == 27 or key == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()