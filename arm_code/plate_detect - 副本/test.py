import os
import glob
import torch
from PIL import Image
from torchvision import transforms
from model import LPRNet
from tqdm import tqdm
import json
from wordbank import CHARS

# 车牌类型字典
PLATE_TYPE_DICT = {
    '单层蓝牌': 0,
    '单层黄牌': 1,
    '双层黄牌': 2,
    '拖拉机绿牌': 3,
    '新能源小型车': 4,
    '新能源大型车': 5,
    '黑色车牌': 6,
    'unknown': 7
}

TYPE_IDX_TO_NAME = {v: k for k, v in PLATE_TYPE_DICT.items()}

def decode_ctc(preds, chars):
    """CTC 贪心解码策略"""
    result = []
    blank_index = len(chars) - 1
    for i in range(len(preds)):
        if preds[i] != blank_index and (i == 0 or preds[i] != preds[i - 1]):
            result.append(chars[preds[i]])
    return "".join(result)

def parse_label_file(label_path, debug=False):
    """解析标签文件"""
    with open(label_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    
    if debug:
        print(f"标签文件内容: '{content}'")
    
    if not content:
        return [], 7
    
    parts = content.split(' ')
    if len(parts) == 2:
        char_indices_str = parts[0]
        plate_type_idx = int(parts[1]) if parts[1].isdigit() else 7
    else:
        char_indices_str = content
        plate_type_idx = 7
    
    if debug:
        print(f"解析后字符索引字符串: '{char_indices_str}'")
        print(f"解析后类型索引: {plate_type_idx}")
    
    char_indices = []
    if char_indices_str:
        for idx_str in char_indices_str.split('_'):
            if idx_str.isdigit():
                char_indices.append(int(idx_str))
    
    if debug:
        print(f"解析后字符索引列表: {char_indices}")
        if char_indices:
            print(f"对应的字符: {[CHARS[idx] for idx in char_indices if 0 <= idx < len(CHARS)]}")
    
    return char_indices, plate_type_idx

def test(max_test_num=2000, debug_samples=5):
    DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    
    # 尝试使用第一个代码的权重路径
    WEIGHTS_PATHS = [
        './model_save/lprnet_double.pth',  # 第二个代码的路径
    ]
    
    WEIGHTS_PATH = None
    for path in WEIGHTS_PATHS:
        if os.path.exists(path):
            WEIGHTS_PATH = path
            print(f"找到权重文件: {WEIGHTS_PATH}")
            break
    
    if not WEIGHTS_PATH:
        print(f"Error: 未找到权重文件，请检查路径。")
        return
    
    # 测试集路径
    TEST_IMG_DIR = './datasets/cblprd_test/test/images'
    TEST_LABEL_DIR = './datasets/cblprd_test/test/labels'
    
    # 结果保存路径
    RESULTS_DIR = './outputs'
    os.makedirs(RESULTS_DIR, exist_ok=True)
    DETAILS_PATH = os.path.join(RESULTS_DIR, 'test_details.json')
    SUMMARY_PATH = os.path.join(RESULTS_DIR, 'test_summary.txt')
    
    # 打印字符集信息
    print(f"字符集大小: {len(CHARS)}")
    print(f"字符集: {CHARS[:]}")
    
    # 1. 模型初始化
    print("\n加载模型...")
    lprnet = LPRNet(lpr_max_len=8, phase=False, class_num=len(CHARS), dropout_rate=0.5)
    lprnet.to(DEVICE)
    
    try:
        lprnet.load_state_dict(torch.load(WEIGHTS_PATH, map_location=DEVICE))
        print("模型加载成功!")
    except Exception as e:
        print(f"加载模型失败: {e}")
        return
    
    lprnet.eval()

    # 2. 数据预处理
    transform = transforms.Compose([
        transforms.Resize((24, 94)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5],
                             std=[0.5])
    ])

    # 3. 获取测试图片
    img_paths = glob.glob(os.path.join(TEST_IMG_DIR, '*.jpg'))
    if not img_paths:
        print(f"未在 {TEST_IMG_DIR} 找到任何测试图片。")
        return
    
    # 限制测试图片数量
    if len(img_paths) > max_test_num:
        print(f"测试图片数量超过上限 {max_test_num}，将随机选择 {max_test_num} 张进行测试。")
        import random
        random.shuffle(img_paths)
        img_paths = img_paths[:max_test_num]
    
    print(f"开始测试，共计提取到 {len(img_paths)} 张测试图片。")
    
    # 4. 调试前几个样本
    print(f"\n调试前 {debug_samples} 个样本:")
    print("-" * 50)
    
    # 5. 初始化统计变量
    total = len(img_paths)
    correct = 0
    
    # 按车牌类型统计字符识别准确率
    type_stats = {}
    for type_idx, type_name in TYPE_IDX_TO_NAME.items():
        type_stats[type_idx] = {
            'name': type_name,
            'total': 0,
            'correct': 0
        }
    
    # 6. 评估循环
    debug_count = 0
    with torch.no_grad():
        for img_idx, img_path in enumerate(tqdm(img_paths, desc="测试进度")):
            basename = os.path.basename(img_path)
            basename_no_ext = os.path.splitext(basename)[0]
            label_path = os.path.join(TEST_LABEL_DIR, basename_no_ext + '.txt')
            
            # 跳过没有标签文件的图片
            if not os.path.exists(label_path):
                if debug_count < debug_samples:
                    print(f"样本 {img_idx}: 缺少标签文件 {label_path}")
                continue
            
            # 解析标签文件
            debug_mode = (debug_count < debug_samples)
            if debug_mode:
                print(f"\n样本 {img_idx} 文件名: {basename}")
            
            char_indices, plate_type_idx = parse_label_file(label_path, debug=debug_mode)
            
            # 获取真实车牌字符
            gt_chars = []
            for idx in char_indices:
                if 0 <= idx < len(CHARS):
                    gt_chars.append(CHARS[idx])
                elif debug_mode:
                    print(f"警告: 索引 {idx} 超出字符集范围 [0, {len(CHARS)-1}]")
            
            gt_str = "".join(gt_chars)
            
            if not gt_str:  # 无效标签跳过
                if debug_mode:
                    print(f"无效标签: 字符索引列表为空")
                debug_count += 1
                continue
            
            # 映射车牌类型到已知类型
            if plate_type_idx not in type_stats:
                plate_type_idx = 7  # unknown
            
            # 更新类型统计
            type_stats[plate_type_idx]['total'] += 1
            
            # 推理图片
            try:
                image_pil = Image.open(img_path).convert('L')
                img_tensor = transform(image_pil).unsqueeze(0).to(DEVICE)
                logits = lprnet(img_tensor)
                preds = logits.argmax(dim=1).squeeze(0).cpu().numpy()
                pred_str = decode_ctc(preds, CHARS)
            except Exception as e:
                if debug_mode:
                    print(f"处理图片时出错: {e}")
                pred_str = ""
            
            # 判断是否预测正确
            is_correct = (pred_str == gt_str)
            
            if debug_mode:
                print(f"真实车牌: {gt_str}")
                print(f"预测车牌: {pred_str}")
                print(f"是否正确: {is_correct}")
                print("-" * 30)
                debug_count += 1
            
            # 更新统计
            if is_correct:
                type_stats[plate_type_idx]['correct'] += 1
                correct += 1
    
    # 7. 计算并输出结果
    print("\n" + "="*60)
    
    # 总体准确率
    accuracy = (correct / total * 100) if total > 0 else 0
    print(f"测试集总图片数   : {total}")
    print(f"完全正确预测数   : {correct}")
    print(f"整体准确率 (ACC) : {accuracy:.2f}%")
    print("="*60)
    
    if accuracy == 0:
        print("\n⚠️ 警告: 正确率为0%，可能原因:")
        print("1. 权重文件与字符集不匹配")
        print("2. 测试集标签格式不正确")
        print("3. 模型未正确加载")
        print("4. 字符集定义不匹配")
    
    # 保存结果
    if total > 0 and accuracy > 0:
        # 按类型统计字符识别准确率
        print("\n按车牌类型统计字符识别准确率:")
        print("-"*60)
        print(f"{'车牌类型':<12} {'数量':<8} {'正确数':<8} {'准确率':<8}")
        print("-"*60)
        
        for type_idx in sorted(type_stats.keys()):
            stat = type_stats[type_idx]
            if stat['total'] > 0:
                type_acc = (stat['correct'] / stat['total'] * 100) if stat['total'] > 0 else 0
                print(f"{stat['name']:<12} {stat['total']:<8} {stat['correct']:<8} {type_acc:>7.2f}%")
        
        print("-"*60)
        
        # 保存详细结果
        result_dict = {
            'test_settings': {
                'max_test_num': max_test_num,
                'actual_test_num': total
            },
            'overall': {
                'total_images': total,
                'correct_predictions': correct,
                'accuracy': accuracy
            },
            'by_type': {},
            'model_info': {
                'weights_path': WEIGHTS_PATH,
                'device': str(DEVICE),
                'charset_size': len(CHARS)
            }
        }
        
        for type_idx, stat in type_stats.items():
            if stat['total'] > 0:
                result_dict['by_type'][stat['name']] = {
                    'total': stat['total'],
                    'correct': stat['correct'],
                    'accuracy': (stat['correct'] / stat['total'] * 100) if stat['total'] > 0 else 0
                }
        
        with open(DETAILS_PATH, 'w', encoding='utf-8') as f:
            json.dump(result_dict, f, ensure_ascii=False, indent=2)
        
        print(f"\n结果已保存到 {RESULTS_DIR} 目录")

if __name__ == '__main__':
    # 先测试少量样本进行调试
    test(max_test_num=20000, debug_samples=10)