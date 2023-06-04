SHELL= /bin/bash
MAKEFLAGS+=--no-print-directory

# 在makefile里?=是一个设置默认值的语句，是当且仅在没有设定值的时候的值
CPUS?=1

debug?=off



#设置root为当前目录
ROOT:=$(shell pwd)# $(....) 用于将括号内的变量名替换为其对应的值
SCRIPT:=$(ROOT)/script
BUILD_ROOT:=$(ROOT)/build
U_PROG_DIR:=$(BUILD_ROOT)/user_prog
OBJ_DIR:=$(BUILD_ROOT)/objs
U_OBJ_DIR:=$(BUILD_ROOT)/u_objs

#变量名 := 值，这种方式是立即展开的赋值语法。它表示变量的值在赋值时就会被展开，而不是在使用时才展开。这种方式可以理解为变量的值被静态地计算和保存下来。
TOOLPREFIX:=riscv64-unknown-elf-

cc=$(TOOLPREFIX)gcc
AS=$(TOOLPREFIX)gas
LD=$(TOOLPREFIX)ld
OBJCOPY=$(TOOLPREFIX)objcopy
OBJDUMP=$(TOOLPREFIX)objdump


#=============================EXPORT===============================#

export ROOT SCRIPT OBJ_DIR U_OBJ_DIR U_PROG_DIR K U P BUILD_ROOT TOOL
export CC AS LD OBJCOPY OBJDUMP SUDO
export debug platform arch colorful_output V I

#=============================FLAGS================================#
# platform
CFLAGS += $(EXTRA_CFLAGS)
ifeq ("${platform}", "qemu")
  CFLAGS += -DQEMU
  CFLAGS += -DCPUS=$(CPUS)
else
  CFLAGS += -DK210
endif

# debug
ifeq ("${debug}", "on")
  CFLAGS += -DDEBUG
endif

ifeq ("${display_todo_info}", "on")
	CFLAGS += -DTODO
endif

LDFLAGS := -z max-page-size=4096

export LDFLAGS CFLAGS




#============================QEMU==================================#
QEMU = qemu-system-riscv64
QEMUOPTS += -machine virt -bios bootloader/sbi-qemu -kernel $(BUILD_ROOT)/kernel -m 128M -smp $(CPUS) -nographic

#-machine virt: 设置虚拟机使用virt机型。
#-bios bootloader/sbi-qemu: 指定SBI固件的路径，这里是bootloader/sbi-qemu。
#-kernel $(BUILD_ROOT)/kernel: 指定内核映像文件的路径，这里是$(BUILD_ROOT)/kernel。
#-m 128M: 设置虚拟机的内存大小为128M。
#-smp $(CPUS): 指定虚拟机的处理器核心数量，这里使用了变量$(CPUS)的值。
#-nographic: 禁用图形化界面，以纯文本方式运行虚拟机。

QEMUOPTS += -drive file=$(fs.img),if=none,format=raw,id=x0

#-drive是QEMU的选项，用于定义磁盘驱动器。
#file=$(fs.img)是-drive选项的一个子选项，用于指定磁盘驱动器的镜像文件。$(fs.img)表示fs.img变量的值，这里使用了变量展开机制。
#if=none是-drive选项的另一个子选项，用于指定磁盘驱动器的接口类型。none表示不连接到任何接口。
#format=raw是-drive选项的子选项，用于指定磁盘驱动器的镜像文件格式。这里设置为raw，表示使用原始的二进制格式。
#id=x0是-drive选项的子选项，用于给磁盘驱动器分配一个唯一的标识符。这里设置为x0。


QEMUOPTS += -global virtio-mmio.force-legacy=false
#具体而言，将 force-legacy 属性设置为 false，意味着禁用对 virtio-mmio 设备的强制遗留支持。

QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0
#通过添加这个选项，可以在 QEMU 虚拟机中模拟一个 virtio 块设备，供操作系统或应用程序使用。

#===========================RULES BEGIN============================#
all: kernel
	$(OBJCOPY) $(BUILD_ROOT)/kernel -S -O binary $(BUILD_ROOT)/kernel.bin
	$(OBJCOPY) bootloader/sbi-k210 -S -O binary $(BUILD_ROOT)/k210.bin
	dd if=$(BUILD_ROOT)/kernel.bin of=$(BUILD_ROOT)/k210.bin bs=128k seek=1
	mv $(BUILD_ROOT)/k210.bin os.bin


run: kernel
ifeq ("$(debug)", "on")
	$(call make_echo_color_bold, magenta,\nNotice: Run In Debug Mode\n)
endif
ifeq ("$(platform)", "k210") # k210
	$(OBJCOPY) $(BUILD_ROOT)/kernel -S -O binary $(BUILD_ROOT)/kernel.bin
	$(OBJCOPY) bootloader/sbi-k210 -S -O binary $(BUILD_ROOT)/k210.bin
	dd if=$(BUILD_ROOT)/kernel.bin of=$(BUILD_ROOT)/k210.bin bs=128k seek=1
	$(SUDO) chmod 777 $(serial-port)
# 注意：若是使用自装的kflash可能会出现重复换行的问题，原因在于kflash默认的terminal没有设置eol标志，详见kflash: 1105
	$(TOOL)/kflash.py -p $(serial-port) -b 1500000 -B dan -t $(BUILD_ROOT)/k210.bin
#	python3 -m serial.tools.miniterm --eol LF --dtr 0 --rts 0 --filter direct $(serial-port) 115200
else ifeq ("$(platform)", "qemu") # qemu
	$(QEMU) $(QEMUOPTS) $(EXTRA_QEMUOPTS)
else # others
	$(call make_echo_color_bold, red,\nUNSUPPORT PLATFORM!\n)
endif