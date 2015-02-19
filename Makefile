APP_FILES=$(shell find . -name '*.lua')
LUVI_URL=https://github.com/luvit/luvi/releases/download/$LUVI_VERSION/luvi-static-`uname -s`_`uname -m`

lit: luvi $(APP_FILES)
	LUVI_APP=. ./luvi make

luvi:
	curl -L $(LUVI_URL) > luvi
	chmod +x luvi

test: lit
	tests/run.sh

clean:
	rm -rf lit luvi test-offline test-pull test-push test-server

install: lit
	install lit /usr/local/bin

deploy: lit
	sudo systemctl stop lit
	install lit /usr/local/bin
	sudo systemctl start lit

uninstall:
	rm -f /usr/local/bin/lit

lint:
	luacheck $(APP_FILES)
