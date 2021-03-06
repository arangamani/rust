
# Create variables HOST_<triple> containing the host part
# of each target triple.  For example, the triple i686-darwin-macos
# would create a variable HOST_i686-darwin-macos with the value 
# i386.
define DEF_HOST_VAR
  HOST_$(1) = $(subst i686,i386,$(word 1,$(subst -, ,$(1))))
endef
$(foreach t,$(CFG_TARGET_TRIPLES),$(eval $(call DEF_HOST_VAR,$(t))))
$(foreach t,$(CFG_TARGET_TRIPLES),$(info cfg: host for $(t) is $(HOST_$(t))))

CFG_GCCISH_FLAGS := -fno-strict-aliasing
CFG_GCCISH_LINK_FLAGS :=

# On Darwin, we need to run dsymutil so the debugging information ends
# up in the right place.  On other platforms, it automatically gets
# embedded into the executable, so use a no-op command.
CFG_DSYMUTIL := true

ifeq ($(CFG_VALGRIND),)
  CFG_GCCISH_CFLAGS += -DNVALGRIND
endif

ifneq ($(findstring freebsd,$(CFG_OSTYPE)),)
  CFG_LIB_NAME=lib$(1).so
  CFG_LIB_GLOB=lib$(1)-*.so
  CFG_GCCISH_CFLAGS += -fPIC -I/usr/local/include
  CFG_GCCISH_LINK_FLAGS += -shared -fPIC -lpthread -lrt
  CFG_GCCISH_DEF_FLAG := -Wl,--export-dynamic,--dynamic-list=
  CFG_GCCISH_PRE_LIB_FLAGS := -Wl,-whole-archive
  CFG_GCCISH_POST_LIB_FLAGS := -Wl,-no-whole-archive
  CFG_GCCISH_CFLAGS_i386 += -m32
  CFG_GCCISH_LINK_FLAGS_i386 += -m32
  CFG_GCCISH_CFLAGS_x86_64 += -m64
  CFG_GCCISH_LINK_FLAGS_x86_64 += -m64
  CFG_UNIXY := 1
  CFG_LDENV := LD_LIBRARY_PATH
  CFG_DEF_SUFFIX := .bsd.def
  CFG_INSTALL_NAME =
  CFG_PERF_TOOL := /usr/bin/time

  # FIXME (1825): We're deadlocking on FreeBSD
  ifndef RUST_THREADS
    RUST_THREADS=1
    export RUST_THREADS
  endif
endif

ifneq ($(findstring linux,$(CFG_OSTYPE)),)
  CFG_LIB_NAME=lib$(1).so
  CFG_LIB_GLOB=lib$(1)-*.so
  CFG_GCCISH_CFLAGS += -fPIC
  CFG_GCCISH_LINK_FLAGS += -shared -fPIC -ldl -lpthread -lrt
  CFG_GCCISH_DEF_FLAG := -Wl,--export-dynamic,--dynamic-list=
  CFG_GCCISH_PRE_LIB_FLAGS := -Wl,-whole-archive
  # -znoexecstack is here because librt is for some reason being created
  # with executable stack and Fedora (or SELinux) doesn't like that (#798)
  CFG_GCCISH_POST_LIB_FLAGS := -Wl,-no-whole-archive -Wl,-znoexecstack
  CFG_GCCISH_CFLAGS_i386 = -m32
  CFG_GCCISH_LINK_FLAGS_i386 = -m32
  CFG_GCCISH_CFLAGS_x86_64 = -m64
  CFG_GCCISH_LINK_FLAGS_x86_64 = -m64
  CFG_UNIXY := 1
  CFG_LDENV := LD_LIBRARY_PATH
  CFG_DEF_SUFFIX := .linux.def
  ifdef CFG_PERF
    ifneq ($(CFG_PERF_WITH_LOGFD),)
        CFG_PERF_TOOL := $(CFG_PERF) stat -r 3 --log-fd 2
    else
        CFG_PERF_TOOL := $(CFG_PERF) stat -r 3
    endif
  else
    ifdef CFG_VALGRIND
      CFG_PERF_TOOL :=\
        $(CFG_VALGRIND) --tool=cachegrind --cache-sim=yes --branch-sim=yes
    else
      CFG_PERF_TOOL := /usr/bin/time --verbose
    endif
  endif
  CFG_INSTALL_NAME =
  # Linux requires LLVM to be built like this to get backtraces into Rust code
  CFG_LLVM_BUILD_ENV="CXXFLAGS=-fno-omit-frame-pointer"
endif

