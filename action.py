import os
from pathlib import Path
from subprocess import check_call, check_output
import sys
import shutil


original_dir = Path(os.getcwd())
work_dir = Path(os.environ["ARG_DOWNLOADED_IMAGE_WORKDIR"])
output_path = os.environ["ARG_IMAGE_PATH"]
arg_image_maxsize = os.environ["ARG_IMAGE_MAXSIZE"]
arg_files = os.environ["ARG_FILES"]
arg_script_path = os.environ["ARG_SCRIPT_PATH"]
arg_run = os.environ["ARG_RUN"]

os.chdir(work_dir)
files = list(work_dir.iterdir())

if len(files) != 1 or not files[0].is_file():
    print("Only one image file expected. (Did your archive content more than one?)")
    sys.exit(1)

image_path = files[0]

print(f"Temporarily expanding image to {arg_image_maxsize}")
check_call(["fallocate", "-l", arg_image_maxsize, image_path])

loopback_dev = check_output(["losetup", "-fP", "--show", image_path], text=True).strip()
print(f"Created looped device {loopback_dev}")

print("Expanding partition")
check_call(["parted", image_path, "resizepart", "2", "100%FREE"])
check_call(["losetup", "-d", loopback_dev])
loopback_dev = check_output(["losetup", "-fP", "--show", image_path], text=True).strip()
print(f"Re-created looped device {loopback_dev}")

print("Resizing second partition")
check_call(["resize2fs", f"{loopback_dev}p2"])

mount_path = work_dir / "mnt"
print(f"Mounting image to {mount_path}")
check_call(["mkdir", mount_path])
check_call(["mount", f"{loopback_dev}p2", mount_path])
check_call(["mount", f"{loopback_dev}p1", mount_path / "boot"])

cleanup_files = []

for arch in ("aarch64", "arm"):
    with open(f"/proc/sys/fs/binfmt_misc/qemu-{arch}", "r") as file:
        for line in file.read().splitlines():
            if line.startswith("interpreter "):
                qemu_bin_src = Path(line.removeprefix("interpreter "))
                qemu_bin_dest = mount_path.joinpath(*qemu_bin_src.parts[1:])
                qemu_bin_dest.parent.mkdir(parents=True, exist_ok=True)
                print(f"Temporarily copying {qemu_bin_src} to image")
                shutil.copy(qemu_bin_src, qemu_bin_dest)
                cleanup_files.append(qemu_bin_dest)
                break
        else:
            print(f"qemu interpreter for {arch} not found!")
            sys.exit(1)

# print(f"Destroying loopback device {loopback_dev}")
# check_call(['sudo', 'losetup', '-d', loopback_dev])
