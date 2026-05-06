import os
import cv2
import glob
import time
import torch
import numpy as np
import ncnn
from PIL import Image, ImageDraw, ImageFont
from torchvision import transforms
from model import LPRNet
from wordbank import CHARS, SPECIALS

class LPRNetRecognizer:
    """LPRNet字符识别类"""
    def __init__(self, weights_path, chars):
        self.chars = chars
        self.weights_path = weights_path
        
        # 判断如果是 .param 或者 .bin 结尾，则使用 NCNN 推理
        if weights_path.endswith('.param') or weights_path.endswith('.bin'):
            self.backend = 'ncnn'
            param_path = weights_path if weights_path.endswith('.param') else weights_path.replace('.bin', '.param')
            bin_path = weights_path.replace('.param', '.bin') if weights_path.endswith('.param') else weights_path
            
            print(f"加载 LPRNet NCNN 模型: {param_path}")
            self.ncnn_net = ncnn.Net()
            self.ncnn_net.opt.use_vulkan_compute = True
            self.ncnn_net.opt.use_fp16_arithmetic = True
            self.ncnn_net.opt.use_fp16_storage = True
            self.ncnn_net.opt.use_int8_inference = True
            
            if os.path.exists(param_path) and os.path.exists(bin_path):
                self.ncnn_net.load_param(param_path)
                self.ncnn_net.load_model(bin_path)
                print("LPRNet NCNN 模型加载成功")
            else:
                print(f"警告：未找到 LPRNet NCNN 模型权重 {param_path} 或 {bin_path}")
        else:
            self.backend = 'pytorch'
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            print("加载 LPRNet PyTorch 模型...")
            self.lprnet = LPRNet(lpr_max_len=8, phase=False, class_num=len(self.chars), dropout_rate=0.5)
            self.lprnet.to(self.device)
            if os.path.exists(weights_path):
                self.lprnet.load_state_dict(torch.load(weights_path, map_location=self.device))
                print("LPRNet PyTorch 模型加载成功")
            else:
                print(f"警告：未找到 LPRNet 模型权重 {weights_path}")
            self.lprnet.eval()

            self.transform = transforms.Compose([
                transforms.Resize((24, 94)),
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.5], std=[0.5])
            ])

    def decode_ctc(self, preds):
        result = []
        blank_index = len(self.chars) - 1
        for i in range(len(preds)):
            if preds[i] != blank_index and (i == 0 or preds[i] != preds[i - 1]):
                result.append(self.chars[preds[i]])
        return "".join(result)

    def recognize(self, gray_img):
        if self.backend == 'pytorch':
            pil_img = Image.fromarray(gray_img)
            tensor_img = self.transform(pil_img).unsqueeze(0).to(self.device)

            with torch.no_grad():
                logits = self.lprnet(tensor_img)
                preds = logits.argmax(dim=1).squeeze(0).cpu().numpy()
            
            return self.decode_ctc(preds)
        elif self.backend == 'ncnn':
            # NCNN 前处理
            img = cv2.resize(gray_img, (94, 24))
            img = img.astype(np.float32)
            img = (img / 127.5) - 1.0
            img = img[np.newaxis, ...]

            with self.ncnn_net.create_extractor() as ex:
                ex.input("in0", ncnn.Mat(img).clone())
                _, out0 = ex.extract("out0")
                out0 = np.array(out0)

            preds = out0.argmax(axis=0)
            return self.decode_ctc(preds)