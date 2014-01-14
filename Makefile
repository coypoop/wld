# wld: Makefile

include config.mk

VERSION_MAJOR   := 0
VERSION_MINOR   := 0
VERSION         := $(VERSION_MAJOR).$(VERSION_MINOR)

WLD_LIB         := libwld.so
WLD_LIB_MAJOR   := $(WLD_LIB).$(VERSION_MAJOR)
WLD_LIB_MINOR   := $(WLD_LIB_MAJOR).$(VERSION_MINOR)

TARGETS         := wld.pc libwld.a $(WLD_LIB) $(WLD_LIB_MAJOR) $(WLD_LIB_MINOR)
CLEAN_FILES     := $(TARGETS)

WLD_REQUIRES = fontconfig pixman-1
WLD_REQUIRES_PRIVATE = freetype2
WLD_SOURCES =           \
    color.c             \
    context.c           \
    drawable.c          \
    font.c              \
    renderer.c
WLD_HEADERS = wld.h

ifeq ($(ENABLE_DEBUG),1)
    WLD_CPPFLAGS += -DENABLE_DEBUG=1
endif

ifeq ($(ENABLE_DRM),1)
    WLD_REQUIRES_PRIVATE += libdrm
    WLD_SOURCES += drm.c dumb.c
    WLD_HEADERS += drm.h
endif

ifeq ($(ENABLE_PIXMAN),1)
    WLD_SOURCES += pixman.c
    WLD_HEADERS += pixman.h
endif

ifeq ($(ENABLE_WAYLAND),1)
    WLD_REQUIRES_PRIVATE += wayland-client
    WLD_SOURCES += wayland.c
    WLD_HEADERS += wayland.h

    ifneq ($(findstring shm,$(WAYLAND_INTERFACES)),)
        WLD_SOURCES += wayland-shm.c
        WLD_HEADERS += wayland-shm.h
        WLD_CPPFLAGS += -DWITH_WAYLAND_SHM=1
    endif

    ifneq ($(findstring drm,$(WAYLAND_INTERFACES)),)
        WLD_SOURCES += wayland-drm.c protocol/wayland-drm-protocol.c
        WLD_HEADERS += wayland-drm.h
        WLD_CPPFLAGS += -DWITH_WAYLAND_DRM=1
    endif
endif

ifneq ($(findstring intel,$(DRM_DRIVERS)),)
    WLD_REQUIRES_PRIVATE += libdrm_intel intelbatch
    WLD_SOURCES += intel.c
    WLD_CPPFLAGS += -DWITH_DRM_INTEL=1
endif

ifeq ($(if $(V),$(V),0), 0)
    define quiet
        @echo "  $1	$@"
        @$(if $2,$2,$($1))
    endef
else
    quiet = $(if $2,$2,$($1))
endif

WLD_STATIC_OBJECTS  = $(WLD_SOURCES:%.c=%.o)
WLD_SHARED_OBJECTS  = $(WLD_SOURCES:%.c=%.lo)
WLD_PACKAGES        = $(WLD_REQUIRES) $(WLD_REQUIRES_PRIVATE)
WLD_PACKAGE_CFLAGS ?= $(call pkgconfig,$(WLD_PACKAGES),cflags,CFLAGS)
WLD_PACKAGE_LIBS   ?= $(call pkgconfig,$(WLD_PACKAGES),libs,LIBS)

CLEAN_FILES += $(WLD_STATIC_OBJECTS) $(WLD_SHARED_OBJECTS)

FINAL_CFLAGS = $(CFLAGS) -fvisibility=hidden -std=c99
FINAL_CPPFLAGS = $(CPPFLAGS) -D_XOPEN_SOURCE=700 -D_BSD_SOURCE

# Warning/error flags
FINAL_CFLAGS += -Werror=implicit-function-declaration -Werror=implicit-int \
                -Werror=pointer-sign -Werror=pointer-arith \
                -Wall -Wno-missing-braces

ifeq ($(ENABLE_DEBUG),1)
    FINAL_CPPFLAGS += -DENABLE_DEBUG=1
    FINAL_CFLAGS += -g
endif

compile     = $(call quiet,CC) $(FINAL_CPPFLAGS) $(FINAL_CFLAGS) -c -o $@ $< \
              -MMD -MP -MF .deps/$(basename $<).d -MT $(basename $@).o -MT $(basename $@).lo
link        = $(call quiet,CCLD,$(CC)) $(FINAL_CFLAGS) -o $@ $^
pkgconfig   = $(sort $(foreach pkg,$(1),$(if $($(pkg)_$(3)),$($(pkg)_$(3)), \
                                           $(shell $(PKG_CONFIG) --$(2) $(pkg)))))

.PHONY: all
all: $(TARGETS)

include protocol/local.mk

.deps:
	@mkdir "$@"

%.o: %.c | .deps
	$(compile) $(WLD_CPPFLAGS) $(WLD_PACKAGE_CFLAGS)

%.lo: %.c | .deps
	$(compile) $(WLD_CPPFLAGS) $(WLD_PACKAGE_CFLAGS) -fPIC

wayland-drm.o wayland-drm.lo: protocol/wayland-drm-client-protocol.h

wld.pc: wld.pc.in
	$(call quiet,GEN,sed)                                       \
	    -e "s:@VERSION@:$(VERSION):"                            \
	    -e "s:@PREFIX@:$(PREFIX):"                              \
	    -e "s:@LIBDIR@:$(LIBDIR):"                              \
	    -e "s:@INCLUDEDIR@:$(INCLUDEDIR):"                      \
	    -e "s:@WLD_REQUIRES@:$(WLD_REQUIRES):"                  \
	    -e "s:@WLD_REQUIRES_PRIVATE@:$(WLD_REQUIRES_PRIVATE):"  \
	    $< > $@

libwld.a: $(WLD_STATIC_OBJECTS)
	$(call quiet,AR) cr $@ $^

$(WLD_LIB_MINOR): $(WLD_SHARED_OBJECTS)
	$(link) $(WLD_PACKAGE_LIBS) -shared -Wl,-soname,$(WLD_LIB_MAJOR),-no-undefined

$(WLD_LIB_MAJOR) $(WLD_LIB): $(WLD_LIB_MINOR)
	$(call quiet,SYM,ln -sf) $< $@

$(foreach dir,LIB PKGCONFIG,$(DESTDIR)$($(dir)DIR)) $(DESTDIR)$(INCLUDEDIR)/wld:
	mkdir -p "$@"

.PHONY: install
install: $(TARGETS) | $(foreach dir,LIB PKGCONFIG,$(DESTDIR)$($(dir)DIR)) $(DESTDIR)$(INCLUDEDIR)/wld
	install -m0644 wld.pc "$(DESTDIR)$(PKGCONFIGDIR)"
	install -m0644 $(WLD_HEADERS) "$(DESTDIR)$(INCLUDEDIR)/wld"
	install -m0644 libwld.a "$(DESTDIR)$(LIBDIR)"
	install -m0755 $(WLD_LIB_MINOR) "$(DESTDIR)$(LIBDIR)"
	ln -sf $(WLD_LIB_MINOR) "$(DESTDIR)$(LIBDIR)/$(WLD_LIB_MAJOR)"
	ln -sf $(WLD_LIB_MINOR) "$(DESTDIR)$(LIBDIR)/$(WLD_LIB)"

.PHONY: clean
clean:
	rm -rf $(CLEAN_FILES)

-include .deps/*.d

