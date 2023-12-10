import os
from pathlib import Path
from subprocess import check_call, check_output
import sys


workdir = Path(os.environ["ARG_DOWNLOADED_IMAGE_WORKDIR"])
output_path = os.environ["ARG_IMAGE_PATH"]
arg_image_maxsize = os.environ["ARG_IMAGE_MAXSIZE"]
arg_files = os.environ["ARG_FILES"]
arg_script_path = os.environ["ARG_SCRIPT_PATH"]
arg_run = os.environ["ARG_RUN"]

os.chdir(workdir)

files = list(workdir.iterdir())

if len(files) != 1 or not files[0].is_file():
    print("Only one image file expected. (Did your archive content more than one?)")
    sys.exit(1)

image_path = files[0]
loopback_dev = check_output(["sudo", "losetup", "-fP", "--show", image_path], text=True).strip()

print(f"Created device {loopback_dev}")
print(f"Expanding second partition to {arg_image_maxsize}")
check_call(["fallocate", "-l", arg_image_maxsize, image_path])
check_call(["sudo", "parted", image_path, "resizepart", "2", "100%FREE"])
check_call(["sudo", "partprobe", "-s", loopback_dev])
check_call(["sudo", "resize2fs", f"{loopback_dev}p2"])

print(f"Destroying loopback device {loopback_dev}")
# check_call(['sudo', 'losetup', '-d', loopback_dev])
