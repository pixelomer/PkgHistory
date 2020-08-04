include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PkgHistory

PkgHistory_FILES = $(wildcard *.m)
PkgHistory_FRAMEWORKS = UIKit
PkgHistory_CFLAGS = -fobjc-arc

#
# If you aren't on macOS or if you are in a future where qlmanage doesn't work/exist,
# you can replace it with something else as long as it converts icon.svg to PNG and
# writes it to ${template}
#
# ImageMagick is required since the "convert" command is used. ImageMagick isn't used
# for converting icon.svg to PNG since it can't do it properly (or I can't use it
# properly :P)
#
internal-stage:: icon.svg
	@	path="$(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app"; \
		template="$${path}/icon.svg.png"; \
		AppIcon="$${path}/AppIcon"; \
		verbose=false; \
		mkdir -p "$${path}"; \
		$(PRINT_FORMAT_GREEN) "Converting icon.svg to PNG"; \
		qlmanage -t -s 512 -o "$${path}" icon.svg; \
		$(PRINT_FORMAT_GREEN) "Creating app icons"; \
		resize() { \
			size=$$(($$1 * $$2)); \
			suffix=""; \
			if [ $$2 -ne 1 ]; then \
				suffix="@$$2x"; \
			fi; \
			final="$${AppIcon}$$1x$$1$${suffix}.png"; \
			$${verbose} && echo "Creating $$(basename "$${final}")..."; \
			convert -scale $${size} "$${template}" "$${final}"; \
		}; \
		in=(29 1 29 2 29 3 40 1 40 2 40 3 50 1 50 2 57 1 57 2 57 3 60 1 60 2 60 3 72 1 72 2 76 1 76 2); \
		for ((i=0; i<$${#in[@]}; i+=2)); do \
			resize $${in[$$i]} $${in[$$(($$i+1))]}; \
		done;

include $(THEOS_MAKE_PATH)/application.mk