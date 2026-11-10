# 内置乐器采样：来源与授权

`Sources/TunerKit/Samples/` 里的声音都是**真实录音**，来自下面几个来源，已逐个核对授权。
处理脚本在 `Sounds/tools/`（下载 `fetch_sources.py`、处理 `process_samples.py`），原始录音不进仓库。
处理内容：裁掉起音前的静音、测真实基频、把起音/衰减里的音高漂移拉平、拨弦淡出到 3–4 秒、拉弦找无缝循环点、
响度归一化、压缩成 AAC（CAF）。**没有使用任何其他 App 的声音。**

| 乐器 | 来源 | 授权 | 地址 |
| --- | --- | --- | --- |
| 吉他（钢弦原声，`acoustic` 通道） | Karoryfer Samples「Shinyguitar」，D. Smolken 录制 | CC0 1.0（仓库含 CC0 LICENSE；作者声明商用与非商用均免版税） | https://github.com/sfzinstruments/karoryfer.shinyguitar |
| 贝斯（电贝斯，`babyblue/reg`） | Karoryfer Samples「Black And Blue Basses」 | CC0 1.0（仓库含 CC0 license 文件） | https://github.com/sfzinstruments/karoryfer.black-and-blue-basses |
| 尤克里里（单音：G4 G♯4 A4 A♯4 B4 C4 E4） | Freesound 用户 zhankster 的 Ukulele-* 系列 | CC0（页面标注 Creative Commons 0） | https://freesound.org/people/zhankster/ （声音编号 723347–723356） |
| 小提琴、中提琴、大提琴（拉弦，arco mf） | 爱荷华大学电子音乐工作室 Musical Instrument Samples（MIS），2012 年前的单声道 16 bit/44.1 kHz 录音 | 站点声明：录音“可下载并用于任何项目，没有限制”（见下方说明） | https://theremin.music.uiowa.edu/MIS.html |
| 钢琴（「自动」模式，mf） | 同上，MIS 钢琴 | 同上 | https://theremin.music.uiowa.edu/MISpiano.html |

## 逐项说明

### Karoryfer Shinyguitar / Black And Blue Basses（CC0 1.0）
- 仓库根目录的 LICENSE / license 文件是 CC0 1.0 Universal 全文，GitHub 上也标为 CC0-1.0。
- 吉他取 `Samples/acoustic/<音>_vl3_rr1_1.wav`（第 3 力度层、第 1 轮换），音名按 C4=60；
  贝斯取 `Samples/babyblue/reg/babyblue_<音>_f_rr1.wav`，文件名里的八度比标准低两个（`b1` = B0，已用实测音高核对）。
- CC0 不要求署名，这里仍然注明来源。

### zhankster 的尤克里里单音（CC0）
- 每个声音页面都标注 CC0。下载的是 Freesound 公开的 hq 预览（128 kbps MP3）；原始文件需要登录才能下载。
- 这套单音只有 C4、E4、G4–B4（共 7 个），更高/更低的音靠重采样变速得到，音色会偏离（见 README「已知限制」）。
- `Ukulele-C-G`（编号 723351）标成 C，实测其实是 B4，所以没有使用。

### 爱荷华大学 MIS（小提琴、中提琴、大提琴、钢琴）
- 站点原文声明录音 “may be downloaded and used for any projects, without restrictions”，并只提出希望使用者告知用途、欢迎捐赠。
- **这句话没有单独写明“随商业 App 分发”**。同一批钢琴录音已被 Karoryfer 以 CC0 重新发布（Scarypiano），也被大量开源项目使用，
  我们认为可以随 App 分发；但正式上架前，**建议给站点负责人 Lawrence Fritts（lawrence-fritts@uiowa.edu，联系方式见站点页面）发一封邮件确认并留存回复**。
- 用到的文件：`Strings/violin|viola|cello/*.arco.mf.sul*.aiff`（半音阶/四分音练习，已切成单音）、`Piano_Other/piano/Piano.mf.<音>.aiff`。

## 评估过但没有采用
- Versilian Community Sample Library（VCSL，CC0）：里面没有吉他、贝斯、尤克里里和提琴类乐器。
- FreePats、Sonatina 等：未发现可确认的、适合这几件乐器的 CC0/公有领域音色，没有采用。
- Freesound 用户 Sadiquecat 的 CC0「Ukulele」包（336 个声音，多为和弦扫弦）：网页无法逐条列出，未采用。

## 调准提示音
调准一根弦时的“叮—咚”提示音（`TuneChime`）是**程序合成**的，不使用任何外部录音，没有授权问题：两个钟琴音（E6 → C6），
基频加一个很弱、衰减很快的非谐和泛音，4 ms 起音、指数衰减，峰值 0.4，末尾淡出。

## 体积
全部采样合计约 5.5 MB（AAC 96 kbps，单声道 44.1 kHz），远低于 15 MB 的预算；`SampleBankTests` 里有体积检查。
