import torch
from model import LPRNet
from wordbank import CHARS

def main():
    # 加载模型
    model = LPRNet(lpr_max_len=8, phase=False, class_num=len(CHARS), dropout_rate=0.5)
    
    # 加载权重
    checkpoint = torch.load('model_save/lprnet_double.pth', map_location='cpu')
    if 'state_dict' in checkpoint:
        model.load_state_dict(checkpoint['state_dict'])
    elif 'model' in checkpoint:
        model.load_state_dict(checkpoint['model'])
    elif 'net' in checkpoint:
        model.load_state_dict(checkpoint['net'])
    else:
        model.load_state_dict(checkpoint)
    
    model.eval()
    
    # 创建示例输入
    dummy_input = torch.randn(1, 1, 24, 94)
    
    # 保存为 TorchScript
    traced_script = torch.jit.trace(model, dummy_input)
    traced_script.save("model_save/lprnet.pt")
    
    print("模型已保存为 lprnet.pt")
    print("\n请运行以下命令进行转换：")
    print("pnnx model_save/lprnet.pt inputshape=[1,1,24,94]")

if __name__ == "__main__":
    main()