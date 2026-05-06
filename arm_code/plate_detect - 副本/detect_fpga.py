import cv2
from lprnet import LPRNetRecognizer
from cv_process import CVImageProcessor
from double_plate import double_plate_check
import torch
from wordbank import CHARS, SPECIALS, PROVINCES, WORDS
import time
import signal
import sys
from person_detector import PersonDetector
from performance_timer import PerformanceTimer
from cv_detect import RedBoxDetector

class PlateDetectorFPGA:
    def __init__(self, lpr_model_path, person_detector_path=None, enable_timing=True):

        self.red_box_detector = RedBoxDetector()
        self.lpr_recognizer = LPRNetRecognizer(lpr_model_path, chars=CHARS)
        self.cv_processor = CVImageProcessor(gamma=1.5)
        self.person_detector = None
        if person_detector_path:
            self.person_detector = PersonDetector(person_detector_path)
        self.mode = 'plate'  # plate or person

        self.performance_timer = PerformanceTimer(enabled=enable_timing)
        self.performance_timer.setup_signal_handler()

    def clean_plate_string(self, text, plate_color):
        if not text:
            return "", plate_color

        if text[-1] == '使' and text[0] in PROVINCES:
            text = text[1:]

        res = []
        for c in text:
            if not res:
                if c in PROVINCES or c in WORDS:
                    res.append(c)
            else:
                if c in WORDS:
                    res.append(c)
                elif c in SPECIALS:
                    res.append(c)

        final_res = []
        for i, c in enumerate(res):
            if c in SPECIALS:
                if i == len(res) - 1:
                    final_res.append(c)
            else:
                final_res.append(c)

        has_province = (len(final_res) > 0 and final_res[0] in PROVINCES)
        max_len = 8 if has_province else 7

        clean_str = "".join(final_res)[:max_len]

        if clean_str and clean_str[-1] in SPECIALS:
            last_char = clean_str[-1]
            if last_char in ["警", "港", "澳", "使", "领"]:
                plate_color = "黑色车牌"
            elif last_char == "临":
                plate_color = "拖拉机绿牌"
            elif last_char == "挂":
                plate_color = "双层黄牌"

        return clean_str, plate_color

    def process_plate_roi(self, img, box):
        plate_img, padded_box = self.cv_processor.extract_padded_box(img, box, pad_w_ratio=0.0, pad_h_ratio=0.10)
        if plate_img.size == 0:
            return None

        plate_img = self.cv_processor.gamma_correction(plate_img)

        start_time = time.time()
        plate_color = self.cv_processor.determine_plate_color(plate_img)
        color_detect_time = time.time() - start_time
        self.performance_timer.record_time("cv_processor.determine_plate_color", color_detect_time)

        # 加了边缘检测与透视拉正后有时画错边缘得不偿失
        # pts = self.cv_processor.extract_plate_corners(plate_img)
        # if pts is not None:
        #     warped_img = self.cv_processor.perspective_transform(plate_img, pts)
        # else:
        warped_img = plate_img

        gray = cv2.cvtColor(warped_img, cv2.COLOR_BGR2GRAY)

        start_time = time.time()
        pred_str = self.lpr_recognizer.recognize(gray)
        lpr_time = time.time() - start_time
        self.performance_timer.record_time("lpr_recognizer.recognize", lpr_time)

        start_time = time.time()
        warped_img, plate_color = double_plate_check(warped_img, plate_color)
        double_plate_time = time.time() - start_time
        self.performance_timer.record_time("double_plate_check", double_plate_time)

        start_time = time.time()
        clean_str, plate_color = self.clean_plate_string(pred_str, plate_color)
        clean_time = time.time() - start_time
        self.performance_timer.record_time("clean_plate_string", clean_time)

        print(f"车牌号: '{clean_str}' | 车牌: {plate_color}")

        return {
            "box": box,
            "padded_box": padded_box,
            "color": plate_color,
            "text": clean_str,
            "raw_text": pred_str,
            "plate_img": warped_img, 
        }

    def detect_and_recognize(self, img, display_plate=True):
        results = []
        draw_img = img.copy()

        draw_img = self.cv_processor.draw_fps(draw_img)

        start_time = time.time()
        boxes = self.red_box_detector.detect(img)
        red_box_time = time.time() - start_time
        self.performance_timer.record_time("red_box_detector.detect", red_box_time)

        if boxes:
            for i, box in enumerate(boxes):
                res = self.process_plate_roi(img, box)
                if res is not None:
                    results.append(res)
                    display_text = f"[{res['color']}] {res['text']}"
                    draw_img = self.cv_processor.draw_result(draw_img, res['box'], display_text)

                    if display_plate and res['plate_img'] is not None:
                        plate_display = res['plate_img'].copy()

                        cv2.imshow(f'Plate {i+1}', plate_display)

        return results, draw_img

    def detect_persons(self, img):
        if self.person_detector is None:
            return [], img

        detections = []
        draw_img = img.copy()

        draw_img = self.cv_processor.draw_fps(draw_img, "Person Detection")

        start_time = time.time()
        person_detections = self.person_detector.detect(img)
        person_detect_time = time.time() - start_time
        self.performance_timer.record_time("person_detector.detect", person_detect_time)

        for det in person_detections:
            x1, y1, x2, y2, conf = det
            detections.append({
                "box": [x1, y1, x2, y2],
                "confidence": conf,
                "type": "person"
            })

            cv2.rectangle(draw_img, (x1, y1), (x2, y2), (255, 0, 0), 2)
            label = f"Person {conf:.2f}"
            cv2.putText(draw_img, label, (x1, max(y1-10, 0)),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)

        return detections, draw_img

    def toggle_mode(self):
        if self.mode == 'plate':
            self.mode = 'person'
        else:
            self.mode = 'plate'

    def get_mode_text(self):
        return "Person Detection" if self.mode == 'person' else "Red Box Plate Recognition"

    def process_frame(self, img, display_plate=True):
        if self.mode == 'person':
            return self.detect_persons(img)
        else:
            return self.detect_and_recognize(img, display_plate)