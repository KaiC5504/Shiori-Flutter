# 文库图标

图标是奶白纸雕风格的闭眼侧脸人物，头戴一对蝴蝶发饰，以紫黑配色呈现。iOS 提供浅色、深色与着色三种外观，随主屏幕外观自动切换：

| 外观 | 文件 | 配色 |
| --- | --- | --- |
| 浅色 | `app-icon-light.png` | 奶白底、墨色人物、黑边紫色发饰 |
| 深色 | `app-icon-dark.png` | 炭灰底、奶白人物、黑边紫色发饰 |
| 着色 | `app-icon-tinted.png` | 黑底灰度图，由系统按用户选择的色调着色 |

`app-icon-source.png` 是选定的原图（1264 px）。生成器只重新上色，不重绘人物：在原图分辨率下分离纸面、发饰与投影，再放大并重新锐化边缘，输出 4096 px 母版。`app-icon.png` 是应用内使用的 512 px 浅色版本。

更新原图或配色后运行：

```sh
uv run --with pillow --with numpy python tools/generate_app_icons.py
```

生成器写入三张 4096 px 母版、`app-icon.png`，以及 `ios/Runner/Assets.xcassets/AppIcon.appiconset/` 中的三张 1024 px 图标（单尺寸格式，各尺寸由 Xcode 生成）。Android 与鸿蒙图标仍为旧版人物，不由此生成器更新。旧的 `app-icon.svg` 不参与生成。
