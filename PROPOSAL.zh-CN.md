# MoonNIfTI 项目申报书

## 一、项目名称与申报人

项目名称：MoonNIfTI——MoonBit 原生 NIfTI 体数据与空间变换库。

申报人：王嘉乐；邮箱：316447364@qq.com。

参赛类型：新项目申报；当前版本：v0.2.0；许可证：MIT。

## 二、项目简介

MoonNIfTI 为 MoonBit 应用提供三维、四维 NIfTI 标量体数据的读取、切片、区域分析和坐标保持导出能力。裁剪或调整数据轴时，分别更新 qform、sform 两套空间变换，避免“数组已改变、空间信息仍停留在原位置”的错误。

影像计算核心由 MoonBit 实现，可用于 JavaScript、Wasm-GC、Native 三种后端；Node.js 仅承担命令行文件、gzip 和进程适配，NiBabel/NumPy 仅用于独立测试。已完成可运行 MVP、命令行工具和批处理示例，并发布至 GitHub 与 Mooncakes。

## 三、项目方向、通用性与独立价值

项目方向为科学计算、专业数据格式与 MoonBit 基础工具库，不绑定特定疾病、模型或数据集，可供教学、科研数据处理和体数据应用复用。

目标用户是希望在 MoonBit 中复用同一套影像处理核心、而不额外部署 Python 服务或另一语言影像引擎的开发者。独立贡献是将体素读取、空间网格核对、标签区域分析及双空间写回组合为可跨后端使用的数据层，而非仅做头部检查或包装外部库。

其他语言已有 NiBabel、NiiVue 等成熟工具；本项目不声称全面优于它们，也不建议已有成熟流程的用户仅为换语言而迁移。详细对照见[项目定位][positioning]。

## 四、三个完整的预期使用场景

### 1. 教学工具中的四维切片与坐标查询

使用者为 MoonBit 教学工具作者。输入一份三维/四维文件及时间帧、层号和空间形式；程序读取并应用数值缩放，提取指定数据轴切片，计算选定体素的世界坐标；输出切片数据、坐标和统计 JSON，供应用绘制或讲解。切片与坐标需和独立读取结果一致，不将数据轴切片冒称为解剖重采样。

### 2. 保留空间位置的局部样例导出

使用者为科研预处理工具开发者。输入体数据、整数裁剪范围及轴排列/翻转参数；程序保留全部时间帧，重排原始样本，并分别更新 qform/sform；输出较小的 `.nii/.nii.gz` 和元数据变更报告。输出须能由 NiBabel 独立读取，对应体素的数值与空间位置保持一致，便于后续分析或复现问题。

### 3. 标签区域的批量时间序列分析

使用者为 MoonBit 数据应用开发者。输入包含图像、静态标签及目标类别的清单；程序先核对空间网格，再计算区域逐帧统计、体积和中心，按包围盒导出局部数据；输出 CSV、裁剪文件及逐例报告。错位案例被拒绝且不进入统计表，合格案例保留；裁剪为矩形，不对未选体素填零。

上述场景均已有自建合成数据演示，暂无外部机构采用证明。[完整流程与运行方法][scenarios]另见仓库。

## 五、核心功能及验收边界

v0.2.0 已实现：

- 读取 NIfTI-1 单文件 3D/4D 标量数据，支持大小端、8/16/32 位有符号与无符号整数、float32/float64。
- 区分原始值与缩放值，提供切片、有限值统计及 NaN/正负无穷计数。
- 独立解释 qform/sform，支持世界坐标查询、长度单位换算和空间网格比较。
- 实现整数裁剪及 48 种轴排列/翻转，保持原始样本并分别更新两套空间信息。
- 实现静态标签选择、区域几何量、逐帧统计、直方图及批处理导出；已有输出不覆盖，不透明扩展不静默丢弃。

直接验收：仓库固定区域样例须选中 4 个体素，三帧均值为 116、2116、4116；同尺寸但偏移 5 mm 的标签须拒绝；空间变换的输出须通过独立读回检查。输入定义、容差与失败标准见[行为验收规范][acceptance]。

边界：不支持 NIfTI-2、RGB/复数/64 位整数体素、配准、插值或完整查看器；区域分析要求静态同网格标签，未知空间/单位时拒绝构造区域。输入上限 256 MiB、1,600 万体素，采用全缓冲处理；不是临床诊断或匿名化产品。详细边界见[API 契约][api]。

后续优先补充合法真实使用反馈、内存评估及兼容性回归；通过 GitHub Issues 维护，修复配套测试，不重写已发布版本。

## 六、项目性质与原创说明

本项目为依据公开规范新实现的 MoonBit 项目，非整库移植、非外部影像引擎包装。原创贡献是实现与工程集成，不将 NIfTI 格式、仿射公式等既有知识申报为原创算法。开发、测试及文档使用 AI 辅助。

## 七、参考项目、来源与许可证

移植来源：不适用。实现参考公开 NIfTI-1 规范；独立测试使用 NiBabel（MIT）、NumPy（BSD-3-Clause），标准库使用 MoonBit Core（Apache-2.0）。规范链接、依赖用途与许可证统一列于[来源及许可说明][sources]，测试依赖不承担产品运行时的影像计算。

## 八、GitHub 仓库与完成情况

仓库：[wangjiale6036-dotcom/moonnifti][repo]。

发布：[v0.2.0 源码与运行包][release]；[Mooncakes 包][package]。

v0.2.0 发布时已有 17 次真实提交，涵盖功能、测试、文档与公开包消费验证，未通过空提交、重复提交或无意义拆分凑数；赛期有效提交最终由组委会认定。

核心 MoonBit 库排除测试、CLI、宿主代码、空行和注释后为 1,235 行；进一步排除纯分隔符行为 1,005 行，统计方法可复算，最终有效行口径由组委会认定。三后端、Linux/Windows 验收及公开包消费验证已通过。

源码统计、测试结果与命令见[验收文档][acceptance]；性能方法与原始记录见[性能文档][performance]。这些数据作为实现佐证，不代替项目必要性或真实采用证据。

[repo]: https://github.com/wangjiale6036-dotcom/moonnifti
[release]: https://github.com/wangjiale6036-dotcom/moonnifti/releases/tag/v0.2.0
[package]: https://mooncakes.io/docs/wangjiale6036-dotcom/moonnifti
[positioning]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/docs/POSITIONING.zh-CN.md
[scenarios]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/docs/SCENARIOS.md
[acceptance]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/docs/ACCEPTANCE.zh-CN.md
[api]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/docs/API.md
[sources]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/THIRD_PARTY.md
[performance]: https://github.com/wangjiale6036-dotcom/moonnifti/blob/main/docs/PERFORMANCE.md
