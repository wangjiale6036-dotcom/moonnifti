# 选题查重与独立贡献

研究日期：2026-09-23。结论是**已查公开资料未发现相同核心能力的 MoonBit 项目**，
不是全球唯一证明，不涵盖组委会内部未公开申报。选择此方向不意味着新项目申报
资格或初审通过已有保证。

## 检索范围

- 官方 Mooncakes 索引快照 `abd42454f555b6fefc6f26def201da136545a7cb`，筛选
  2,637 个模块最新名称、描述、关键词；不是阅读全部源码。
- 24 次 GitHub 官方仓库搜索 API，含 MoonBit / NIfTI / nii / NiBabel /
  qform / sform / neuroimaging / MRI，以及 fork/archive 扩展。
- 相邻体素、医学影像筛选；MoonDICOM、MedSeal 接口/解析源码及已检出 mbt/mbti/md
  的相关关键词核查，没有运行其代码。Gitee/GitLink 依赖搜索收录，不是全量扫描。

筛选淘汰了已有项目的 TZif、RRULE、CEL、字幕质检、FITS、响度方向。FITS 和
响度在包索引无命中，但 GitHub 有实际实现，说明“包搜索为零”不够。
完整原始记录在交付目录 `选题查重/`，公开接口不存在未公开项目的证明能力。

## 最接近的 MoonBit 项目

| 项目及核查版本 | 已观察边界 | 本项目的不同产出 |
| --- | --- | --- |
| [MoonDICOM](https://github.com/CCllff-jpg/MoonDICOM-MoonBit-) `a64531ee8aa671df39ac59f71be852e51cdbb956` | DICOM 标签、校验、匿名化，Pixel Data 保留原字节 | 解码标量体素、NIfTI 双空间几何和样本重排 |
| [MedSeal-MBT](https://github.com/001-Elsa/MedSeal-MBT) `bb7e895900dbaf55e13651460906044df50b12fe` | DICOM 序列、脱敏和写出，Pixel Data 不解码编辑 | 4D 切片、坐标保持 ROI/48 种轴变换，外部库验收 |

它们解决不同数据层问题，这不是对它们整体质量的评价。通用头部验证在本项目中
只是支持功能，独立交付物是体素及空间变换引擎，不是换格式的检查报告。

## 原创边界

NiBabel、nifti-rs、NIFTI-Reader-JS、NiiVue 都是明确先例。格式、算法、查看器
概念并非本项目发明。贡献是 MoonBit 可复用数据层、三个后端和独立双空间写回验证。
NiBabel 仅用于测试；Node 只承担文件、gzip、进程边界。运行时没有其他语言影像库
替代核心算法。没有虚构用户、合作单位或患者收益；后续若发现同等 MoonBit 项目，
应重新评估，而非改名规避重叠。
