ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoticeDeleteAnimation

NoticeDeleteAnimation_FILES = src/NLDustRenderer.m \
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
NoticeDeleteAnimation_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NoticeDeleteAnimation_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Metal
NoticeDeleteAnimation_LIBRARIES = substrate
NoticeDeleteAnimation_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
