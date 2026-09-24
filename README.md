# MoonNIfTI

[![CI](https://github.com/wangjiale6036-dotcom/moonnifti/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiale6036-dotcom/moonnifti/actions/workflows/ci.yml)

**MoonBit 原生 NIfTI-1 体数据与空间变换库。** 读取真实体素，在保留 qform / sform 各自含义的前提下裁剪、置换和翻转数据轴，并写出可被 NiBabel 读取的文件。

Pure MoonBit scalar NIfTI-1 decoding, voxel access, spatial geometry, ROI and signed-axis transforms. Python/NiBabel is an independent **test oracle**, not the implementation. Node.js only adapts files, gzip containers and CLI I/O.

适合科研数据工具、教学合成数据、Wasm 或原生 MoonBit 程序的体数据处理基础层。**不是临床诊断产品，不做疾病识别、配准、DICOM 转换或脱敏。**

## 已实现

| 能力 | 0.2.0 边界 |
| --- | --- |
| 读取 | NIfTI-1 `n+1` 单文件、3D/4D、大小端 |
| 数据类型 | uint8 / int8 / uint16 / int16 / uint32 / int32 / float32 / float64 |
| 访问 | x 最快存储序，原始值与缩放值分离，时间帧选择，数据轴切片 |
| 几何 | 独立 qform/sform、qfac、仿射组合/求逆、显式空间选择 |
| 统计 | 有限值最小/最大/均值；NaN、+Inf、-Inf 独立计数 |
| 网格比较 | 尺寸、坐标系代码、已知长度单位换算、空间位置误差 |
| 标签区域 | 静态同网格掩码、缩放后整数标签/非零选择、包围盒、毫米中心及 mm³ 体积 |
| 区域分析 | 每帧统计、明确时间单位换算、直方图及超界/非有限值计数 |
| 变换 | 整数 ROI、全部 48 种轴排列与翻转；不插值、不重采样 |
| 写出 | 原始样本字节和缩放保留；两套坐标独立更新；元数据损失报告 |
| CLI | inspect / dump / slice / world / grid / crop / reorient / roi / hist / roi-crop；受限 gzip，禁止覆盖已有输出 |

不支持：NIfTI-2、Analyze `.hdr/.img` 对、RGB/复数/64 位整数体素、向量/张量重定向、任意角度重采样、自动解剖方向标准化。切片是**数据轴切片**，不能直接称为经过校正的轴位/冠状位/矢状位。

## 构建与快速开始

经验证的工具链：MoonBit **0.10.14+7d59c7ec9**，core 同版本；CLI 使用 Node.js 22 或以上。旧版 MoonBit 不保证兼容。安装方式见 [MoonBit 官方说明](https://www.moonbitlang.com/download)。

```sh
git clone https://github.com/wangjiale6036-dotcom/moonnifti.git
cd moonnifti
moon update
moon build --target js --release
node _build/js/release/build/cmd/moonnifti/moonnifti.js --help
```

无需 Python 即可对已有文件运行 CLI。以下命令创建**合成数据**并完成三个独立验证的示例，因此额外需要 Python 3.12、NumPy 和 NiBabel：

```sh
python -m pip install numpy==2.3.5 nibabel==5.3.2
python scripts/scenarios.py work/demo
```

`work/demo` 必须尚不存在。结果包含切片/坐标 JSON、兼容与错位网格报告、门控后的配对切片数据，以及 `03-roi.nii.gz`、`03-reoriented.nii`。没有真实患者数据，也没有外部数据下载。

直接运行（下文把完整 JS 路径写作 `CLI`，请替换为上面的实际路径）：

```text
node CLI inspect input.nii.gz
node CLI slice input.nii.gz 2 10 0
node CLI world input.nii.gz 10 20 30 qform
node CLI grid image.nii.gz labels.nii.gz 0.001
node CLI crop input.nii.gz roi.nii.gz 10 20 5 32 32 16
node CLI reorient roi.nii.gz arranged.nii 2 0 1 1 0 0
node CLI roi image.nii.gz labels.nii 2
node CLI hist image.nii.gz labels.nii 2 0 15 217 2
node CLI roi-crop image.nii.gz labels.nii region.nii.gz 2 1
```

`reorient` 中新轴 0/1/2 分别对应旧轴 2/0/1，最后三个 0/1 表示是否翻转新轴。不会把它自动解释为 RAS/LPS。

退出码：0 成功，1 参数/输入/输出错误，2 网格不兼容。输出文件必须不存在；父目录需预先存在。`.gz` 输出会压缩，输入由 gzip 魔数识别。JSON 中非有限样本输出为 `null`，完整计数见 `inspect` 的 statistics。

## 作为库使用

模块名 `wangjiale6036-dotcom/moonnifti`；[Mooncakes](https://mooncakes.io/docs/wangjiale6036-dotcom/moonnifti)。区域分析接口需要 0.2.0，旧版 0.1.0 不含这些接口。先在消费项目运行 `moon add wangjiale6036-dotcom/moonnifti`，确认版本，再在 `moon.pkg` 中导入：

```moonbit
import { "wangjiale6036-dotcom/moonnifti" @nifti }
```

```moonbit
fn process(bytes : Bytes) -> Bytes raise @nifti.NiftiError {
  let image = @nifti.read(bytes)
  let value = image.voxel(1, 2, 3, t=0)
  let xyz = image.world(1, 2, 3, space=QForm)
  ignore(value)
  ignore(xyz)
  let roi = image.crop([0, 0, 0], [2, 3, 4])
  // Inspect roi.warnings before downstream use.
  roi.image.to_bytes()
}
```

示例假设输入足够大且定义了 qform，否则返回错误。`Image`、`Affine`、`Region` 内部存储私有；返回的尺寸、矩阵、区域中心是副本。库的输入是解压后的 `.nii` 字节，gzip 不属于核心库接口。参见 [公开接口](pkg.generated.mbti)、[跨包消费测试](examples/library/usage_test.mbt)、[区域分析与导出流水线](examples/library/pipeline.mbt)、[API 语义](docs/API.md)。

独立的 [registry-consumer](examples/registry-consumer) 模块只声明版本依赖、不配置本地路径。运行 `moon -C examples/registry-consumer test --target js` 可验证从 Mooncakes 下载后的完整读取、统计、切片和变换接口。

## 空间语义与安全边界

- qform 和 sform 可以合法不同。`PreferSForm` 只是在使用时优先选择 sform，没有把两者合并。变换会分别更新每一套已定义坐标，保留各自代码。
- 若两套空间都未知，不会凭空补一个矩阵；读取允许，世界坐标与空间变换拒绝。未知单位阻止网格兼容判断。
- 网格兼容只说明**空间采样格一致**，不保证属于同一受试者、同一解剖结构或已正确配准；默认比较不包含时间轴。
- 变换只允许 scalar intent 0、label 1002、time-series 2001。不透明扩展默认阻止变换；显式 `--drop-extensions` 才允许丢弃并报告。
- 空间操作清除 `dim_info` 与 slice timing 并报告；头文本原样保留，**不是匿名化工具**。
- 浮点头字段写回会有舍入误差；空间保持是在明确误差容限下验证，不宣称逐位矩阵相等。
- `.nii` 上限 256 MiB、头部 1 MiB、16,000,000 个体素；会产生输入/输出/数组副本，不是零拷贝或流式处理。CLI gzip 解压也有上限。
- 严格子集拒绝尾随字节、无效 spacing、奇异定义矩阵和不支持类型；不是声称它们全都违反整个 NIfTI 标准。

更多：[数值契约](docs/CONTRACT.md)、[安全边界](SECURITY.md)、[完整场景](docs/SCENARIOS.md)。

## 测试与复现

```sh
moon check --target js --deny-warn
moon fmt --check
moon info
node scripts/check-api.mjs
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target native --deny-warn
moon build --target js --release --deny-warn
node tests/cli.mjs
python scripts/oracle.py --report work/oracle-report.json
python scripts/scenarios.py work/scenarios
python scripts/roi_acceptance.py work/roi-acceptance
python scripts/benchmark.py work/benchmark
node scripts/source-audit.mjs --check --report work/source-audit.json
moon package
```

0.2.0 本地验收：32 个测试在三个后端通过；其中包含 3,000 次有界头部变异、48 种轴变换属性检查。原 CLI 37 次进程调用通过，包括损坏 gzip、超大文件、解压上限和拒绝覆盖。NiBabel 交叉验证 276 案例：32 读取、32 裁剪、192 轴变换、12 切片、8 网格比较。新增 ROI 验收包含 69 次直接 CLI 调用、2 次批处理程序调用及 12 组行为标准，和原有三个工作流一起复现。

上述数量不是 3,000 个独立单元测试，也不是完整标准认证。实测独立矩阵最大绝对元素误差约 `3.9124e-6`；固定合成样例结果不构成所有输入的误差上界。CI 在 Linux / Windows 重跑验收并上传可下载的 CLI、包和场景产物。

评审可以优先检查 [逐项行为验收](docs/ACCEPTANCE.zh-CN.md)，而不是以数量代替正确性。核心库排除测试、空行、注释后为 1,235 行 MoonBit；进一步排除纯分隔符行为 1,005 行，均不计 CLI、示例、生成接口或内嵌宿主 JS。`source-audit.mjs` 可逐文件复算，不声称是赛事官方有效行定义。性能仅作佐证，见 [实测方法与结果](docs/PERFORMANCE.md)。

## 可运行的下游批处理

`python scripts/roi_acceptance.py work/roi-acceptance` 会生成可手算图像、标签和 `batch.json`，并验收 [批处理消费程序](examples/batch-roi.mjs)。实际使用已有文件时只需 Node，不依赖 Python：

```sh
node examples/batch-roi.mjs work/roi-acceptance/batch.json work/my-batch
```

清单中每行含 `id`、`image`、`mask`、`label`，相对路径按清单目录解析。结果为逐帧 `time-series.csv`、成功案例的矩形裁剪 `.nii.gz` 和 `report.json`；示例中的 5 mm 错位案例被拒绝，进程返回 2，成功案例保留。已有输出目录会拒绝，不覆盖、不静默删扩展。见 [完整场景](docs/SCENARIOS.md)。这些是自建、合成数据集成样例，**没有声称真实机构已采用**。

## 独立贡献与来源

这是按公开 NIfTI 规范新写的 MoonBit 实现，不是调用现成 JS/Python 影像引擎的包装。格式、四元数算法、体数据裁剪均非本项目发明；其他语言已有成熟实现。价值在于 MoonBit 可复用数据层和双空间变换写回的可验证实现。

[查重与相邻项目边界](docs/POSITIONING.zh-CN.md) 记录公开检索范围、MoonDICOM / MedSeal 差异及未覆盖区域，不承诺全球唯一或评审通过。[来源与许可证](THIRD_PARTY.md) 区分规范、开发依赖和测试 oracle。

项目开发和文档使用 AI 辅助，提交历史保留实际迭代；没有空提交或回填时间。许可证：MIT。后续优先增加独立用户样例与兼容性覆盖，再评估 NIfTI-2、类型扩展和更多宿主适配，不把计划功能写成已实现。
