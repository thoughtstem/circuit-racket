ifneq ($(MKENV_INCLUDED),1)
# We assume that mkenv is in the same directory as this file.
THIS_MAKEFILE = $(lastword $(MAKEFILE_LIST))
include $(dir $(THIS_MAKEFILE))mkenv.mk
endif

# This file expects that OBJ contains a list of all of the object files.
# The directory portion of each object file is used to locate the source
# and should not contain any ..'s but rather be relative to the top of the
# tree.
#
# So for example, py/map.c would have an object file name py/map.o
# The object files will go into the build directory and mantain the same
# directory structure as the source tree. So the final dependency will look
# like this:
#
# build/py/map.o: py/map.c
#
# We set vpath to point to the top of the tree so that the source files
# can be located. By following this scheme, it allows a single build rule
# to be used to compile all .c files.

vpath %.S . $(TOP)
$(BUILD)/%.o: %.S
	$(STEPECHO) "CC $<"
	$(Q)$(CC) $(CFLAGS) -c -o $@ $<

vpath %.s . $(TOP)
$(BUILD)/%.o: %.s
	$(STEPECHO) "AS $<"
	$(Q)$(AS) -o $@ $<

define compile_c
$(STEPECHO) "CC $<"
$(Q)$(CC) $(CFLAGS) -c -MD -o $@ $<
@# The following fixes the dependency file.
@# See http://make.paulandlesley.org/autodep.html for details.
@# Regex adjusted from the above to play better with Windows paths, etc.
@$(CP) $(@:.o=.d) $(@:.o=.P); \
  $(SED) -e 's/#.*//' -e 's/^.*:  *//' -e 's/ *\\$$//' \
      -e '/^$$/ d' -e 's/$$/ :/' < $(@:.o=.d) >> $(@:.o=.P); \
  $(RM) -f $(@:.o=.d)
endef

vpath %.c . $(TOP)
$(BUILD)/%.o: %.c
	$(call compile_c)

# frozen.c and frozen_mpy.c are created in $(BUILD), so use our rule
# for those as well.
vpath %.c . $(BUILD)
$(BUILD)/%.o: %.c
	$(call compile_c)

# List all native flags since the current build system doesn't have
# the MicroPython configuration available. However, these flags are
# needed to extract all qstrings
QSTR_GEN_EXTRA_CFLAGS += -DNO_QSTR -DN_X64 -DN_X86 -DN_THUMB -DN_ARM -DN_XTENSA
QSTR_GEN_EXTRA_CFLAGS += -I$(BUILD)/tmp

vpath %.c . $(TOP)

$(BUILD)/%.pp: %.c
	$(STEPECHO) "PreProcess $<"
	$(Q)$(CC) $(CFLAGS) -E -Wp,-C,-dD,-dI -o $@ $<

# The following rule uses | to create an order only prerequisite. Order only
# prerequisites only get built if they don't exist. They don't cause timestamp
# checking to be performed.
#
# We don't know which source files actually need the generated.h (since
# it is #included from str.h). The compiler generated dependencies will cause
# the right .o's to get recompiled if the generated.h file changes. Adding
# an order-only dependency to all of the .o's will cause the generated .h
# to get built before we try to compile any of them.
$(OBJ): | $(HEADER_BUILD)/qstrdefs.generated.h $(HEADER_BUILD)/mpversion.h

$(HEADER_BUILD)/qstr.i.last: $(SRC_QSTR) | $(HEADER_BUILD)/mpversion.h
	$(ECHO) "GEN $@"
	$(Q)$(CPP) $(QSTR_GEN_EXTRA_CFLAGS) $(CFLAGS) $(if $?,$?,$^) >$(HEADER_BUILD)/qstr.i.last;

$(HEADER_BUILD)/qstr.split: $(HEADER_BUILD)/qstr.i.last
	$(STEPECHO) "GEN $@"
	$(Q)$(PYTHON) $(PY_SRC)/makeqstrdefs.py split $(HEADER_BUILD)/qstr.i.last $(HEADER_BUILD)/qstr $(QSTR_DEFS_COLLECTED)
	$(Q)touch $@

$(QSTR_DEFS_COLLECTED): $(HEADER_BUILD)/qstr.split
	$(STEPECHO) "GEN $@"
	$(Q)$(PYTHON) $(PY_SRC)/makeqstrdefs.py cat $(HEADER_BUILD)/qstr.i.last $(HEADER_BUILD)/qstr $(QSTR_DEFS_COLLECTED)

