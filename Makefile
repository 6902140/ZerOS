SHELL = /bin/bash
MAKEFLAGS += --no-print-directory

#===========================CONFIG=================================#
# CPU NUMS(qemu)
#默认cpu个数是一个
CPUS ?= 1
# platform [qemu|k210]
#默认环境是k210开发板
platform ?= k210
# debug [on|off]
debug ?= off
# serial-port
serial-port := /dev/ttyUSB0
# gdb-port
gdb_port := 1234
# architecture
arch := riscv64
# card used to makefs
card ?= /dev/sdd
# colorful echo
colorful_output ?= on
#
display_todo_info ?= off

# compile output
verbose ?= 1
#verbose是我们自己定义的一个变量，用来控制编译输出行为
#@用于静默输出，V变量用于控制命令本身的显示输出，I变量用于控制命令执行过程的显示输出
ifeq ($(verbose), 0)
  V := @
  I := @
else ifeq ($(verbose), 1)
  V := @
  I := 
else ifeq ($(verbose), 2)
  V :=
  I :=
endif

#==========================DIR INFO================================#
ROOT 	:= $(shell pwd)#设置makefile所在的目录为根目录
SCRIPT	:= $(ROOT)/script
TOOL    := $(ROOT)/tools
BUILD_ROOT 	:= $(ROOT)/build
U_PROG_DIR	:= $(BUILD_ROOT)/user_prog
OBJ_DIR 	:= $(BUILD_ROOT)/objs
U_OBJ_DIR 	:= $(BUILD_ROOT)/u_objs
K := $(ROOT)/src
U := $(ROOT)/user
P := $(ROOT)/src/platform

#==========================TOOLCHAINS==============================#
TOOLPREFIX := riscv64-unknown-elf-
# TOOLPREFIX := /opt/kendryte-toolchain/bin/riscv64-unknown-elf-
CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump


ifeq ($(shell echo $$UID), 0)
SUDO := 
else
SUDO := sudo
endif

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

include $(SCRIPT)/cflags.mk
include $(SCRIPT)/colors.mk
LDFLAGS := -z max-page-size=4096

export LDFLAGS CFLAGS

#============================QEMU==================================#
QEMU = qemu-system-riscv64
QEMUOPTS += -machine virt -bios bootloader/sbi-qemu -kernel $(BUILD_ROOT)/kernel -m 128M -smp $(CPUS) -nographic
QEMUOPTS += -drive file=$(fs.img),if=none,format=raw,id=x0
QEMUOPTS += -global virtio-mmio.force-legacy=false
QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0
#设置qemu环境的一些属性
#===========================RULES BEGIN============================#、
#调用objcopy工具根据build目录下的内核目标文件生成kernel.bin二进制文件
#bs=128k：使用bs选项设置块大小为128k。这表示dd命令将按照128k的块大小进行读取和写入操作。
#注意seek=1，所以copy的时候其实是跳过了第一个块的，也就是说，k210.bin第一个块的内容没有被覆盖
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

GEN_HEADER_DIR := $(ROOT)/include/generated

syscall := $(GEN_HEADER_DIR)/syscall_gen.h
profile := $(GEN_HEADER_DIR)/profile_gen.h

#makefile语法：$(call function-name, arguments)调用函数，result := $(call my_func, arg1, arg2)
#make_echo_color_bold是在colors.mk中定义的函数，用于颜色输出
#K 是K := $(ROOT)/src 是定义的OS所有源文件的目录，所以make -C指令是用执行在$(K)目录下的makefile文件
# 没错，就是这里：make -C $k 调用 K 目录下makefile文件制作kenerl
kernel: $(syscall)
	$(call make_echo_color_bold, white,\nCFLAGS = $(CFLAGS)\n)
	$(V)make -C $K  
	$(call make_echo_color_bold, green,\nKERNEL BUILD SUCCESSFUL!\n)

$(syscall): entry/syscall.tbl
	$(call make_echo_generate_file,syscall_tbl)
	$(V)mkdir -p $(GEN_HEADER_DIR)
	$(V)python3 $(SCRIPT)/sys_tbl.py $< -o $(GEN_HEADER_DIR)/syscall_gen.h -t tbl
	$(V)python3 $(SCRIPT)/sys_tbl.py $< -o $(GEN_HEADER_DIR)/syscall.h -t hdr

ifeq ("${debug}", "on")
kernel: $(profile)

$(profile): entry/profile.tbl
	$(call make_echo_generate_file,profile)
	$(V)mkdir -p $(GEN_HEADER_DIR)
	$(V)python3 $(SCRIPT)/profile_tbl.py $< -o $@
endif

SBI_TARGET_PATH := target/riscv64imac-unknown-none-elf/debug
sbi-k210:
	$(V)cd bootloader/rustsbi-k210 && cargo make
	$(V)cp bootloader/rustsbi-k210/$(SBI_TARGET_PATH)/rustsbi-k210 bootloader/$@
sbi-qemu:
	$(V)cd bootloader/rustsbi-qemu && cargo make
	$(V)cp bootloader/rustsbi-qemu/$(SBI_TARGET_PATH)/rustsbi-qemu bootloader/$@

clean: 
	-$(V)rm -rf $(BUILD_ROOT)
	-$(V)rm -rf $(SCRIPT)/mkfs
	-$(V)rm -rf $(GEN_HEADER_DIR)
	-$(V)rm -rf os.bin
	-$(V)rm -rf sbi-qemu
	-$(V)rm -rf kernel-qemu
	-$(V)rm -rf $K/include/generated
	$(call make_echo_color_bold, green,\nCLEAN DONE\n)

fs.img = $(BUILD_ROOT)/fs.img

ifeq ("$(platform)", "qemu")
run: $(fs.img)
endif

# 磁盘映像制作
MNT_DIR := $(BUILD_ROOT)/mnt
fs.img : $(fs.img)

$(MNT_DIR):
	$(V)mkdir -p $(MNT_DIR)


# $(fs.img): user $(MNT_DIR)
# 	$(V)dd if=/dev/zero of=$@ bs=1M count=30
# 	$(V)mkfs.vfat -F 32 -s 8 $@
# 	$(SUDO) mount $@ $(MNT_DIR)
# 	$(SUDO) cp -r $(U_PROG_DIR)/* $(MNT_DIR)/
# 	$(SUDO) umount $(MNT_DIR)

$(fs.img): user
	$(V)dd if=/dev/zero of=$@ bs=1M count=257
	$(V)mformat -i $@ -F -c 8 ::
	$(V)mcopy -i $@ $(U_PROG_DIR)/* ::
# 似乎可以截断以减少体积...因为我们用不到后面的簇
	$(V)truncate $(fs.img) -s 30M


user: $(syscall)
	$(V)mkdir -p $(U_PROG_DIR)
	$(V)make -C $U
	$(V)cp -r $U/raw/. $(U_PROG_DIR)
	$(call make_echo_color_bold, green,\nUSER EXE BUILD SUCCESSFUL!\n)

mnt: $(fs.img)
	@$(SUDO) mount $< $(MNT_DIR)
umnt: $(MNT_DIR)
	@$(SUDO) umount $(MNT_DIR)

sdcard: $(fs.img)
	$(SUDO) dd if=$(fs.img) of=$(card) bs=4M

attach:
	python3 -m serial.tools.miniterm --eol LF --dtr 0 --rts 0 --filter direct $(serial-port) 115200

.PHONY: qemu clean all user kernel entry sbi-k210 fs.img mnt sdcard

#===========================RULES END==============================#
