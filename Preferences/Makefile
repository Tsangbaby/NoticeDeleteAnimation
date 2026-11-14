ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NDAPreferences
NDAPreferences_FILES = NDASettingsController.swift NDAPreferencesBridge.m
NDAPreferences_SWIFT_BRIDGING_HEADER = NDAPreferencesBridge.h
NDAPreferences_SWIFT_VERSION = 5
NDAPreferences_CFLAGS = -fobjc-arc -Wall -Wextra
NDAPreferences_FRAMEWORKS = UIKit Foundation CoreFoundation
NDAPreferences_PRIVATE_FRAMEWORKS = Preferences
# Xcode public SDKs omit this private framework's link stub. Cloud CI obtains
# the unmodified stub from a pinned official theos/sdks commit, hash-checked.
NDA_PRIVATE_FRAMEWORKS ?= $(abspath ../.ci-frameworks)
NDAPreferences_LDFLAGS += -F$(NDA_PRIVATE_FRAMEWORKS)
NDAPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
