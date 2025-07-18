#
# Copyright (C) 2006-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

GIT_COMMIT_DATE:=$(shell git log -n 1 --pretty=%ad --date=short . | sed 's|-|.|g' )
GIT_COMMIT_TSTAMP:=$(shell git log -n 1 --pretty=%at . )

PKG_NAME:=lime-system
PKG_VERSION=$(GIT_COMMIT_DATE)~$(GIT_COMMIT_TSTAMP)

LIME_ID:=LiMe
LIME_RELEASE:=$(shell git branch | sed -n '/\* /s///p')
LIME_CODENAME:=development
LIME_BRANCH:=$(shell git branch | sed -n '/\* /s///p')
LIME_REVISION:=$(shell git log -n 1 --pretty=%h)
LIME_BUILDDATE:=$(shell date +%Y%m%d_%H%M)
LIME_DESCRIPTION:=$(LIME_ID) $(LIME_RELEASE) $(LIME_CODENAME) ($(LIME_BRANCH) rev. $(LIME_REVISION) $(LIME_BUILDDATE))

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  TITLE:=LibreMesh system core
  CATEGORY:=LibreMesh
  MAINTAINER:=Gioacchino Mazzurco <gio@eigenlab.org>
  URL:=http://libremesh.org
  DEPENDS:=+firewall4 +libiwinfo-lua +lua +libuci-lua +luci-lib-ip +luci-lib-nixio +luci-lib-jsonc
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	LibreMesh is a modular meta-firmare this package provide the core of it
	which articulates all LiMe modules around it
endef

define Build/Compile
endef

LIME_VERSION_SED:=$(SED)   's,%LIME_ID%,$(LIME_ID),g' \
			-e 's,%LIME_RELEASE%,$(LIME_RELEASE),g' \
			-e 's,%LIME_CODENAME%,$(LIME_CODENAME),g' \
			-e 's,%LIME_BRANCH%,$(LIME_BRANCH),g' \
			-e 's,%LIME_REVISION%,$(LIME_REVISION),g' \
			-e 's,%LIME_BUILDDATE%,$(LIME_BUILDDATE),g' \
			-e 's,%LIME_DESCRIPTION%,$(LIME_DESCRIPTION),g'

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/
	$(CP) ./files/* $(1)/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/lime-config/
	$(LIME_VERSION_SED) \
		$(1)/etc/lime_release \
		$(1)/etc/profile.d/10-lime-banner.sh
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
#[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/firewall-lime enable || true
# Add here stuff to be executed after installation at image creation time
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
