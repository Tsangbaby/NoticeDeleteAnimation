ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
# Use a matching upstream or RootHide Theos. Override at invocation, never infer jailbreak paths.
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NoticeDeleteAnimation
NoticeDeleteAnimation_FILES = $(wildcard Sources/Core/*.swift) $(wildcard Sources/Tweak/*.swift) Sources/Bridge/NDABridge.m
NoticeDeleteAnimation_SWIFT_BRIDGING_HEADER = Sources/Bridge/NDABridge.h
NoticeDeleteAnimation_SWIFT_VERSION = 5
NoticeDeleteAnimation_CFLAGS = -fobjc-arc -Wall -Wextra
NoticeDeleteAnimation_SWIFTFLAGS = -O
NoticeDeleteAnimation_FRAMEWORKS = UIKit QuartzCore Foundation
NoticeDeleteAnimation_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
