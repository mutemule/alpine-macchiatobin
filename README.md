## Synopsis

This is a very quick script to build an Alpine distribution for use on the [MACCHIATObin](https://macchiatobin.net/) Single Shot and Double Shot boards.

## Requirements

1. An existing MACCHIATObin board for compiling (cross-compiling has been problematic)
2. An SD card imaged with the [SolidRun ARMADA A8040 Debian distribution](https://developer.solid-run.com/knowledge-base/armada-8040-debian/)
3. Confirmed working serial console ([Linux](http://wiki.macchiatobin.net/tiki-index.php?page=Serial+connection+-+Linux) / [Windows](http://wiki.macchiatobin.net/tiki-index.php?page=Serial+connection+-+Windows))
4. Another computer of some sort. Any sort. Whatever tickles your fancy, but it will need to have a way to write to your MicroSD card
5. Oh right: a spare MicroSD card. Almost any size will do -- this build is about 500MB in size when completed.
6. Some spare time

NB: Minicom was acting strangely for me on Linux; I found it much easier to use `cu`: `cu -l /dev/ttyUSB0 -s 115200` (you'll need to have appropriate permissions to open the serial device -- for Debian distributions, add yourself to the `dialout` group)

## Instructions

1. (Optional) [Update the U-Boot](https://developer.solid-run.com/knowledge-base/armada-8040-machiatobin-u-boot-and-atf/) on your board.
** If you put the resulting flash-image.bin on the root of a FAT32-formatted MicroSD card, you can update u-boot with `bubt flash-image.bin spi mmc` at the u-boot prompt
2. Get your Debian-based MACCHIATObin online
3. Check out this source tree, and copy it to the host
4. SSH over (default username/password is `debian`), spin up a `tmux` session, and type `bash build-image.sh`
5. Once complete, copy the resulting tarball back to your computer
6. Initialize your MicroSD card with an MSDOS partition table -- using UEFI can cause U-Boot to behave weirdly
7. Create a single partition, of at least 550MB, and format it with your filesystem of choice -- confirmed that FAT32 and ext4 both work just fine
8. Explode the tarball you copied in #5 above into the root of the MicroSD card.

You should now be able to put this MicroSD card into your MACCHIATObin board, power it on, and 30-45 seconds later, you'll have an Alpine prompt on the serial console.

Note that I have *not* tested this with the U-Boot that ships on the boards; I have built something following the instructions above and deployed that; it's considerably newer, and may behave differently than the distributed u-boot. Yes, I'm aware that there are considerably more convoluted instructions pointing you to a Marvell-specific fork of u-boot with some custom patches and checking out weird branches and whatnot -- don't follow those instructions. They work just fine, but so do the ones above (and the ones above seem to be more current).

## TODO

All the things I'd like to change but haven't gotten around to yet:

1. Add more packages in the base distribution. Specifically, I'm looking at adding `nftables` for firewall management, `tcpdump` and `ethtool` to troubleshoot network issues, and ... I forget the rest, but I have them noted down ... somewhere.
2. Clean up the kernel configuration a bit.
3. Produce an SD card image, instead of a tarball.
4. Automatically identify the latest Alpine distribution and use that -- maybe even be able to specify `edge` or `stable`.
5. Tune up the base install to mount the on-board `mmc` device automatically (to be used for LBU)
6. Really clean up that build script. It's pretty rough.

## FAQ
### Why is there a FAQ? Nobody uses this but you.
Well, yeah. This is more of a "Fun and Anticipated Questions" than a "Frequently Asked Questions".

### What's a Fun question?
Depends on your perspective -- but I find asking people about their grandmothers to be fun.

### How do I create an MSDOS partition table?
WARNING: THIS WILL REMOVE ALL YOUR DATA

If you think you might possibly have something stored on that MicroSD card that maybe you, or your grandmother, will want to access at some point in the future, please back it up now. You *will* lose that data during this process.

#### Windows
1. Insert the MicroSD card into your computer, using whatever mechanism you have: native MicroSD reader, SD reader and a MicroSD adapter, or some new-fangled USB dongle of some sort that maybe does both
2. Launch Powershell as admin (Search Bar -> "Windows Powershell" -> Right-Click -> "Run as administrator")
3. Say that "Yes", you want to allow this program to make changes to your computer
4. Type `diskpart` (followed by the enter button, of course) to launch the disk partition manager
5. Type `list disk` to show the available disks, and figure out which one is your MicroSD card (hint: it will *not* be Disk 0)
6. Type `select disk <n>`, where `n` is the number of the disk assigned to your MicroSD card
7. Type `clean` (this is the step that removes all your data)
8. Type `convert mbr` to create a new MSDOS partition table
9. Type `create partition primary` to create a new partition (`diskpart` will also magically select this partition for us, which is one less thing for us to type out!)
10. Type `format quick fs=fat32 label="ALPINE"` to format this new partition
11. Sometimes Windows doesn't like to make the drive actually be available (¯\_(ツ)_/¯), so we gotta do that part for us. Pick a drive letter that isn't in use -- in my case, let's use `J` -- and assign it: `assign letter=j`

Voila! You now have a blank, MSDOS-compatible, FAT32-formatted MicroSD card at your chosen drive letter (`J:`, if you followed everything verbatim).

#### Linux
1. Insert the MicroSD card into your computer. Since you're running Linux, you probably have a homebrew MicroSD reader attached to a breadboard somewhere in the back of a project drawer.
2. Launch whatever newfangled partition manager all the Linux kids are using these days: `fdisk`? `cfdisk`? `gdisk`? `parted`? `debug`?
3. Refer to whatever documentation exists to figure out how to create an MSDOS partition table. Create it.

Yeah, okay, this is less than helpful. But it's late, I'm tired, and I don't want to admit to the world that I still use `fdisk` and don't know how to use any of the newer partition managers.

### I've previously mucked about with u-boot and things are a bit weird now -- help!
The boards are pretty forgiving, thankfully. If you trash u-boot in the SPI, you can flash it to an MMC card directly (instructions can be found in the `Update the U-Boot` link above), and re-flash to SPI from there. This is a bit too complicate for me to toss as an answer in a light-hearted FAQ, so feel free to hit me up if you need help (open an issue, @-me on Twitter, whatever).

If you think it's just the u-boot environment that needs cleaning, that's an easy fix! Get on your console, power up the board, interrupt the boot process, and then just type `env default -a` followed by `env save`. That's it! Your U-Boot configuration is reset to defaults. At this point, I would recommend removing power from the board -- a simple `reset` doesn't always work as expected here.

### This kernel configuration looks ... strange.
Yeah. Well, as I noted above, SD cards are slow. Almost the entirety of the boot time is spent reading the `initramfs` from the SD card, so I'm trying to cut out as many kernel modules as I possible can. The first successful boot I had took almost a full minute, and I managed to cut that down to about 30 seconds just by stripping unnecessary cruft from the kernel (do you really need Android driver support on this thing?).

I still have a fair bit of work to do here: some more modules to cut out, some others to add back in, then finally actually going over the configuration and making sure it actually makes sense. I'm targeting usage as a wired router: no wireless cards, no GPU support, just passin' packets.

### I'd really like Package X to be in the root
So would I, probably. Thankfully it's pretty easy to add a package to your system once it's up and running, so modifying the base system is a lower priority right now.

### Why do we build on Debian?
Because all my cross-compiling efforts were failing, and using SolidRun's Debian distribution was the easiest way to get a stable system up and running, with a reasonably current version of `gcc` available.

This will *probably* work on any Debian derivative (i.e. Ubuntu) with no modifications, but I haven't tested it. Using this script with any other distribution will require some slight modifications -- probably just to the package installation stuff, and the build flags we use when building the kernel.
