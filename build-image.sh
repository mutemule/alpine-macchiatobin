#!/usr/bin/env bash

set -Eeu

ALPINE_VERSION="3.10"
ALPINE_PATCHLEVEL="3"
KERNEL_VERSION="5.4-rc8"
BUILD_ROOT="${HOME}/alpine-macchiatobin/build"

# The rest of these shouldn't require tuning
SD_ROOT="${BUILD_ROOT}/sdcard"
ALPINE_DISTRO="${BUILD_ROOT}/alpine-uboot"
INITRAMFS_ROOT="${BUILD_ROOT}/initramfs"
MODLOOP_ROOT="${BUILD_ROOT}/modloop"

error() {
  # TODO: something about line numbers -- something something ${BASH_LINENO}
  # Is there an equivalent for calling function?
  local retcode="${1}"
  shift

  echo "--! ${*}"

  exit "${retcode:-255}"
}

install_requirements() {
  echo "--> Checking required packages..."
  local required_packages=("bc" "bison" "build-essential" "cpio" "curl" "flex" "gpgv" "squashfs-tools" "u-boot-tools" "xz-utils")
  local packages_to_add=()

  for pkg in "${required_packages[@]}"
  do
    dpkg-query -W "${pkg}" > /dev/null 2>&1 || packages_to_add+=("${pkg}")
  done

  if [[ "${#packages_to_add[*]}" -gt 0 ]]
  then
    echo "--> Installing required packages..."
    echo "We need to install a number of packages to build the image: ${packages_to_add[*]}"
    sudo -p "Enter your password to install these packages:" apt install "${packages_to_add[@]}"
  fi
}

get_alpine_distribution() {
  local keyring="${PWD}/trustedkeys.kbx"
  test -f "${keyring}" || error 7 "Could not find keyring to validate GPG signatures at '${keyring}'."

  cd "${BUILD_ROOT}" || error 3 "Could not find our build root at ${BUILD_ROOT}."

  # TODO: Identify the latest patchlevel automatically
  echo "--> Downloading Alpine AARCH64 u-boot distribution..."
  curl -sLO "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/aarch64/alpine-uboot-${ALPINE_VERSION}.${ALPINE_PATCHLEVEL}-aarch64.tar.gz" \
    || error "${?}" "Failed to download Alpine u-boot distribution."
  curl -sLO "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/aarch64/alpine-uboot-${ALPINE_VERSION}.${ALPINE_PATCHLEVEL}-aarch64.tar.gz.asc" \
    || error "${?}" "Failed to download Alpine u-boot distribution signature."

  echo "--> Validating distribution signature..."
  gpgv -q --keyring "${keyring}" \
    "alpine-uboot-${ALPINE_VERSION}.${ALPINE_PATCHLEVEL}-aarch64.tar.gz.asc" \
    "alpine-uboot-${ALPINE_VERSION}.${ALPINE_PATCHLEVEL}-aarch64.tar.gz" \
    || error "${?}" "Failed to validate signatures of the Alpine distribution!"

  echo "--> Extracting distribution..."
  tar -C "${ALPINE_DISTRO}" -xf "alpine-uboot-${ALPINE_VERSION}.${ALPINE_PATCHLEVEL}-aarch64.tar.gz" \
   || error "${?}" "Failed to extract Alpine u-boot distribution."

  # I don't like relying on `cd -`, but the output of pushd/popd can be confusing
  cd -
}

extract_initramfs() {
  test -d "${INITRAMFS_ROOT}" || error 3 "Could not find our initramfs root at '${INITRAMFS_ROOT}'."

  echo "--> Extracting initramfs from distribution..."
  zcat "${ALPINE_DISTRO}/boot/initramfs-vanilla" | cpio -D "${INITRAMFS_ROOT}" -idm \
    || error "${?}" "Failed to extract Alpine initramfs image."

  echo "--> Cleaning kernel modules and firmware images from extracted initramfs..."
  rm -rf "${INITRAMFS_ROOT}/lib/modules/*" "${INITRAMFS_ROOT}/lib/firmware/*" \
    || error "${?}" "Failed to clean kernel-specific binaries from initramfs image."
}

