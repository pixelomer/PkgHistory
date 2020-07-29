TARGET := iphone:clang:latest:7.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = dpkglogger

dpkglogger_FILES = main.m
dpkglogger_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
dpkglogger_CODESIGN_FLAGS = -Sentitlements.plist
dpkglogger_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
SUBPROJECTS += App
include $(THEOS_MAKE_PATH)/aggregate.mk
