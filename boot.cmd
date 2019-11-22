if test -n "${console}"; then
  setenv bootargs "${bootargs} console=${console}"
fi

if test -z "${fk_kvers}"; then
   setenv fk_kvers '@@KERNEL_VERSION@@'
fi

setenv bootargs ${bootargs} earlycon log_level=7 net.ifnames=0 modloop=/boot/modloop-${fk_kvers}

# These two blocks should be the same apart from the use of
# ${fk_kvers} in the first, the syntax supported by u-boot does not
# lend itself to removing this duplication.

if test -n "${fdtfile}"; then
   setenv fdtpath dtbs/${fk_kvers}/${fdtfile}
else
   setenv fdtpath dtb-${fk_kvers}
fi

if test -z "${distro_bootpart}"; then
  setenv partition ${bootpart}
else
  setenv partition ${distro_bootpart}
fi



load ${devtype} ${devnum}:${partition} ${kernel_addr_r} ${prefix}vmlinuz-${fk_kvers} \
&& load ${devtype} ${devnum}:${partition} ${fdt_addr_r} ${prefix}${fdtpath} \
&& load ${devtype} ${devnum}:${partition} ${ramdisk_addr_r} ${prefix}initramfs-${fk_kvers} \
&& echo "Booting Alpine${fk_kvers} from ${devtype} ${devnum}:${partition}..." \
&& booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}

load ${devtype} ${devnum}:${partition} ${kernel_addr_r} ${prefix}vmlinuz \
&& load ${devtype} ${devnum}:${partition} ${fdt_addr_r} ${prefix}dtb \
&& load ${devtype} ${devnum}:${partition} ${ramdisk_addr_r} ${prefix}initramfs.img \
&& echo "Booting Alpinefrom ${devtype} ${devnum}:${partition}..." \
&& booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
