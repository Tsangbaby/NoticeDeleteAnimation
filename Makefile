ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoticeListTweak

NoticeListTweak_FILES = src/NLDustRenderer.m \
                        src/DustShaderSource.m \
                        src/NLNotificationDismissalSnapshot.m \
                        src/NLWithdrawalEffect.m \
                        src/NLPreferences.m \
                        src/NLNotificationHookLoader.m \
                        src/NLNotificationListHooks.m \
                        src/NLIconDust.m \
                        src/NLLockScreenDust.m \
                        src/NLBannerDust.m \
                        src/NLIslandDust.m \
                        src/NLStatusProbe.m
NoticeListTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NoticeListTweak_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Metal
NoticeListTweak_LIBRARIES = substrate
NoticeListTweak_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
