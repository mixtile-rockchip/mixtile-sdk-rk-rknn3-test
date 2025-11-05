import numpy as np
from rknn.api import RKNN

ONNX_MODEL = '../../model/vision/Qwen2.5-VL-3B-vision.onnx'
RKNN_MODEL = '../../model/vision/Qwen2.5-VL-3B-vision.rknn'
DATASET_PATH = '../../../../datasets/MMBench/vision/datasets.txt'

grid_thw = np.array([[1,28,28]], dtype=np.int64)

if __name__ == '__main__':

    from argparse import ArgumentParser
    parser = ArgumentParser(description="Qwen2.5-VL-3B-Instruct vision convert rknn") 
    parser.add_argument("--onnx_path", type=str, help="onnx model path", required=False, default=ONNX_MODEL)
    parser.add_argument("--rknn_path", type=str, help="output rknn model path", required=False, default=RKNN_MODEL)
    parser.add_argument("--dataset_path", type=str, help="model quantization dataset path", required=False, default=DATASET_PATH)
    parser.add_argument("--no_prune_mode", dest="prune_mode", action="store_false", help="close prune mode")
    parser.set_defaults(prune_mode=True)
    args = parser.parse_args()

    # Create RKNN object
    rknn = RKNN(verbose=True)

    print('--> config model')
    if args.prune_mode == True:
        rknn.config(target_platform='rk1820', core_num=8,
                quantized_dtype='w4a16', quantized_algorithm='normal', quantized_method='group32')
    else:
        rknn.config(target_platform='rk1820', core_num=8,
                    quantized_dtype='w4a16', quantized_algorithm='normal', quantized_method='group32',
                    mean_values=[[0.48145466 * 255, 0.4578275 * 255, 0.40821073 * 255]], #完整版
                    std_values=[[0.26862954 * 255, 0.26130258 * 255, 0.27577711 * 255]],
                    input_attrs={'pixel': {'dtype': 'uint8', 'layout': 'NHWC'}}
                    )
    print('done')

    # Load model
    print('--> Loading model')
    if args.prune_mode == True:
        ret = rknn.load_onnx(model=args.onnx_path,
                         inputs=['/Reshape_1_output_0', 'grid_thw'], #裁剪版
                         input_size_list = [[784,1176],[1,3]],
                         input_initial_val=[None, grid_thw])
    else:
        ret = rknn.load_onnx(model=args.onnx_path,
                         inputs=['pixel', 'grid_thw'], #完整版
                         input_size_list = [[1,3,392,392],[1,3]],
                         input_initial_val=[None, grid_thw])
    if ret != 0:
        print('Load model failed!')
        exit(ret)
    print('done')

    # Build model
    print('--> Building model')
    rknn.build(do_quantization=True, dataset=args.dataset_path)
    if ret != 0:
        print('Build model failed!')
        exit(ret)
    print('done')

    # Export rknn model
    print('--> Export rknn model')
    ret = rknn.export_rknn(args.rknn_path)
    if ret != 0:
        print('Export rknn model failed!')
        exit(ret)
    print('done')

    rknn.release()

