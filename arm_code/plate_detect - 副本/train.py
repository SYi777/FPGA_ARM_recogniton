import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms
from PIL import Image
from model import LPRNet
from tqdm import tqdm
import glob

# 车牌字符字典
PROVINCES = [
    "皖", "沪", "津", "渝", "冀",
    "晋", "蒙", "辽", "吉", "黑",
    "苏", "浙", "京", "闽", "赣",
    "鲁", "豫", "鄂", "湘", "粤",
    "桂", "琼", "川", "贵", "云",
    "藏", "陕", "甘", "青", "宁",
    "新"
]

WORDS = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
    "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V",
    "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5",
    "6", "7", "8", "9"
]

SPECIALS = ["学", "警", "港", "澳", "挂", "使", "领", "临"]

CHARS = PROVINCES + WORDS + SPECIALS + ['-']

CHARS_DICT = {char: i for i, char in enumerate(CHARS)}


class LPRDataset(Dataset):
    def __init__(self, img_dir, label_dir, transform=None):
        self.img_dir = img_dir
        self.label_dir = label_dir
        self.img_paths = glob.glob(os.path.join(img_dir, '*.jpg'))
        self.transform = transform

    def __len__(self):
        return len(self.img_paths)

    def __getitem__(self, idx):
        img_path = self.img_paths[idx]
        image = Image.open(img_path).convert('L')

        # 获取基础文件名并读取对应的标签文件
        basename = os.path.basename(img_path)
        basename_no_ext = os.path.splitext(basename)[0]
        label_path = os.path.join(self.label_dir, basename_no_ext + '.txt')

        target = []
        try:
            with open(label_path, 'r', encoding='utf-8') as f:
                lpr_label = f.read().strip()
                # 标签是存成了数字索引，如 '19_33_25_25_25_25_25' 对应 CHARS 的索引
                parts = lpr_label.split('_')
                for p in parts:
                    if p.isdigit():
                        target.append(int(p))
        except FileNotFoundError:
            # 如果找不到文件，提供默认值
            target = [0, 0, 0, 0, 0, 0, 0]

        target_length = len(target)

        if self.transform:
            image = self.transform(image)

        return image, target, target_length


def collate_fn(batch):
    imgs = []
    labels = []
    lengths = []
    for img, label, length in batch:
        imgs.append(img)
        labels.extend(label)
        lengths.append(length)

    imgs = torch.stack(imgs, 0)
    labels = torch.tensor(labels, dtype=torch.long)
    lengths = torch.tensor(lengths, dtype=torch.long)
    return imgs, labels, lengths


def train():
    # 超参数设置
    EPOCHS = 1000
    BATCH_SIZE = 128
    LEARNING_RATE = 0.0003
    LPR_MAX_LEN = 8
    CLASS_NUM = len(CHARS)
    loss_min = float('inf')
    DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    SAVE_PATH = './large/lprnet_weights.pth'
    DATA_DIR = './datasets/cblprd_grey/train/images'  # 替换为你的实际图片目录
    LABEL_DIR = './datasets/cblprd_grey/train/labels'  # 对应的标签目录

    # 数据预处理 (加入数据增强)
    transform = transforms.Compose([
        transforms.Resize((24, 94)),
        transforms.RandomRotation(degrees=5),  # 随机旋转±5度，模拟车牌倾斜
        transforms.ColorJitter(brightness=0.3, contrast=0.3),  # 随机亮度和对比度
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5],
                             std=[0.5])
    ])

    # 数据集加载
    dataset = LPRDataset(DATA_DIR, LABEL_DIR, transform=transform)
    dataloader = DataLoader(dataset, batch_size=BATCH_SIZE,
                            shuffle=True, collate_fn=collate_fn, num_workers=4)

    # 模型初始化
    model = LPRNet(lpr_max_len=LPR_MAX_LEN, phase=True,
                   class_num=CLASS_NUM, dropout_rate=0.5)
    model.to(DEVICE)

    # 损失函数和优化器
    ctc_loss = nn.CTCLoss(blank=len(CHARS)-1, reduction='mean',
                          zero_infinity=True)  # 假设 '-' 是 blank
    optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE)

    # 学习率调度器：余弦退火学习率
    scheduler = optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=EPOCHS, eta_min=1e-6)

    # 训练循环
    for epoch in range(EPOCHS):
        model.train()
        total_loss = 0.0

        pbar = tqdm(dataloader, desc=f'Epoch {epoch+1}/{EPOCHS}')
        for imgs, labels, lengths in pbar:
            imgs = imgs.to(DEVICE)
            labels = labels.to(DEVICE)

            optimizer.zero_grad()

            # [batch, CLASS_NUM, width]
            logits = model(imgs)

            # CTC loss 期望 shape 为 [T, N, C]
            # T 是序列长度 (width), N 是 batch size, C 是类别数
            logits = logits.permute(2, 0, 1)  # [width, batch, CLASS_NUM]

            # 计算 log_softmax
            log_probs = logits.log_softmax(2)

            input_lengths = torch.full(
                size=(imgs.size(0),), fill_value=logits.size(0), dtype=torch.long).to(DEVICE)

            loss = ctc_loss(log_probs, labels, input_lengths, lengths)

            if torch.isnan(loss) or torch.isinf(loss):
                print("Loss is NaN or Inf")
                continue

            loss.backward()

            # 加入梯度裁剪，防止梯度爆炸导致 NaN
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)

            optimizer.step()

            total_loss += loss.item()
            pbar.set_postfix(
                {'loss': loss.item(), 'lr': optimizer.param_groups[0]['lr']})

        print(f"Epoch {epoch+1} Average Loss: {total_loss/len(dataloader):.4f}")

        # 步进学习率调度器
        scheduler.step()

        # 保存模型
        if loss_min > total_loss/len(dataloader):
            loss_min = min(loss_min, total_loss/len(dataloader))
            torch.save(model.state_dict(), SAVE_PATH)
            print("save model")

    torch.save(model.state_dict(), SAVE_PATH)
    print("Training Complete!")


if __name__ == '__main__':
    train()