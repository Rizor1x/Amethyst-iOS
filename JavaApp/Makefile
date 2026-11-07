# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java')

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d)
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)

# Add all jars to classpath and allow compiling with private API
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(wildcard libs/*/*.jar))" -XDignore.symbol.file

all: $(TARGETS)

# Each jar owns its class directory. Shared sources remain on the classpath
# without letting concurrent javac invocations write the same class files.
$(OUTPUTDIR)/.%.compiled: $(SOURCES) Makefile
	@rm -f $@
	@rm -rf $(OUTPUTDIR)/$*
	@mkdir -p $(OUTPUTDIR)/$*
	@echo "Compiling $*"
	@$(BOOTJDK)/javac $(JCFLAGS) -implicit:none -d $(OUTPUTDIR)/$* $(filter $(SOURCEDIR)/$*/%,$(SOURCES))
	@empty_classes=$$(find $(OUTPUTDIR)/$* -name '*.class' -size 0); \
	if [ -n "$$empty_classes" ]; then \
		echo "Error: found empty class files: $$empty_classes"; \
		exit 1; \
	fi
	@touch $@

$(OUTPUTDIR)/launcher.jar: $(OUTPUTDIR)/.launcher.compiled
	@set -e
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .

$(OUTPUTDIR)/lwjgl.jar: $(OUTPUTDIR)/.lwjgl.compiled
	@set -e
	@echo "Creating $@"
	@rm -rf $(OUTPUTDIR)/lwjgl_lib
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib
	@cd $(OUTPUTDIR)/lwjgl_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib .

$(OUTPUTDIR)/patchjna_agent.jar: $(OUTPUTDIR)/.patchjna_agent.compiled $(SOURCEDIR)/patchjna_agent.txt
	@set -e
	@if [ -f $(basename $@)/com/sun/jna/Platform.class ]; then \
		mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch; \
	fi
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean
