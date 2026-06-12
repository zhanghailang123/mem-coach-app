import os
import shutil

# 新生成的暗色纹理 M 图标路径
src_img = r"C:\Users\86152\.gemini\antigravity-ide\brain\da404482-07c7-456a-baf6-3f17939b10d5\textured_dark_icon_1781243011482.png"
res_dir = r"d:\newIDeaProject\mem-coach-app\app\src\main\res"

def update_icons():
    # 1. 创建 drawable-xxxhdpi 目录并保存新图为 ic_launcher_foreground.png 作为 adaptive icon 的前景图
    foreground_dir = os.path.join(res_dir, "drawable-xxxhdpi")
    os.makedirs(foreground_dir, exist_ok=True)
    shutil.copy(src_img, os.path.join(foreground_dir, "ic_launcher_foreground.png"))
    print("✓ Copy foreground to drawable-xxxhdpi")

    # 2. 删除原有的矢量图 foreground XML，防止资源冲突
    old_xml = os.path.join(res_dir, "drawable", "ic_launcher_foreground.xml")
    if os.path.exists(old_xml):
        os.remove(old_xml)
        print("✓ Removed old vector foreground XML")

    # 3. 创建不同的 mipmap 分辨率文件夹，并保存非 adaptive 的 fallback 图标
    mipmap_dirs = ["mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi", "mipmap-xxhdpi", "mipmap-xxxhdpi"]
    for folder in mipmap_dirs:
        target_folder = os.path.join(res_dir, folder)
        os.makedirs(target_folder, exist_ok=True)
        shutil.copy(src_img, os.path.join(target_folder, "ic_launcher.png"))
        shutil.copy(src_img, os.path.join(target_folder, "ic_launcher_round.png"))
        print(f"✓ Copied launcher icons to {folder}")

if __name__ == '__main__':
    update_icons()
