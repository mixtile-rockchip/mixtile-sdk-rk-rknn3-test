import os
import torch
from transformers import SiglipModel, SiglipProcessor

# ========================
# 配置
# ========================
MODEL_ID = "/hdd_data/shared_develop/pretrained_models/google/siglip-so400m-patch14-384/"   # 可以换成本地路径
SAVE_DIR = "./onnx_siglip"
os.makedirs(SAVE_DIR, exist_ok=True)
from transformers import AutoProcessor, AutoModel
# 加载模型和处理器
processor = SiglipProcessor.from_pretrained(MODEL_ID)

print("=============================")
print(f"{processor}")
model = SiglipModel.from_pretrained(MODEL_ID)
model.eval()

# ========================
# 导出 图像编码器
# ========================
# url = "http://images.cocodataset.org/val2017/000000039769.jpg"
# image = Image.open(requests.get(url, stream=True).raw)

from PIL import Image

# image = Image.open("000000039769.jpg").convert("RGB")
# dummy_image = processor.image_processor(image, return_tensors="pt")

# dummy_image = processor.image_processor(
#     ["000000039769.jpg"],
#     return_tensors="pt"
# ).pixel_values  # shape: [1, 3, H, W]

image_encoder = model.vision_model
image_model = AutoModel.from_pretrained(MODEL_ID).vision_model.eval()
dummy_image = torch.randn(1, 3, 384, 384)  # 随机输入
import numpy as np
dummy_image = torch.randn(1, 3, 384, 384)      # NCHW
hwc = dummy_image.squeeze(0).permute(1, 2, 0)  # (384,384,3)
hwc = hwc.unsqueeze(0)                         # (1,384,384,3)

# np.save('dummy_image.npy', hwc.numpy())  
# np.save('input_384x384.npy',hwc.numpy())
torch.onnx.export(
    image_model,
    (dummy_image,),  # 注意这里传 tuple，而不是 BatchPFeature
    os.path.join(SAVE_DIR, "siglip_image_encoder.onnx"),
    input_names=["pixel_values"],
    output_names=["image_embeds"],
    # dynamic_axes={"pixel_values": {0: "batch"}, "image_embeds": {0: "batch"}},
    opset_version=17
)

# torch.onnx.export(
#     image_encoder,
#     (dummy_image,),
#     os.path.join(SAVE_DIR, "siglip_image_encoder.onnx"),
#     input_names=["pixel_values"],
#     output_names=["image_embeds"],
#     # dynamic_axes={
#     #     "pixel_values": {0: "batch"},
#     #     "image_embeds": {0: "batch"},
#     # },
#     opset_version=17
# )
print("✅ 图像编码器导出完成")

# ========================
# 导出 文本编码器
# ========================
dummy_inputs = processor.tokenizer(
    ["This is a running dog,please tell me ."],
    return_tensors="pt",
    padding=True,
    truncation=True
)

input_ids = dummy_inputs["input_ids"]
# attention_mask = dummy_inputs["attention_mask"]
print(f"------input_ids: {input_ids.shape}")
text_encoder = model.text_model

torch.onnx.export(
    text_encoder,
    (input_ids,),
    os.path.join(SAVE_DIR, "siglip_text_encoder.onnx"),
    input_names=["input_ids"],
    output_names=["text_embeds"],
    # dynamic_axes={
    #     "input_ids": {0: "batch", 1: "sequence"},
    #     "attention_mask": {0: "batch", 1: "sequence"},
    #     "text_embeds": {0: "batch"},
    # },
    opset_version=17
)
print("✅ 文本编码器导出完成")

print(f"全部导出完成，文件保存在: {SAVE_DIR}")