get_kernel() {
  cd "${BUILD_ROOT}" || error 3 "Could not find our build root at ${BUILD_ROOT}."

  echo "--> Downloading Linux kernel..."
  curl -sLO "https://git.kernel.org/torvalds/t/linux-${KERNEL_VERSION}.tar.gz" \
    || error "${?}" "Failed to download Linux kernel ${KERNEL_VERSION}."

  # TODO: monitor for a proper 5.4 release and update once that's published
  # TODO: figure out what happens when we need to support multiple major/minor versions
  # Since we're grabbing an RC kernel, there's no signature, and the URL is different.
  # curl -sLO "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz" \
  #   || error "${?}" "Failed to download Linux kernel ${KERNEL_VERSION}."
  # curl -sLO "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.sign" \
  #   || error "${?}" "Failed to download Linux kernel signature for ${KERNEL_VERSION}."
  #
  # --> echo "Validating kernel signature..."
  # xzcat linux-${KERNEL_VERSION}.tar.xz | gpgv -q --keyring "${PWD}/trustedkeys.kbx" linux-${KERNEL_VERSION}.tar.sign -)

  echo "--> Extracting Linux kernel..."
  tar -xf linux-${KERNEL_VERSION}.tar.gz \
    || error "${?}" "Failed to extract kernel."
  # tar -xf linux-${KERNEL_VERSION}.tar.xz \
  #   || error "${?}" "Failed to extract kernel."

  # TODO: this produces some output, and I really wish it didn't
  # We might need to save ${PWD} when we enter a function, or just
  # change the assumption that we are always in the same directory
  # as the script
  cd -
}

build_kernel() {
  echo "--> Copying in kernel configuration..."
  cp kernel-config "${BUILD_ROOT}/linux-${KERNEL_VERSION}/.config" \
    || error "${?}" "Failed to deploy kernel configuration."

  cd "${BUILD_ROOT}/linux-${KERNEL_VERSION}" \
    || error "${?}" "Failed to chane to Linux kernel source tree."

  echo "--> Updating kernel configuration..."
  make oldconfig \
    || error "${?}" "Failed to update kernel configuration."

  echo "--> Building the kernel (this will take a while)..."
  local numcpus
  numcpus="$(grep -c -E '^processor' /proc/cpuinfo 2>/dev/null)"
  test "${numcpus}" -ge 0 || numcpus=0

  CPPFLAGS=$(dpkg-buildflags --get CPPFLAGS) \
    CFLAGS=$(dpkg-buildflags --get CFLAGS) \
    CXXFLAGS=$(dpkg-buildflags --get CXXFLAGS) \
    LDFLAGS=$(dpkg-buildflags --get LDFLAGS) \
    make -j$((${numcpus} + 1)) Image modules dtbs > "${LOGDIR}/kernel-build.out" 2>&1 \
    || error "${?}" "Failed to build the kernel; see ${LOGDIR}/kernel-build.out for details."

  cd -
}

