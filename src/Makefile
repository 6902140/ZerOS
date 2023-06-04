SHELL = /bin/bash

#增加编译选项，指明头文件路径
CFLAGS += -I$(ROOT)/include
CFLAGS += -I$K/include

#构建目标路径 BUILD_ROOT 	:= $(ROOT)/build
TARGET := $(BUILD_ROOT)/kernel

# 添加要*包含在构建目标中*的源文件或目录,也就是说这些全部是包含在TARGET目录下的
obj-y+=atomic/
obj-y+=driver/
obj-y+=fs/
obj-y+=kernel/
obj-y+=misc/
obj-y+=mm/
obj-y+=net/
obj-y+=platform/
obj-y+=lib/
obj-y+=tests/

obj-y += device.o
obj-y += ioctl.o
obj-y += kprint.o
obj-y += main.o
obj-y += printf.o
obj-y += console.o
obj-y += nulldev.o
obj-y += riscv.o
obj-y += utils.o

obj-y += zerodev.o


#================GEN kernel=================#
#注：OBJ_DIR 	:= $(BUILD_ROOT)/objs这是在上一级makefile中指定的
BUILD_DIR := $(subst $K,$(OBJ_DIR),$(shell pwd))
# $(subst from,to,text): subst函数用于在文本中将某个字符串from替换为另一个字符串to。
# 使用这个makefile内置函数来切换到build/objs路径下

include $(SCRIPT)/colors.mk

# 在makefile文件中”all“通常被用作目标入口点
all: start_recursive_build  $(TARGET)
#执行"all"目标时，会首先执行"start_recursive_build"规则，然后再构建$(TARGET)目标。

.PHONY: start_recursive_build

start_recursive_build:
	$(V)make -C ./ -f $(SCRIPT)/Makefile.build

# 生成内核程序
$(TARGET): $(BUILD_DIR)/built-in.o
	$(call make_echo_ld,kernel)
	$(V)$(LD) $(LDFLAGS) -L$(SCRIPT) -T $(SCRIPT)/kernel-$(platform).ld -o $(TARGET) $<
	$(V)$(OBJDUMP) -S $(TARGET) > $(TARGET).asm
	$(V)$(OBJDUMP) -t $(TARGET) | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(TARGET).sym

#使用变量$(LD)表示链接器的路径，并将链接选项$(LDFLAGS)传递给链接器。
# -L$(SCRIPT)指定了库文件的搜索路径，-T $(SCRIPT)/kernel-$(platform).ld指定了链接时使用的链接脚本。
# 最终的可执行文件将被命名为$(TARGET)，其中的$<表示依赖项$(BUILD_DIR)/built-in.o。