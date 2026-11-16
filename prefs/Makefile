ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NoticeListTweak
NoticeListTweak_FILES = NLRootListController.m NLBannerStatusController.m
NoticeListTweak_INSTALL_PATH = /Library/PreferenceBundles
NoticeListTweak_FRAMEWORKS = UIKit Foundation QuartzCore
NoticeListTweak_PRIVATE_FRAMEWORKS = Preferences
# Xcode SDK may omit this private linker stub; CI pins the official Theos SDK file.
NL_PRIVATE_FRAMEWORKS ?= $(abspath ../.ci-frameworks)
NoticeListTweak_LDFLAGS += -F$(NL_PRIVATE_FRAMEWORKS)
NoticeListTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NoticeListTweak_RESOURCE_DIRS = ../layout/Library/PreferenceBundles/NoticeListTweak.bundle

include $(THEOS_MAKE_PATH)/bundle.mk
