import torch
import os

def save_config(config_path: str, img_size: int, patch_size: int):
    import json
    import os

    if img_size % patch_size != 0:
        raise ValueError(f"img_size ({img_size}) must be divisible by patch_size ({patch_size})")
    
    grid_t = 1
    grid_h = img_size // patch_size
    grid_w = img_size // patch_size
    grid_thw = [grid_t, grid_h, grid_w]

    config = {
        "img_size": img_size,
        "grid_thw": grid_thw
    }

    # 获取目录部分，如果为空则表示当前目录，无需创建
    config_dir = os.path.dirname(config_path)
    if config_dir:  # 只有非空时才创建目录
        os.makedirs(config_dir, exist_ok=True)

    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4)
    print(f"Config saved to {config_path}")

def export_qwen2_vl_vision(model, args):
    class qwen2vl(torch.nn.Module):
        def __init__(self, vl_m, in_h, in_w):
            super(qwen2vl, self).__init__()
            self.vl_m = vl_m

            self.grid_t = 1
            self.merge_size = 2
            self.channel = 3
            self.temporal_patch_size = 2
            self.patch_size = 14

            align_size = self.merge_size* self.patch_size
            align_h = (in_h + align_size - 1) // align_size* align_size
            align_w = (in_w + align_size - 1) // align_size* align_size
            self.in_h = align_h
            self.in_w = align_w

        def forward(self, pixel, grid_thw):
            patches = pixel.repeat(self.temporal_patch_size, 1, 1, 1)
            h = pixel.shape[2]
            w = pixel.shape[3]
            patches = patches.reshape(self.grid_t, self.temporal_patch_size, self.channel, h//self.merge_size//self.patch_size, self.merge_size, self.patch_size, w//self.merge_size//self.patch_size, self.merge_size, self.patch_size)
            patches = patches.permute(0, 3, 6, 4, 7, 2, 1, 5, 8)
            flatten_patches = patches.reshape(self.grid_t * h//self.patch_size * w//self.patch_size, self.channel * self.temporal_patch_size * self.patch_size * self.patch_size)

            return self.vl_m(flatten_patches, grid_thw)

    in_h = args.img_size
    in_w = args.img_size
    model = qwen2vl(model, in_h, in_w)
    save_config("vision_config.json", args.img_size, model.patch_size)
    in_h = model.in_h
    in_w = model.in_w

    fake_input = torch.randn(1, 3, in_h, in_w)
    grid_thw = torch.tensor([[1, in_h//model.patch_size, in_w//model.patch_size]], dtype=torch.int64)

    out = model(fake_input, grid_thw)

    torch.onnx.export(model,
                    (fake_input, grid_thw),
                    args.export_vision_path,
                    input_names=['pixel', 'grid_thw'],
                    dynamic_axes={'pixel': {2: 'height', 3: 'width'}},
                    opset_version=17)
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")


def export_vila_1_5_vision(vision_model, proj_model, args):
    class vila1_5(torch.nn.Module):
        def __init__(self, vision, proj):
            super(vila1_5, self).__init__()
            self.vision = vision
            self.proj = proj


        def forward(self, pixel):
            last_hidden_state = self.vision(pixel)['last_hidden_state']
            vision_embeds = self.proj(last_hidden_state)

            return vision_embeds

    img_size = vision_model.config.image_size

    vila_vision = vila1_5(vision_model, proj_model)

    pixel = torch.randn(1, 3, img_size, img_size)

    out = vila_vision(pixel)

    torch.onnx.export(vila_vision,
                     (pixel),
                     args.export_vision_path,
                     input_names=['pixel'],
                     opset_version=17)
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")

def export_minicpm3o_vision(vlm, args):
    import math
    class minicpm_v_vision(torch.nn.Module):
        def __init__(self, vlm, batch_size, in_h, in_w):
            super(minicpm_v_vision, self).__init__()
            self.vpm = vlm.vpm
            self.resampler = vlm.resampler
            patch_size = vlm.config.patch_size
            num_patches_per_side = vlm.vpm.embeddings.num_patches_per_side
            tgt_sizes = torch.Tensor([[(in_h // patch_size), math.ceil(in_w / patch_size)]]).type(torch.int32)
            patch_attention_mask = torch.ones(
                size=(batch_size, in_h // patch_size, in_w // patch_size),
                dtype=torch.bool, device=vlm.device,
            )
            max_im_h, max_im_w = in_h, in_w
            max_nb_patches_h, max_nb_patches_w = max_im_h // patch_size, max_im_w // patch_size
            boundaries = torch.arange(1 / num_patches_per_side, 1.0, 1 / num_patches_per_side)
            position_ids = torch.full(
                size=(batch_size, max_nb_patches_h * max_nb_patches_w),
                fill_value=0,
            )
            for batch_idx, p_attn_mask in enumerate(patch_attention_mask):
                if tgt_sizes is not None:
                    nb_patches_h = tgt_sizes[batch_idx][0]
                    nb_patches_w = tgt_sizes[batch_idx][1]
                else:
                    nb_patches_h = p_attn_mask[:, 0].sum()
                    nb_patches_w = p_attn_mask[0].sum()

                fractional_coords_h = torch.arange(0, 1 - 1e-6, 1 / nb_patches_h)
                fractional_coords_w = torch.arange(0, 1 - 1e-6, 1 / nb_patches_w)

                bucket_coords_h = torch.bucketize(fractional_coords_h, boundaries, right=True)
                bucket_coords_w = torch.bucketize(fractional_coords_w, boundaries, right=True)

                pos_ids = (bucket_coords_h[:, None] * num_patches_per_side + bucket_coords_w).flatten()
                position_ids[batch_idx][p_attn_mask.view(-1).cpu()] = pos_ids

                position_ids = position_ids.to(vlm.device)
            self.position_ids = position_ids
            
            patch_len = tgt_sizes[:, 0] * tgt_sizes[:, 1]
            max_patch_len = torch.max(patch_len)
            key_padding_mask = torch.zeros((batch_size, max_patch_len), dtype=torch.bool, device=vlm.device)
            pos_embed = []
            for i in range(batch_size):
                tgt_h, tgt_w = tgt_sizes[i]
                pos_embed.append(self.resampler.pos_embed[:tgt_h, :tgt_w, :].reshape((tgt_h * tgt_w, -1)).to(torch.float32))  # patches * D
                key_padding_mask[i, patch_len[i]:] = True

            self.pos_embed = torch.nn.utils.rnn.pad_sequence(
                pos_embed, batch_first=True, padding_value=0.0).permute(1, 0, 2)  # BLD => L * B * D
        
        def forward(self, pixel_values):
            batch_size = pixel_values.size(0)
            # patch embedding
            patch_embeds = self.vpm.embeddings.patch_embedding(pixel_values)
            embeddings = patch_embeds.flatten(2).transpose(1, 2)
            hidden_states = embeddings + self.vpm.embeddings.position_embedding(self.position_ids)
            # encoder
            encoder_outputs = self.vpm.encoder(inputs_embeds=hidden_states)
            last_hidden_state = encoder_outputs[0]
            last_hidden_state = self.vpm.post_layernorm(last_hidden_state)
            # resampler
            x = self.resampler.kv_proj(last_hidden_state)  # B * L * D
            x = self.resampler.ln_kv(x).permute(1, 0, 2)  # L * B * D

            q = self.resampler.ln_q(self.resampler.query)  # Q * D

            out = self.resampler.attn(
                self.resampler._repeat(q, batch_size),  # Q * B * D
                x + self.pos_embed,  # L * B * D +  L * B * D
                x)[0]
            #  out: Q * B * D
            x = out.permute(1, 0, 2)  # B * Q * D

            x = self.resampler.ln_post(x)
            x = x @ self.resampler.proj
            return x

    img_size = vlm.config.image_size

    minicpmv3_vision = minicpm_v_vision(vlm, 1, img_size, img_size)

    pixel = torch.randn(1, 3, img_size, img_size)

    # out = minicpmv3_vision(pixel)

    torch.onnx.export(minicpmv3_vision,
                     (pixel),
                     args.export_vision_path,
                     input_names=['pixel'],
                     opset_version=17)
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")

def export_fastvlm_vision(model, args):
    class fastvlm(torch.nn.Module):
        def __init__(self, model):
            super(fastvlm, self).__init__()
            self.vision_tower = model.get_vision_tower()
            self.mm_projector = model.get_model().mm_projector

        def forward(self, pixel):
            vision_feats = self.vision_tower(pixel)
            projected = self.mm_projector(vision_feats)
            return projected

    # img_size = model.get_vision_tower().image_processor.size["shortest_edge"] # 1024
    img_size = args.img_size

    fastvlm_vision = fastvlm(model)

    pixel = torch.randn(1, 3, img_size, img_size)

    torch.onnx.export(fastvlm_vision,
                     (pixel),
                     args.export_vision_path,
                     input_names=['pixel'],
                     opset_version=17)
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")

def export_janus_pro_vision(model, args):
    class janus(torch.nn.Module):
        def __init__(self, model):
            super(janus, self).__init__()
            self.vision_model = model.vision_model
            self.aligner = model.aligner

        def forward(self, pixel):
            img_embeds = self.aligner(self.vision_model(pixel))
            return img_embeds

    img_size = model.config.vision_config.params.image_size

    janus_vision = janus(model)

    pixel = torch.randn(1, 3, img_size, img_size)

    torch.onnx.export(janus_vision,
                     (pixel),
                     args.export_vision_path,
                     input_names=['pixel'],
                     opset_version=17)
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")

def export_internvl_vision(internvl_model, args):
    class InternVLVisionModel(torch.nn.Module):
        """
        从 InternVLChatModel 中分离出的视觉模型。
        包括 vision_model、下采样（如果 downsample_ratio < 1）和 mlp1 投影。
        """
        def __init__(self, vision_model, select_layer, downsample_ratio, mlp1, image_size=448, patch_size=14):
            super().__init__()
            self.vision_model = vision_model  # InternVisionModel
            self.select_layer = select_layer
            self.downsample_ratio = downsample_ratio
            self.mlp1 = mlp1  # nn.Sequential for projection
            self.image_size = image_size
            self.patch_size = patch_size
            self.num_patches = (image_size // patch_size) ** 2  # 用于动态调整
        def pixel_shuffle(self, x, scale_factor=0.5):
            n, w, h, c = x.size()
            # N, W, H, C --> N, W, H * scale, C // scale
            x = x.view(n, w, int(h * scale_factor), int(c / scale_factor))
            # N, W, H * scale, C // scale --> N, H * scale, W, C // scale
            x = x.permute(0, 2, 1, 3).contiguous()
            # N, H * scale, W, C // scale --> N, H * scale, W * scale, C // (scale ** 2)
            x = x.view(n, int(h * scale_factor), int(w * scale_factor),
                    int(c / (scale_factor * scale_factor)))
           
            x = x.permute(0, 2, 1, 3).contiguous()
            return x

        def forward(self, pixel_values):
            # 提取视觉特征（基于典型 InternVL extract_feature 实现）
            # Step 1: 从 vision_model 获取隐藏状态
            # vision_outputs = self.vision_model(pixel_values, output_hidden_states=True)
            # image_features = vision_outputs.hidden_states[self.select_layer]
            vit_embeds = self.vision_model(
                pixel_values=pixel_values,
                output_hidden_states=False,
                return_dict=True).last_hidden_state
            
            # Step 2: 移除 CLS token（假设第一个 token 是 CLS）
            vit_embeds = vit_embeds[:, 1:, :]
            h = w = int(vit_embeds.shape[1] ** 0.5)
            vit_embeds = vit_embeds.reshape(vit_embeds.shape[0], h, w, -1)
            vit_embeds = self.pixel_shuffle(vit_embeds, scale_factor=self.downsample_ratio)
            vit_embeds = vit_embeds.reshape(vit_embeds.shape[0], -1, vit_embeds.shape[-1])
            vit_embeds = self.mlp1(vit_embeds)
            return vit_embeds
               
    vision_model = internvl_model.vision_model
    select_layer = internvl_model.select_layer
    downsample_ratio = internvl_model.downsample_ratio
    mlp1 = internvl_model.mlp1
    image_size = internvl_model.config.vision_config.image_size
    patch_size = internvl_model.config.vision_config.patch_size
    # 从原有模型提取视觉部分
    model = InternVLVisionModel(vision_model, select_layer, downsample_ratio, mlp1, image_size, patch_size)
    
    # 假输入（动态大小，类似 Qwen）
    in_h = 448  # 可调整
    in_w = 448
    fake_input = torch.randn(1, 3, in_h, in_w)  # [B, C, H, W]
    
    # 导出 ONNX
    torch.onnx.export(
        model,
        fake_input,
        args.export_vision_path,
        input_names=['pixel_values'],
        output_names=['image_features'],
        opset_version=17
    )
    print(f"Exported to {os.path.abspath(args.export_vision_path)}")