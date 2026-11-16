ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NoticeDeleteAnimation
NoticeDeleteAnimation_FILES = NLRootListController.m NLBannerStatusController.m
NoticeDeleteAnimation_INSTALL_PATH = /Library/PreferenceBundles
NoticeDeleteAnimation_FRAMEWORKS = UIKit Foundation QuartzCore
NoticeDeleteAnimation_PRIVATE_FRAMEWORKS = Preferences
# Xcode SDK may omit this private linker stub; CI pins the official Theos SDK file.
NL_PRIVATE_FRAMEWORKS ?= $(abspath ../.ci-frameworks)
NoticeDeleteAnimation_LDFLAGS += -F$(NL_PRIVATE_FRAMEWORKS)
NoticeDeleteAnimation_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NoticeDeleteAnimation_RESOURCE_DIRS = ../layout/Library/PreferenceBundles/NoticeDeleteAnimation.bundle

include $(THEOS_MAKE_PATH)/bundle.mk
