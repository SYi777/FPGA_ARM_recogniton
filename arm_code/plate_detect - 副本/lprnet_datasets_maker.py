import os
import shutil
import cv2
import numpy as np
from tqdm import tqdm
from wordbank import CHARS_DICT
from double_plate import double_plate_cut

def lprnet_datasets_maker(input_txt_path, input_img_dir, out_dir, gamma, train_num, test_num):

    train_images = os.path.join(out_dir, 'train', 'images')
    train_labels = os.path.join(out_dir, 'train', 'labels')
    test_images = os.path.join(out_dir, 'test', 'images')
    test_labels = os.path.join(out_dir, 'test', 'labels')

    # 创建输出文件夹
    for d in [train_images, train_labels, test_images, test_labels]:
        os.makedirs(d, exist_ok=True)

    # 预计算Gamma校正的查找表 (LUT)
    # gamma值根据实际情况调整，>1能提升暗部细节，<1会加深暗部
    gamma = 1.5
    inv_gamma = 1.0 / gamma
    gamma_table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in np.arange(0, 256)]).astype("uint8")

    if not os.path.exists(input_txt_path):
        print(f"找不到标签文件: {input_txt_path}，请确认路径是否正确。")
        return

    with open(input_txt_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    total_needed = train_num + test_num
    if len(lines) < total_needed:
        print(f"警告：标签文件内行数不足 {total_needed}，共有 {len(lines)} 行")
        total_needed = len(lines)
        
    selected_lines = lines[:total_needed]
    train_limit = min(train_num, len(selected_lines))

    print(f"准备处理：前 {train_limit} 张作为训练集，后续 {len(selected_lines) - train_limit} 张作为测试集。")

    success_count = 0
    for idx, line in enumerate(tqdm(selected_lines, desc="处理 CBLPRD 数据集")):
        parts = line.strip().split()
        if len(parts) < 2:
            continue
            
        img_rel_path = parts[0]
        plate_text = parts[1] 
        plate_type = parts[2] if len(parts) > 2 else 'unknown'

        src_img_path = os.path.join(input_img_dir, img_rel_path)
        if not os.path.exists(src_img_path):
            if os.path.exists(img_rel_path):
                src_img_path = img_rel_path
            else:
                continue

        is_train = (idx < train_limit)
        cur_img_dir = train_images if is_train else test_images
        cur_lab_dir = train_labels if is_train else test_labels

        label_indices = []
        for char in plate_text:
            if char in CHARS_DICT:
                label_indices.append(str(CHARS_DICT[char]))
            else:
                label_indices.append(str(CHARS_DICT['-']))

        label_str = "_".join(label_indices)

        out_basename = f"{idx:06d}"
        dst_img_path = os.path.join(cur_img_dir, out_basename + ".jpg")
        dst_lab_path = os.path.join(cur_lab_dir, out_basename + ".txt")

        # 1. 灰度化读取图片
        img = cv2.imread(src_img_path, cv2.IMREAD_GRAYSCALE)
        if img is not None:
            # 2. Gamma校正
            img = cv2.LUT(img, gamma_table)

            # 3. 双层车牌切割
            if plate_type in ["双层黄牌", "拖拉机绿牌"]:
                try:
                    img = double_plate_cut(img)
                except Exception as e:
                    print(f"双层车牌切割失败（{plate_type}，文件: {img_rel_path}）: {e}")

            cv2.imwrite(dst_img_path, img)
            with open(dst_lab_path, 'w', encoding='utf-8') as f:
                f.write(label_str)
            success_count += 1

    print(f"\n处理完成！共成功保存 {success_count} 个样本。")

def main():
    lprnet_datasets_maker(input_img_dir='datasets/cblprd/',
                           input_txt_path='datasets/cblprd/train.txt',
                           out_dir='datasets/cblprd_grey',
                           gamma=1.5,
                           train_num=300000,
                           test_num=20000)

if __name__ == "__main__":
    main()