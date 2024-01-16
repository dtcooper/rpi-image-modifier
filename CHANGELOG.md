# Changelog for Raspberry Pi OS Image Modifier GitHub Action

## v1.3.0

* Added `extra-xz-args` input
* Added `image-sha256sum` output

## v1.2.1

* Clean up temporary directory after running

## v1.2.0

* Add `shrink` input and `image-size` output
* Colorize logging

## v1.1.1

* Be verbose and show how we'll execute `systemd-nspawn`

## v1.1.0

* Added `env-vars` input

## v1.0.1

* Mount boot partition on `/boot/firmware` for newer versions of Raspberry Pi OS

## v1.0.0

* Initial release
