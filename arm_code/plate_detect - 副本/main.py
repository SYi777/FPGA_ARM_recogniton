from detect_fpga import PlateDetectorFPGA
import cv2
import os
import glob

def pic(yolo_model_path='model_save/only_plate.pt', lpr_model_path='model_save/lprnet_double.pth'):
    detector = PlateDetectorFPGA(yolo_model_path=yolo_model_path, lpr_model_path=lpr_model_path)

    # 从datasets/test文件夹读取所有图片
    test_folder = 'datasets/test'
    image_extensions = ['*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tiff', '*.tif']
    image_paths = []
    
    for ext in image_extensions:
        image_paths.extend(glob.glob(os.path.join(test_folder, ext)))
    
    if not image_paths:
        print(f"在文件夹 {test_folder} 中没有找到图片")
        return
    
    print(f"找到 {len(image_paths)} 张图片")
    image_paths.sort()  # 按文件名排序
    current_index = 0
    
    # 加载第一张图片
    img = cv2.imread(image_paths[current_index])
    if img is None:
        print(f"无法加载图片: {image_paths[current_index]}")
        return
    
    window_name = "Plate Detection - Space: next, Q/ESC: quit"
    
    while True:
        frame = img.copy()
        if frame is None:
            print(f"无法处理图片: {image_paths[current_index]}")
            break
            
        # 显示当前图片信息
        filename = os.path.basename(image_paths[current_index])
        
        # 进行车牌检测和识别
        results, draw_img = detector.detect_and_recognize(frame, display_plate=True)
        
        # 显示识别结果
        cv2.imshow(window_name, draw_img)
        
        # 控制按键
        key = cv2.waitKey(0)  # 等待按键
        
        if key == ord(' ') or key == 32:  # 空格键
            current_index = (current_index + 1) % len(image_paths)
            img = cv2.imread(image_paths[current_index])
            if img is None:
                print(f"无法加载图片: {image_paths[current_index]}")
                break
        
        elif key == ord('q') or key == ord('Q') or key == 27:  # Q或ESC
            break

    cv2.destroyAllWindows()



def cam(yolo_model_path='model_save/only_plate.pt', lpr_model_path='model_save/lprnet_double.pth', person_detector_path=None):
    detector = PlateDetectorFPGA(yolo_model_path=yolo_model_path, lpr_model_path=lpr_model_path, person_detector_path=person_detector_path)
    cap = cv2.VideoCapture(0)

    print("按空格键切换检测模式 (车牌/行人)")
    print("按 q 或 ESC 退出")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # 根据当前模式处理帧
        results, draw_img = detector.process_frame(frame, display_plate=True)

        # 显示当前模式
        mode_text = detector.get_mode_text()
        cv2.putText(draw_img, f"Mode: {mode_text}", (10, 70), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)

        cv2.imshow("Detection System", draw_img)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q') or key == 27:  # q 或 ESC
            break
        elif key == ord(' '):  # 空格键切换模式
            detector.toggle_mode()
            print(f"切换到: {detector.get_mode_text()}")

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    cam(yolo_model_path='model_save/plate_int8_ncnn_model',
        lpr_model_path='model_save/lprnet_ncnn_model/lprnet_opt.param',
        person_detector_path='model_save/yolo26n_ncnn_model')
    #cam(yolo_model_path='model_save/only_plate.pt', lpr_model_path='model_save/lprnet_double.pth', person_detector_path='model_save/yolo26n.pt')