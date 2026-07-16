# 图片自动压缩说明

- 当前网页的 PNG、JPG、GIF、TIF/TIFF 素材已统一转换为 WebP。
- 以后新增图片时，双击 `start-image-watcher.cmd`，并保持弹出的窗口开启。
- 监控开启后，把图片放进本项目任意目录即可自动转换；网页中对应的旧扩展名引用也会自动改成 `.webp`。
- GIF 会转换为动态 WebP，动画会保留。
- 默认质量为 82；需要手动处理时可运行 `optimize-images.ps1`。
