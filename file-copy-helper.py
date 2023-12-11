#!/usr/bin/env python3

import os
import shutil

temp_dir = os.environ.get("TEMP_DIR")
files_to_copy = os.environ.get("ARG_FILES")
run_file_contents = os.environ.get("ARG_RUN")

print(f"{temp_dir=}")
print(f"{files_to_copy=}")
print(f"{run_file_contents=}")
