# MoonNIfTI 项目申报书

## 1. 项目名称

MoonNIfTI——MoonBit 原生 NIfTI 体数据与空间变换库。

## 2. 项目简介

面向科研数据处理与教学工具，提供不依赖 Python/C/JS 影像引擎的 MoonBit NIfTI-1 标量体数据核心库。项目不仅读取文件头，还解码实际体素与缩放值，独立解释 qform/sform，执行保持对应体素世界位置的 ROI 裁剪及轴置换/翻转，并导出可由 NiBabel 重新读取的文件。当前已有可运行 MVP、七个命令的 CLI、跨后端测试和三个完整示例；不涉及临床诊断。

## 3. 项目方向与通用性

方向：科学计算／专业数据格式／基础工具库，新项目。可作为科研预处理、教学体数据工具及 MoonBit 应用的数据层，核心支持 JS、Wasm-GC、Native。与 MoonDICOM、MedSeal 的 DICOM 标签与元数据脱敏能力不同，本项目处理 NIfTI 标量样本及其空间几何；不是日志、HAR、HTTP 回放或脱敏工具的换名延续。独立价值是可复用的 MoonBit 体素操作和双空间写回，而非单纯格式校验。公开查重暂未发现同等 MoonBit 核心实现，但不宣称全球首创或排除未公开项目。

## 4. 至少三个完整使用场景

1. **科研样例切片与坐标提取。** 输入授权的 4D `.nii/.nii.gz`，选择时间帧、数据轴及层号；解码缩放体素并显式选用 qform/sform；输出切片 JSON、统计和指定体素世界坐标。合成示例与 NiBabel 独立结果一致。输出是数据轴切片，不冒充解剖重采样。
2. **图像与分割标签的网格门控。** 输入图像和标签，比较空间尺寸、坐标系代码、长度单位及世界坐标；同尺寸但原点偏移的负例被拒绝直接配对，几何兼容的正例输出同层图像/标签数据。该判断不等于受试者一致或配准成功。
3. **坐标保持的 ROI 与轴重排。** 输入体数据、整数裁剪框或轴排列/翻转；保留原始样本、缩放和时间帧，分别更新两套空间变换；输出新 `.nii/.nii.gz` 及元数据损失报告。NiBabel 读回验证原始值、单位、形式代码及新旧对应位置；不做插值或非线性配准。

## 5. 核心功能与完成情况

已实现 NIfTI-1 单文件 3D/4D、大小端、8 种标量类型、原始/缩放访问、非有限值统计、切片、显式空间坐标、网格比较、ROI、全部 48 种轴排列/翻转和写出；CLI 有界 gzip 与拒绝覆盖输出。扩展元数据默认阻止空间变换，显式丢弃才放行；保守清理切片时序并报告。24 个测试通过三个后端；37 次 CLI 验收；NiBabel 276 案例交叉验证；Linux/Windows CI 通过。首版不支持 NIfTI-2、RGB/复数、64 位整数、向量/张量重定向、自动解剖重采样。

## 6. 原创／移植性质

按公开规范新实现的原创 MoonBit 项目，非整库移植；开发、测试及文档使用 AI 辅助。NIfTI 格式和标准几何算法已有成熟先例，不作为原创发明申报。NiBabel 仅承担独立测试，Node 仅承担文件/gzip/进程适配，核心运算在 MoonBit。

## 7. 参考项目与许可证

不涉及直接源码移植。参考 [NIfTI 规范](https://github.com/NIFTI-Imaging/nifti_clib/blob/master/nifti2/nifti1.h)；测试基准 [NiBabel 5.3.2](https://github.com/nipy/nibabel)（MIT）与 [NumPy](https://github.com/numpy/numpy)（BSD-3-Clause）。现有其他语言实现包括 [NIFTI-Reader-JS](https://github.com/rii-mango/NIFTI-Reader-JS)（MIT），仅作先例研究，不是运行依赖。MoonNIfTI 使用 MIT，详细边界见仓库 THIRD_PARTY.md。

## 8. 仓库与有效提交

GitHub：[wangjiale6036-dotcom/moonnifti](https://github.com/wangjiale6036-dotcom/moonnifti)。已有超过 10 次实际开发提交，覆盖二进制解码、几何、解析、切片/网格、裁剪、轴变换、CLI、独立验证、边界加固、公开 API、完整场景与 CI；无空提交、重复提交或伪造时间。有效赛期认定以组委会审核为准。[CI 与复现产物](https://github.com/wangjiale6036-dotcom/moonnifti/actions/workflows/ci.yml)，README 提供完整复现命令。

---

本文为基于已实现功能整理的 AI 辅助材料。若报名要求人工撰写，请参赛者按本人理解改写并确认后提交；本文不构成人工独立撰写声明。新项目本期申报资格仍需组委会确认，不能作为已被驳回项目的复审。