# $(sort $(var)) removes duplicates
#
# The net effect of this, is it causes the objects to depend on the
# object directories (but only for existence), and the object directories
# will be created if they don't exist.
OBJ_DIRS = $(sort $(dir $(OBJ)))
$(OBJ): | $(OBJ_DIRS)
$(OBJ_DIRS):
	$(Q)$(MKDIR) -p $@

$(HEADER_BUILD):
	$(Q)$(MKDIR) -p $@

ifneq ($(FROZEN_DIR),)
$(BUILD)/frozen.c: $(wildcard $(FROZEN_DIR)/*) $(HEADER_BUILD) $(FROZEN_EXTRA_DEPS)
	$(STEPECHO) "Generating $@"
	$(Q)$(MAKE_FROZEN) $(FROZEN_DIR) > $@
endif

ifneq ($(FROZEN_MPY_DIRS),)
# to build the MicroPython cross compiler
# Currently not used, because the wrong mpy-cross may be left over from a previous build. Build by hand to make sure.
$(MPY_CROSS): $(TOP)/py/*.[ch] $(TOP)/mpy-cross/*.[ch] $(TOP)/windows/fmode.c
	$(Q)$(MAKE) -C $(TOP)/mpy-cross

# Copy all the modules and single python files to freeze to a common area, omitting top-level dirs (the repo names).
# Do any preprocessing necessary: currently, this adds version information, removes examples, and
# non-library .py files in the modules (setup.py and conf.py)
# Then compile .mpy files from all the .py files, placing them in the same directories as the .py files.
$(BUILD)/frozen_mpy: $(FROZEN_MPY_DIRS)
	$(ECHO) FREEZE $(FROZEN_MPY_DIRS)
	$(Q)$(MKDIR) -p $@
	$(Q)$(PREPROCESS_FROZEN_MODULES) -o $@ $(FROZEN_MPY_DIRS)
	$(Q)$(CD) $@ && \
$(FIND) -L . -type f -name '*.py' | sed 's=^\./==' | \
xargs -n1 $(abspath $(MPY_CROSS)) $(MPY_CROSS_FLAGS)

# to build frozen_mpy.c from all .mpy files
# You need to define MPY_TOOL_LONGINT_IMPL in mpconfigport.mk
# if the default will not work (mpz is the default).
$(BUILD)/frozen_mpy.c: $(BUILD)/frozen_mpy $(BUILD)/genhdr/qstrdefs.generated.h
	$(STEPECHO) "Creating $@"
	$(Q)$(PYTHON) $(MPY_TOOL) $(MPY_TOOL_LONGINT_IMPL) -f -q $(BUILD)/genhdr/qstrdefs.preprocessed.h $(shell $(FIND) -L $(BUILD)/frozen_mpy -type f -name '*.mpy') > $@
endif

ifneq ($(PROG),)
# Build a standalone executable (unix does this)

all: $(PROG)

$(PROG): $(OBJ)
	$(STEPECHO) "LINK $@"
# Do not pass COPT here - it's *C* compiler optimizations. For example,
# we may want to compile using Thumb, but link with non-Thumb libc.
	$(Q)$(CC) -o $@ $^ $(LIB) $(LDFLAGS)
ifndef DEBUG
	$(Q)$(STRIP) $(STRIPFLAGS_EXTRA) $(PROG)
endif
	$(Q)$(SIZE) $$(find $(BUILD) -path "$(BUILD)/build/frozen*.o") $(PROG)

clean: clean-prog
clean-prog:
	$(RM) -f $(PROG)
	$(RM) -f $(PROG).map

.PHONY: clean-prog
endif

LIBMICROPYTHON = libmicropython.a

# We can execute extra commands after library creation using
# LIBMICROPYTHON_EXTRA_CMD. This may be needed e.g. to integrate
# with 3rd-party projects which don't have proper dependency
# tracking. Then LIBMICROPYTHON_EXTRA_CMD can e.g. touch some
# other file to cause needed effect, e.g. relinking with new lib.
lib $(LIBMICROPYTHON): $(OBJ)
	$(AR) rcs $(LIBMICROPYTHON) $^
	$(LIBMICROPYTHON_EXTRA_CMD)

clean:
	$(RM) -rf $(BUILD) $(CLEAN_EXTRA)
.PHONY: clean

print-cfg:
	$(ECHO) "PY_SRC = $(PY_SRC)"
	$(ECHO) "BUILD  = $(BUILD)"
	$(ECHO) "OBJ    = $(OBJ)"
.PHONY: print-cfg

print-def:
	@$(ECHO) "The following defines are built into the $(CC) compiler"
	touch __empty__.c
	@$(CC) -E -Wp,-dM __empty__.c
	@$(RM) -f __empty__.c

-include $(OBJ:.o=.P)