ifneq ($(findstring darwin,$(CFG_OSTYPE)),)
  CFG_LIB_NAME=lib$(1).dylib
  CFG_LIB_GLOB=lib$(1)-*.dylib
  CFG_UNIXY := 1
  CFG_LDENV := DYLD_LIBRARY_PATH
  CFG_GCCISH_LINK_FLAGS += -dynamiclib -lpthread -framework CoreServices -Wl,-no_compact_unwind
  CFG_GCCISH_DEF_FLAG := -Wl,-exported_symbols_list,
  # Darwin has a very blurry notion of "64 bit", and claims it's running
  # "on an i386" when the whole userspace is 64-bit and the compiler
  # emits 64-bit binaries by default. So we just force -m32 here. Smarter
  # approaches welcome!
  #
  # NB: Currently GCC's optimizer breaks rustrt (task-comm-1 hangs) on Darwin.
  CFG_GCCISH_CFLAGS_i386 := -m32 -arch i386
  CFG_GCCISH_CFLAGS_x86_64 := -m64 -arch x86_64
  CFG_GCCISH_LINK_FLAGS_i386 := -m32
  CFG_GCCISH_LINK_FLAGS_x86_64 := -m64
  CFG_DSYMUTIL := dsymutil
  CFG_DEF_SUFFIX := .darwin.def
  # Mac requires this flag to make rpath work
  CFG_INSTALL_NAME = -Wl,-install_name,@rpath/$(1)
endif

# Hack: not sure how to test if a file exists in make other than this
OS_SUPP = $(patsubst %,--suppressions=%,\
	    $(wildcard $(CFG_SRC_DIR)src/etc/$(CFG_OSTYPE).supp*))

ifneq ($(findstring mingw,$(CFG_OSTYPE)),)
  CFG_WINDOWSY := 1
endif

ifdef CFG_DISABLE_OPTIMIZE_CXX
  $(info cfg: disabling C++ optimization (CFG_DISABLE_OPTIMIZE_CXX))
  CFG_GCCISH_CFLAGS += -O0
else
  CFG_GCCISH_CFLAGS += -O2
endif

CFG_TESTLIB=$(CFG_BUILD_DIR)/$(2)/$(strip \
 $(if $(findstring stage0,$(1)), \
       stage0/$(CFG_LIBDIR), \
      $(if $(findstring stage1,$(1)), \
           stage1/$(CFG_LIBDIR), \
          $(if $(findstring stage2,$(1)), \
               stage2/$(CFG_LIBDIR), \
               $(if $(findstring stage3,$(1)), \
                    stage3/$(CFG_LIBDIR), \
               )))))/rustc/$(CFG_HOST_TRIPLE)/$(CFG_LIBDIR)

ifdef CFG_UNIXY
  CFG_INFO := $(info cfg: unix-y environment)

  CFG_PATH_MUNGE := true
  CFG_EXE_SUFFIX :=
  CFG_LDPATH :=
  CFG_RUN=$(2)
  CFG_RUN_TARG=$(call CFG_RUN,,$(2))
  CFG_RUN_TEST=$(call CFG_RUN,,$(CFG_VALGRIND) $(1))
  CFG_LIBUV_LINK_FLAGS=-lpthread

  ifdef CFG_ENABLE_MINGW_CROSS
    CFG_WINDOWSY := 1
    CFG_INFO := $(info cfg: mingw-cross)
    CFG_GCCISH_CROSS := i586-mingw32msvc-
    ifdef CFG_VALGRIND
      CFG_VALGRIND += wine
    endif

    CFG_GCCISH_CFLAGS := -fno-strict-aliasing -march=i586
    CFG_GCCISH_PRE_LIB_FLAGS :=
    CFG_GCCISH_POST_LIB_FLAGS :=
    CFG_GCCISH_DEF_FLAG :=
    CFG_GCCISH_LINK_FLAGS := -shared

    ifeq ($(CFG_CPUTYPE), x86_64)
      CFG_GCCISH_CFLAGS += -m32
      CFG_GCCISH_LINK_FLAGS += -m32
    endif
  endif
  ifdef CFG_VALGRIND
    CFG_VALGRIND += --leak-check=full \
                    --error-exitcode=100 \
                    --quiet \
                    --suppressions=$(CFG_SRC_DIR)src/etc/x86.supp \
                    $(OS_SUPP)
  endif
endif


ifdef CFG_WINDOWSY
  CFG_INFO := $(info cfg: windows-y environment)

  CFG_EXE_SUFFIX := .exe
  CFG_LIB_NAME=$(1).dll
  CFG_LIB_GLOB=$(1)-*.dll
  CFG_DEF_SUFFIX := .def
ifdef MSYSTEM
  CFG_LDPATH :=$(CFG_LDPATH):$$PATH
  CFG_RUN=PATH="$(CFG_LDPATH):$(1)" $(2)
else
  CFG_LDPATH :=
  CFG_RUN=$(2)
