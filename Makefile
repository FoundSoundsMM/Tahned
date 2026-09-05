# TAHNED
#
# `make test` boots the script against a headless stand-in for the norns API
# and drives every page, key and encoder. it does not need norns or
# SuperCollider, so it can run on any machine with lua5.3+.

LUA ?= lua
SCLANG ?= /Applications/SuperCollider.app/Contents/MacOS/sclang

.PHONY: test check glyphs sc clean

test:
	@$(LUA) test/run.lua

diag:
	@$(LUA) test/diag.lua

# parse every lua file without running it
check:
	@for f in tahned.lua lib/*.lua lib/ui/*.lua; do \
		$(LUA) -e "local c,e = loadfile('$$f') if e then print('FAIL '..e) os.exit(1) end" || exit 1; \
	done
	@echo "all lua files parse"

# docs/GLYPHS.md is generated; lib/glyph.lua is the source of truth
glyphs:
	@python3 tools/gen_glyphs.py

# compile the engine class and build its synthdefs without a norns
sc:
	@python3 tools/sc_check.py

clean:
	@rm -rf build

