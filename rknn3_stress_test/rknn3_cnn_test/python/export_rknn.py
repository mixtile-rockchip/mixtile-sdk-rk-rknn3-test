import sys
from rknn.api import RKNN
import cv2
import numpy as np


DATASET_PATH = '../../../datasets/COCO/coco_subset_20.txt'
DEFAULT_RKNN_PATH = '../model/vit-b-16-224.rknn'
DEFAULT_QUANT = True

def parse_arg():
    if len(sys.argv) < 3:
        print("Usage: python3 {} onnx_model_path [platform] [dtype(optional)] [output_rknn_path(optional)] [dtype] [core_num(optional)]".format(sys.argv[0]))
        print("       platform choose from [rk1820]")
        exit(1)

    model_path = sys.argv[1]
    platform = sys.argv[2]

    do_quant = DEFAULT_QUANT
    if len(sys.argv) > 3:
        model_type = sys.argv[3]
        if model_type not in ['i8', 'fp']:
            print("ERROR: Invalid model type: {}".format(model_type))
            exit(1)
        elif model_type in ['i8',]:
            do_quant = True
        else:
            do_quant = False

    if len(sys.argv) > 4:
        output_path = sys.argv[4]
    else:
        output_path = DEFAULT_RKNN_PATH

    dtype = sys.argv[5]
    core_num = int(sys.argv[6])

    return model_path, platform, do_quant, output_path, dtype, core_num

if __name__ == '__main__':
    model_path, platform, do_quant, output_path, dtype, core_num = parse_arg()

    # Create RKNN object
    rknn = RKNN(verbose=False)

    # Pre-process config
    print('--> Config model')

    print("dtype: {}".format(dtype))
    print("core_num: {}".format(core_num))

    if dtype == "w4a16":
        rknn.config(mean_values=[[0, 0, 0]], std_values=[[255, 255, 255]], target_platform=platform,
                    input_attrs={'images': {'dtype': 'uint8', 'layout': 'NHWC'}}, 
                    core_num=core_num, quantized_dtype='w4a16',
                    quantized_algorithm='normal', quantized_method='group32')
    else:
        rknn.config(mean_values=[[0, 0, 0]], std_values=[[255, 255, 255]], target_platform=platform,
                    input_attrs={'images': {'dtype': 'uint8', 'layout': 'NHWC'}}, 
                    core_num=core_num, quantized_dtype='w8a8')
    print('done')

    # Load model
    print('--> Loading model')
    ret = rknn.load_onnx(model=model_path , inputs=["pixel_values"], input_size_list=[[1,3,224,224]])
    if ret != 0:
        print('Load model failed!')
        exit(ret)
    print('done')

    # Build model
    print('--> Building model')
    ret = rknn.build(do_quantization=do_quant, dataset=DATASET_PATH)
    if ret != 0:
        print('Build model failed!')
        exit(ret)
    print('done')

    #图像前处理
    # img = cv2.imread("./bus.jpg")
    # img = cv2.resize(img, (224, 224))
    # img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    # # 2. 增加 batch 维度 (N=1)，从 HWC -> NCHW
    # img = np.expand_dims(img, 0) # HWC -> NHWC
    # img = img.transpose(0, 3, 1, 2) # NHWC -> NCHW
    # # 获取逐层golden/simulator
    # rknn.accuracy_analysis(inputs=[img])

    # Export rknn model
    print('--> Export rknn model')
    ret = rknn.export_rknn(output_path)
    if ret != 0:
        print('Export rknn model failed!')
        exit(ret)
    print('done')

    # Release
    rknn.release()




# import sys
# from rknn.api import RKNN

# DATASET_PATH = '../../../datasets/imagenet/ILSVRC2012_img_val_samples/dataset_20.txt'
# DEFAULT_RKNN_PATH = '../model/mobilenetv2-12.rknn'
# DEFAULT_QUANT = True

# def parse_arg():
#     if len(sys.argv) < 3:
#         print("Usage: python3 {} onnx_model_path [platform] [dtype(optional)] [output_rknn_path(optional)]".format(sys.argv[0]))
#         print("       platform choose from [rk1820]")
#         exit(1)

#     model_path = sys.argv[1]
#     platform = 'rk1820'
#     # platform = sys.argv[2]

#     do_quant = DEFAULT_QUANT
#     if len(sys.argv) > 3:
#         model_type = sys.argv[3]
#         if model_type not in ['i8', 'fp']:
#             print("ERROR: Invalid model type: {}".format(model_type))
#             exit(1)
#         elif model_type in ['i8',]:
#             do_quant = True
#         else:
#             do_quant = False

#     if len(sys.argv) > 4:
#         output_path = sys.argv[4]
#     else:
#         output_path = DEFAULT_RKNN_PATH

#     return model_path, platform, do_quant, output_path

# if __name__ == '__main__':
#     model_path, platform, do_quant, output_path = parse_arg()

#     # Create RKNN object
#     rknn = RKNN(verbose=False)

#     # Pre-process config
#     print('--> Config model')
#     rknn.config(mean_values=[[255*0.485, 255*0.456, 255*0.406]], 
#                 std_values=[[255*0.229, 255*0.224, 255*0.225]], target_platform=platform,
#                 input_attrs={'input': {'dtype': 'w4a16', 'layout': 'NHWC'}},core_num=8,quantized_algorithm='normal')
#     print('done')

#     # Load model
#     print('--> Loading model')
#     ret = rknn.load_onnx(model=model_path,inputs=["pixel_values"], input_size_list=[[1,3,224,224]])
#     if ret != 0:
#         print('Load model failed!')
#         exit(ret)
#     print('done')

#     # Build model
#     print('--> Building model')
#     ret = rknn.build(do_quantization=do_quant, dataset=DATASET_PATH)
#     if ret != 0:
#         print('Build model failed!')
#         exit(ret)
#     print('done')

#     # Export rknn model
#     print('--> Export rknn model')
#     ret = rknn.export_rknn(output_path)
#     if ret != 0:
#         print('Export rknn model failed!')
#         exit(ret)
#     print('done')

#     # Release
#     rknn.release()