deploy_kernel() {
  test -d "${INITRAMFS_ROOT}" || error 3 "Could not find our initramfs root at '${INITRAMFS_ROOT}'."
  test -d "${MODLOOP_ROOT}" || error 17 "Could not find our modloop root at '${MODLOOP_ROOT}'."

  echo "--> Installing modules for initramfs..."
  INSTALL_MOD_PATH=${INITRAMFS_ROOT} make -C "${BUILD_ROOT}/linux-${KERNEL_VERSION}" modules_install \
    || error "${?}" "Failed to install kernel modules to initramfs."

  # The modloop root should contain a single directory called `modules`, which is the base of all
  # kernel modules
  echo "--> Copying modules for modloop..."
  cp -R "${INITRAMFS_ROOT}/lib/modules" "${MODLOOP_ROOT}" \
    || error "${?}" "Failed to copy kernel modules to modloop."

  echo "Copying kernel in place..."
  install -m 0755 "${BUILD_ROOT}/linux-${KERNEL_VERSION}/arch/arm64/boot/Image" "${SD_ROOT}/boot/vmlinuz-${KERNEL_VERSION}" \
    || error "${?}" "Failed to deploy kernel image to ${SD_ROOT}/boot."

  echo "Copying kernel config in place..."
  install -m 0644 "${BUILD_ROOT}/linux-${KERNEL_VERSION}/.config" "${SD_ROOT}/boot/config-${KERNEL_VERSION}" \
    || error "${?}" "Failed to deploy kernel configuration to ${SD_ROOT}/boot."

  echo "Copying System.map in place..."
  install -m 0644 "${BUILD_ROOT}/linux-${KERNEL_VERSION}/System.map" "${SD_ROOT}/boot/System.map-${KERNEL_VERSION}" \
    || error "${?}" "Failed to deploy kernel map to ${SD_ROOT}/boot."

  echo "Installing dtbs..."
  INSTALL_PATH="${SD_ROOT}/boot" make -C "${BUILD_ROOT}/linux-${KERNEL_VERSION}" dtbs_install
  
  # We have to temporarily work around the fact that our kernel version is "5.4-rc8", but the built kernel identifies itself as "5.4.0-rc8"
  mv "${SD_ROOT}"/boot/dtbs/* "${SD_ROOT}"/boot/dtbs/"  ${KERNEL_VERSION}"
  
  # Our boot script looks for a specific dtb at `/boot/dtbs/<kernel>/<name>.dtb`, so make that available
  # We copy instead of move, so we're still lined up with the more traditional dtb placement (/boot/dtbs/<kernel>/<vendor>/<name>.dtb)
  cp "${SD_ROOT}"/boot/dtbs/"${KERNEL_VERSION}"/marvell/armada-8040-* "${SD_ROOT}"/boot/dtbs/"${KERNEL_VERSION}"
}

create_initramfs() {
  # We specify `newc` because that's the format the kernel expects
  # And maximize the compression because sd cards are slow
  # TODO: can we use a better form of compression here?
  echo "--> Creating initramfs..."
  find "${INITRAMFS_ROOT}" -printf '%P' | cpio -H newc -o | gzip -9 > "${BUILD_ROOT}/initramfs-${KERNEL_VERSION}" \
    || error "${?}" "Failed to create initramfs."

  echo "--> Building u-boot compatible initramfs..."
  mkimage -n "${BUILD_ROOT}/initramfs-${KERNEL_VERSION}" -A arm -O linux -T ramdisk -C none -d "${BUILD_ROOT}/initramfs-${KERNEL_VERSION}" "${SD_ROOT}/boot/initramfs-${KERNEL_VERSION}" \
    || error "${?}" "Failed to u-boot-ize our initramfs."
  
  rm -f "${BUILD_ROOT}/initramfs-${KERNEL_VERSION}" || true
}

create_modloop() {
  # We need to explicitly remove the previous modloop just in case
  # If one is still there, `mksquashfs` will try to merge rather than overwrite
  rm -f "${SD_ROOT}/boot/modloop-${KERNEL_VERSION}" \
    || error "${?}" "Failed to remove modloop from a previous build."
  
  # Ratchet up the compression as much as possible to speed up boot times
  # Again, SD cards are slow
  echo "--> Creating modloop..."  
  mksquashfs "${MODLOOP_ROOT}/" "${SD_ROOT}/boot/modloop-${KERNEL_VERSION}" -b 1048576 -comp xz -Xdict-size 100%
}

create_boot_script() {
  echo "--> Setting boot script variables..."
  sed -e "s/@@KERNEL_VERSION@@/${KERNEL_VERSION}/" boot.cmd > "${SD_ROOT}/boot/boot.cmd" \
    || error "${?}" "Failed to configure boot script with our kernel version."

  echo "--> Building u-boot compatible boot script..."
  mkimage -C none -A arm -T script -d "${SD_ROOT}/boot/boot.cmd" "${SD_ROOT}/boot/boot.scr" \
    || error "${?}" "Failed to u-boot-ize our boot script."
}

deploy_package_repository() {
  # TODO: we need to add a bunch of packages in here, figuring out dependencies and pulling them in automatically
  # For now, just use the packages provided by upstream in the distribution, and the rest can be installed the normal way
  ### This is where we need to spend a bit more time on the magic
  echo "--> Provisioning local package repository..."
  cp -R "${ALPINE_DISTRO}/apks" "${SD_ROOT}/"
}

# Ew
# Move any previous builds out of the way
# TODO: There's probably no need to keep these around, so this should just be rmeoved, or be configurable, or something
test -d "${BUILD_ROOT}" && mv "${BUILD_ROOT}" "${BUILD_ROOT}.$(date +"%Y%m%d%H%M%S")"
mkdir -p "${BUILD_ROOT}"
mkdir -p "${SD_ROOT}"
mkdir -p "${SD_ROOT}/boot"
mkdir -p "${ALPINE_DISTRO}"
mkdir -p "${INITRAMFS_ROOT}"
mkdir -p "${MODLOOP_ROOT}"

test "${BUILD_ROOT}" == "${PWD}" && error 73 "We don't support maching our build root be the location of the script"

# TODO: Better output handling, logging, etc.
# We should have a `log` function, much like `error`, instead of littering the code with `echo`
LOGDIR="${PWD}"

install_requirements
get_alpine_distribution
extract_initramfs
get_kernel
build_kernel
deploy_kernel
create_initramfs
create_modloop
deploy_package_repository

# TODO: we should build an actual SD card image instead of just a tarball
echo "--> Creating tarball that goes into SD card root..."
(cd "${SD_ROOT}" && tar -cf "${BUILD_ROOT}/alpine-macchiatobin.tar" -- *)

echo "--> All done! You can find your Alpine distribution for the MACCHIATOBIN at ${BUILD_ROOT}/alpine-macchiatobin.tar!"
