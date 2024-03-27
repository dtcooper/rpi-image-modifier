# Raspberry Pi OS Image Modifier GitHub Action

GitHub Action to modify a base Raspberry Pi OS image

This is action is a _simple_ way to modify a base Raspberry Pi OS image. For more complicated use
cases, or to build an image from scratch, I recommend using
[`usimd/pi-gen-action`](https://github.com/usimd/pi-gen-action).

## Usage

### Action Inputs

|  Input name        |  Description                                                                          |  Default                |
|-------------------:|---------------------------------------------------------------------------------------|-------------------------|
| `base-image-url`   | Base Raspberry Pi OS image URL (required)                                             | -                       |
| `script-path`      | Path of script to run to modify image (one of script-path or run is required)         | -                       |
| `run`              | Script contents run to modify image (one of script-path or run is required)           | -                       |
| `env-vars`         | Comma-separated environment variables to pass to the script, example: `ONE,TWO,THREE` | -                       |
| `image-path`       | What to name the modified image                                                       | `'rpi-os-modified.img'` |
| `mount-repository` | Temporary mount repository at /mounted-github-repo/ for copying files                 | `'true'`                |
| `compress-with-xz` | Compress final image with xz (`image-path` output will have an .xz extension added)   | `'false'`               |
| `extra-xz-args`    | Extra arguments to pass to the xz command                                             | `''`                    |
| `shrink`           | Shrink final image using PiShrink (<https://github.com/Drewsif/PiShrink>)             | `'true'`                |
| `shell`            | Shell in container to execute script                                                  | `'/bin/bash'`           |
| `cache`            | Cache image file located at base-image-url                                            | `'false'`               |
| `image-maxsize`    | That maximum size of the modified image (needs to fit on disk)                        | `'12G'`                 |


### Action Outputs

| Output name       | Description                                                                                                             |
|------------------ |-------------------------------------------------------------------------------------------------------------------------|
| `image-path`      | Filename of image, will be same as image-path unless compress-with-xz is set in which case it will have a .xz extension |
| `image-size`      | Size of image, as it was before xz compression was optionally applied                                                   |
| `image-sha256sum` | SHA256 sum of image file after xz compression is optionally applied                                                     |

### Example

```yaml
name: ci

on:
  push:

jobs:
  modify-rpi-image:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout repository
        uses: actions/checkout@v4
      -
        name: Add pygame to Raspberry Pi OS Bookworm
        uses: dtcooper/rpi-image-modifier@v1
        id: create-image
        env:
          TEST: 'hi mom!'
        with:
          base-image-url: https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz
          image-path: 2024-03-15-raspios-bookworm-arm64-lite-modified-with-pygame.img
          compress-with-xz: true
          cache: true
          mount-repository: true
          env-vars: TEST
          run: |
            # Copy project README to root directory
            cp -v /mounted-github-repo/README.md /home/pi/README.md
            chown -v pi:pi /home/pi/README.md

            # Install pygame
            apt-get update
            apt-get install -y --no-install-recommends python3-pygame

            # Should print 'hi mom!'
            echo "$TEST"
      -
        name: Print outputs
        shell: bash
        run: |
          echo 'image-path: ${{ steps.create-image.outputs.image-path }}'
          echo 'image-size: ${{ steps.create-image.outputs.image-size }}'
          echo 'image-sha256sum: ${{ steps.create-image.outputs.image-sha256sum }}'
      -
        name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: built-image
          path: ${{ steps.create-image.outputs.image-path }}
          if-no-files-found: error
          retention-days: 2
          compression-level: 0  # Already compressed with xz above
```


## Changelog &amp; License

Changelog can be found in the [CHANGELOG.md](CHANGELOG.md) file.

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT)
&mdash; see the [LICENSE](LICENSE) file for details.