endif
  CFG_RUN_TARG=$(call CFG_RUN,$(HLIB$(1)_H_$(CFG_HOST_TRIPLE)),$(2))
  CFG_RUN_TEST=$(call CFG_RUN,$(call CFG_TESTLIB,$(1),$(3)),$(1))
  CFG_LIBUV_LINK_FLAGS=-lWs2_32

  ifndef CFG_ENABLE_MINGW_CROSS
    CFG_PATH_MUNGE := $(strip perl -i.bak -p             \
                             -e 's@\\(\S)@/\1@go;'       \
                             -e 's@^/([a-zA-Z])/@\1:/@o;')
    CFG_GCCISH_CFLAGS += -march=i686
    CFG_GCCISH_LINK_FLAGS += -shared -fPIC
  endif
  CFG_INSTALL_NAME =
endif


CFG_INFO := $(info cfg: using $(CFG_C_COMPILER))
ifeq ($(CFG_C_COMPILER),clang)
  CC=clang
  CXX=clang++
  CPP=cpp
  # -Wno-c++11-compat allows us to use 'alignof' as an identifier in the runtime
  CFG_GCCISH_CFLAGS += -Wall -Werror -Wno-c++11-compat -fno-rtti -g
  CFG_GCCISH_LINK_FLAGS += -g
  CFG_DEPEND_C = $(CFG_GCCISH_CROSS)$(CXX) $(CFG_GCCISH_CFLAGS) -MT "$(1)" \
    -MM $(2)

  define CFG_MAKE_CC
	CFG_COMPILE_C_$(1) = $$(CFG_GCCISH_CROSS)$$(CXX)	\
		$$(CFG_GCCISH_CFLAGS) $$(CFG_CLANG_CFLAGS)		\
		$$(CFG_GCCISH_CFLAGS_$$(HOST_$(1)))				\
	    $$(CFG_CLANG_CFLAGS_$$(HOST_$(1)))				\
		-c -o $$(1) $$(2)
    CFG_LINK_C_$(1) = $$(CFG_GCCISH_CROSS)$$(CXX)	\
		$$(CFG_GCCISH_LINK_FLAGS) -o $$(1)			\
		$$(CFG_GCCISH_LINK_FLAGS_$$(HOST_$(1)))		\
        $$(CFG_GCCISH_DEF_FLAG)$$(3) $$(2)			\
	    $$(call CFG_INSTALL_NAME,$$(4))
  endef

  $(foreach target,$(CFG_TARGET_TRIPLES), \
    $(eval $(call CFG_MAKE_CC,$(target))))
else
ifeq ($(CFG_C_COMPILER),gcc)
  CC=gcc
  CXX=g++
  CPP=cpp
  CFG_GCCISH_CFLAGS += -Wall -Werror -fno-rtti -g
  CFG_GCCISH_LINK_FLAGS += -g
  CFG_DEPEND_C = $(CFG_GCCISH_CROSS)$(CXX) $(CFG_GCCISH_CFLAGS) -MT "$(1)" \
    -MM $(2)

  define CFG_MAKE_CC
	CFG_COMPILE_C_$(1) = $$(CFG_GCCISH_CROSS)$$(CXX)	\
        $$(CFG_GCCISH_CFLAGS)							\
	    $$(CFG_GCCISH_CFLAGS_$$(HOST_$(1)))				\
        $$(CFG_GCC_CFLAGS)								\
        $$(CFG_GCC_CFLAGS_$$(HOST_$(1)))				\
        -c -o $$(1) $$(2)
    CFG_LINK_C_$(1) = $$(CFG_GCCISH_CROSS)$$(CXX)	\
        $$(CFG_GCCISH_LINK_FLAGS) -o $$(1)			\
		$$(CFG_GCCISH_LINK_FLAGS_$$(HOST_$(1)))		\
        $$(CFG_GCCISH_DEF_FLAG)$$(3) $$(2)			\
        $$(call CFG_INSTALL_NAME,$$(4))
  endef

  $(foreach target,$(CFG_TARGET_TRIPLES), \
    $(eval $(call CFG_MAKE_CC,$(target))))
else
  CFG_ERR := $(error please try on a system with gcc or clang)
endif
endif

# We're using llvm-mc as our assembler because it supports
# .cfi pseudo-ops on mac
define CFG_MAKE_ASSEMBLER
  CFG_ASSEMBLE_$(1)=$$(CPP) $$(2) | \
                    $$(LLVM_MC_$$(CFG_HOST_TRIPLE)) \
                    -assemble \
                    -filetype=obj \
                    -triple=$(1) \
                    -o=$$(1)
endef

$(foreach target,$(CFG_TARGET_TRIPLES),\
  $(eval $(call CFG_MAKE_ASSEMBLER,$(target))))
